# Fase 1.5 — política canónica DST y corrección de recurrencias

## Diagnóstico de la causa raíz

El propietario reporta que Xcode 26.6/Swift 6.3.3 ejecutó las doce pruebas: once PASS y `testWeeklyDSTGapUsesSavedTimeZone` FAIL. El resultado fue 2026-03-08 07:00 UTC frente a 07:30 UTC esperado. No se ha ejecutado una nueva compilación remota en esta sesión.

La zona guardada es America/New_York. El inicio 2026-03-01 07:30 UTC corresponde a **02:30 local**. El 8 de marzo el reloj salta de 01:59:59 a 03:00:00 y 02:30 no existe. El resultado obtenido equivale a 03:00 local; el esperado, a 03:30 local.

Swift usaba `Calendar.date(bySettingHour:...)` con `.nextTimePreservingSmallerComponents`. El [código público de Foundation](https://github.com/swiftlang/swift-foundation/blob/main/Sources/FoundationEssentials/Calendar/Calendar.swift) muestra que esa función restringe las políticas aceptadas y convierte la solicitada en `.nextTime`. Ese comportamiento coincide con el fallo real reportado: se salta al primer minuto válido en lugar de mantener la posición dentro del hueco. La referencia pública explica el comportamiento; no se afirma haber inspeccionado el binario concreto de Foundation del runner.

## Contrato existente de Android, inspeccionado solo en lectura

`domain/src/main/kotlin/mx/listaclara/domain/Events.kt` obtiene la hora local del inicio en la zona guardada, fija segundos/nanosegundos a cero y resuelve cada día con `day.atTime(startTime).atZone(tz)`. `domain/src/test/kotlin/mx/listaclara/domain/EventsTest.kt`, prueba `missingHourMovesToNextValidHour`, ya espera **2026-03-08T07:30:00Z** para 02:30 en Nueva York. No se cambió Android ni su expectativa.

La [especificación Java LocalDateTime.atZone](https://docs.oracle.com/en/java/javase/17/docs/api/java.base/java/time/LocalDateTime.html#atZone(java.time.ZoneId)) establece desplazamiento por la duración del hueco y selección de la primera ocurrencia cuando hay solapamiento. Esta es la política canónica, no “primer minuto válido”.

Hashes de los archivos Android leídos, comprobados al finalizar:

- Events.kt: `c502de8568a2a158ccf2ea7cd6a043cd9e0a325a122a966d1f534ab0de20c285`.
- EventsTest.kt: `37a626c82e3a71f6e7fcc9d61fef32f7573d5d43e7177dbfbf20ecd50bed6dd3`.

## Regla canónica para ambas plataformas

1. Usar calendario gregoriano y la zona IANA **guardada**, independientemente de la del teléfono.
2. Conservar la hora/minuto originales del inicio para cada día seleccionado; no convertir la corrección de una ocasión en una nueva hora permanente.
3. Hora válida: entregar ese instante.
4. Hueco: desplazar la hora local por la duración exacta del salto. Nueva York 02:30 → 03:30; Lord Howe 02:15 → 02:45 con salto de media hora. No imponer una hora fija ni redondear al inicio del periodo válido.
5. Solapamiento: elegir el primer instante, incluso si el inicio original estuvo en otro offset. No entregar la segunda aparición cuando la primera ya pasó; buscar la próxima ocasión semanal.
6. Conservar `candidate >= start`, `candidate > after`, duración exclusiva y días seleccionados. ONCE sigue siendo un instante absoluto e INTERVAL conserva tiempo transcurrido, no días civiles.

## Parche limitado a la resolución semanal

Se añade un helper privado de unas treinta líneas a `Sources/Core/Recurrence.swift` y se sustituye únicamente la llamada que resolvía la hora semanal.

El helper representa la fecha/hora local nominal en UTC, solo como eje de cálculo sin DST. Recoge los offsets vigentes al inicio/fin del día y justo antes de su inicio. Cada offset propone un instante UTC; se verifica de nuevo contra el offset real de la zona en ese instante. Si hay uno o dos candidatos exactos, devuelve el más temprano. Si no hay exacto y existe un salto positivo, devuelve el candidato desplazado por ese salto. Así trata cambios de una hora, media hora y transiciones a medianoche sin depender de la política restringida de `date(bySettingHour:)`.

No se modifican las ramas ONCE/INTERVAL, los filtros de inicio/cursor/fin, la representación JSON, identidad de ocurrencias, backend, autenticación, permisos, avisos o servicios. No se cambia la configuración Xcode ni Codemagic.

## Pruebas de regresión preparadas

La expectativa original **se mantiene sin cambios**. Se conservan los doce tests anteriores y se añaden diez (22 en total):

- Primavera Nueva York y regreso a 02:30 la semana posterior.
- Otoño Nueva York: primera aparición y omisión de la segunda si ya pasó la primera.
- Fechas normales y medianoche exacta.
- Zona guardada Nueva York con zona por defecto del proceso Asia/Tokyo, restaurada al finalizar.
- Primavera y otoño Lord Howe, con cambio de 30 minutos.
- ONCE e INTERVAL de 24 horas cruzando DST.
- Fin exclusivo en medianoche de la zona guardada.
- Tabla de seis casos compatibles con la regla atZone de Android, incluyendo Berlín.

Las comparaciones usan variables de tipo explícito cuando corresponde para conservar la corrección anterior de inferencia en Swift 6.3.3. No se desactiva ninguna prueba.

## Resultados verificados y límites

| Comprobación | Resultado |
|---|---|
| Suite CI Python | 7/7 PASS |
| Misma suite con padre temporal symlink | 7/7 PASS |
| Seis fixtures DST de XCTest frente a IANA/fold=0 | 6/6 PASS, con herramienta de referencia Python |
| Modelo independiente del resolver frente a IANA, cada minuto de once días/zonas | 15.840/15.840 PASS |
| Estructura Xcode, referencias, esquema e Info.plist | PASS estructural |
| Sintaxis Python/Bash y configuración Codemagic | PASS |
| Android de referencia | Hashes sin cambios; solo lectura |
| Ejecución de 22 XCTest Swift | **Pendiente**: Swift/Xcode no disponibles en Debian |
| Referencia Java real | **Pendiente**: no hay JDK instalado |
| Nuevo build Codemagic / instalación iPhone | **No ejecutados** |

El modelo Python no es el código Swift: sus resultados respaldan el algoritmo y los fixtures, no prueban la compilación ni ejecución de Foundation. El test de paridad también necesita ejecutar XCTest en Codemagic para verificar iOS. No se afirma haber ejecutado el APK Android.

Los once días del modelo incluyen primavera/otoño en Nueva York, Berlín y Lord Howe, fecha normal, México sin DST actual y cambios históricos a medianoche en La Habana, Katmandú y São Paulo. Evidencia externa: `/tmp/ListaClara-iOS-fase1.5-evidence`. No se ejecutaron pruebas que importen o modifiquen el backend.

## Reproducción independiente de la referencia

Sin Swift ni JDK:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 Tools/check_dst_reference.py
```

El comando comprueba los mismos seis fixtures inline del test Swift con la base IANA. Informa SKIP explícito si no hay Java. Con un JDK 11+ disponible, también ejecuta `Tools/AndroidWeeklyOracle.java`, que reproduce las operaciones Java de la rama semanal sin abrir ni modificar Android:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 Tools/check_dst_reference.py --java /ruta/al/jdk/bin/java
java Tools/AndroidWeeklyOracle.java America/New_York 2026-03-01T07:30:00Z 2026-03-08T00:00:00Z 7 2
```

El último comando debe producir 2026-03-08T07:30:00Z y 2026-03-15T06:30:00Z. No se agregó un requisito Java al workflow normal: Swift ejecuta sus propios fixtures sin dependencias nuevas.

## Incorporar el commit y validar en Codemagic

La ruta iOS permanente permanece fuera de las rutas de escritura de la sesión. El commit independiente en main se prepara en `/tmp/ListaClara-iOS-fase1.5`, con base exacta **8eabc8b08d931567c92d0497de1d03ed19c177eb**, y se entrega como bundle Git. No se modifica automáticamente el checkout permanente ni se hace git push.

En la terminal normal del propietario:

```bash
(
set -e
cd /home/dexanox/Servicios/TaskFamily/ListaClara-iOS
test "$(git branch --show-current)" = main
test -z "$(git status --porcelain)"
test "$(git rev-parse HEAD)" = 8eabc8b08d931567c92d0497de1d03ed19c177eb
git bundle verify /tmp/ListaClara-iOS-fase1.5-fix.bundle
git fetch /tmp/ListaClara-iOS-fase1.5-fix.bundle main
git merge --ff-only FETCH_HEAD
PYTHONDONTWRITEBYTECODE=1 python3 ci/test_tools.py
PYTHONDONTWRITEBYTECODE=1 python3 Tools/check_dst_reference.py
sha256sum -c MANIFEST.sha256
)
```

Solo después de autorizar y efectuar su subida, iniciar **Start new build → main → ios-validate** y verificar el nuevo SHA. Deben pasar las 22 pruebas, los tests hospedados en simulador y la compilación Release de dispositivo. Conservar ID real, Xcode/Swift, logs y xcresult. No declarar compilación completa de iPhone hasta obtener esa evidencia; firma/distribución siguen siendo fases separadas.
