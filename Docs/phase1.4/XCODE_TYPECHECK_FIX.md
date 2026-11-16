# Fase 1.4 — corrección mínima de la prueba Swift

## Evidencia recibida

El propietario comunica el error real del build **6afb636601609fea8f691b8a**, commit **2624a70**, workflow **ios-validate**, Mac mini M2, Xcode **26.6** y Swift **6.3.3**. El paso de preparación terminó y la compilación avanzó a `Run Swift Core and iPhone simulator XCTest`.

En `Tests/CoreTests.swift`, línea 56 del commit base, el compilador informa: “The compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions.” La expresión combina XCTAssertEqual genérico, map por key path y un array de expresiones aritméticas cuyo tipo debía inferirse. Se actúa sobre ese diagnóstico proporcionado; no se ha descargado el log completo del servicio ni ejecutado otra compilación remota en esta sesión.

## Cambio y conservación de la intención

`testWeeklyUsesStartClockInsteadOfLegacyTimes` ahora prepara `actual` y `expected` como `[TimeInterval]` antes de llamar a `XCTAssertEqual(actual, expected)`. Los literales aritméticos esperados son explícitamente decimales. Los resultados siguen siendo **381600** y **986400** segundos desde epoch: cuatro/once días más diez horas. El evento, zona, límites y datos de entrada no cambian.

La revisión encontró otra comparación de la misma forma en `testIntervalExclusiveEndAndStrictAfter`, aunque sin aritmética compleja y sin error reportado. Se separó igualmente en variables `[TimeInterval]` conservando **28800** y **57600** segundos. No se modificaron otras pruebas ni se eliminaron aserciones: siguen existiendo doce casos XCTest.

No se encontró otra aserción equivalente con map y array aritmético. Las demás construcciones no se modificaron sin evidencia. **Sources/Core/Recurrence.swift y todo el código productivo permanecen idénticos.** Tampoco cambian Package.swift, configuración Xcode/Codemagic, scripts CI, versión, autenticación, permisos o backend.

Archivos del commit: `Tests/CoreTests.swift`, `CHANGELOG.md`, este informe y `MANIFEST.sha256`.

## Verificación disponible en Debian

- Siete pruebas Python de configuración/salvaguardas CI: PASS.
- Las mismas siete pruebas con TMPDIR mediante symlink: PASS; conserva la corrección del preflight anterior.
- Estructura OpenStep Xcode, referencias, fuentes, esquema e Info.plist: PASS. No es compilación Apple.
- Parseo JSON compatible YAML de Codemagic y coherencia de workflows/bundle: PASS.
- Sintaxis Bash, AST Python y git diff --check: PASS.
- Equivalencia numérica exacta de los valores antes/después: comprobada, sin cambiar la intención de recurrencia.
- Doce casos XCTest y sus aserciones conservados; ningún archivo Sources cambiado.

No hay `swift`, `swiftc` o `xcodebuild` en esta máquina. **No se ejecutaron las pruebas Swift ni se verificó su sintaxis/typechecking con un compilador local.** Eso lo realizará el workflow real. No se afirma éxito del build ni se han observado errores Apple adicionales aquí.

Evidencia de ejecución local: `/tmp/ListaClara-iOS-fase1.4-evidence`.

## Incorporación segura a main

El sandbox mantiene la carpeta iOS permanente fuera de sus rutas de escritura. Se preparó un commit independiente en `main` dentro de `/tmp/ListaClara-iOS-fase1.4`, a partir de **2624a706696fd0da4bdb26e8f541418231034a82**. El checkout permanente y su remoto no se modifican automáticamente.

Desde la terminal normal del propietario:

```bash
(
set -e
cd /home/dexanox/Servicios/TaskFamily/ListaClara-iOS
test "$(git branch --show-current)" = main
test -z "$(git status --porcelain)"
test "$(git rev-parse HEAD)" = 2624a706696fd0da4bdb26e8f541418231034a82
git bundle verify /tmp/ListaClara-iOS-fase1.4-fix.bundle
git fetch /tmp/ListaClara-iOS-fase1.4-fix.bundle main
git merge --ff-only FETCH_HEAD
PYTHONDONTWRITEBYTECODE=1 python3 ci/test_tools.py
sha256sum -c MANIFEST.sha256
)
```

El bloque se detiene si el checkout cambió o está sucio. No hace push, no reescribe historial y no necesita elevación. Después de autorizar separadamente y realizar la subida del nuevo commit, iniciar **Start new build → main → ios-validate** en Codemagic. Verificar que se usa el nuevo SHA, no repetir el build del commit 2624a70.

Guardar el nuevo ID real y los logs de `swift test`, XCTest de simulador y compilación Release. Si surge otro error, conservar su archivo/línea/mensaje antes de corregirlo. Solo el resultado completo de Xcode permite declarar éxito.
