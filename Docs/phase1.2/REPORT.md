# Informe verificable — Fase 1.2

## Estado de los entregables

| Entregable | Resultado actual |
|---|---|
| Reutilización del proyecto | Original tar.gz y sus 32 hashes verificados; extraído sin comenzar de nuevo |
| Copia de seguridad | Original preservado, copia adicional, historial local y bundle Git verificable |
| Ubicación permanente | Bloqueada por sandbox; instalador y comando exacto en CONSERVATION.md |
| Repositorio independiente | Git local, rama main, sin remoto externo; la privacidad de un repositorio remoto aún no existe porque no se creó/subió |
| Codemagic | YAML con workflows ios-validate e ios-adhoc, scripts y evidencia automática preparados; no ejecutado en el servicio |
| Compilación Xcode real | **No ejecutada**: sin conexión/cuenta/token/app Codemagic configurados en esta sesión; Xcode no existe en Debian |
| Firma / IPA | **No generado**: certificados/perfil/equipo/UDID Apple no proporcionados/verificados |
| Instalación física | **No probada; no declarar lista para instalar** |

## Comprobaciones ejecutadas en Debian

- SHA-256 original coincide con la entrega anterior; todos sus archivos de manifiesto pasan integridad.
- Validación estructural `.xcodeproj`, esquema compartido, fuentes, Info.plist y bundle ID: pasa. No es compilación/typechecking Swift.
- **6/6 pruebas de preparación CI**: estructura YAML compatible JSON, comandos existentes, ausencia de publicación/disparadores automáticos, rechazo de ruta Android/sobrescritura, rechazo de fuente comprimida o simulador como app y rechazo de rutas ZIP inseguras. Resultado en `local-ci-tests.txt`.
- **7/7 pruebas aisladas de contrato backend**: resultado en `backend-contract-tests.txt`. Solo base temporal y ejecución ASGI interna sin hilos por limitaciones ya documentadas del ejecutor. No es prueba real de red, concurrencia, APK ni Swift.
- Prueba real del instalador en un destino temporal independiente: pasa clonación, copias verificadas, manifiesto de fuentes, Git limpio/sin remoto y rechazo de sobrescritura. Evidencia en `conservation-test.txt`. No equivale a haber creado la ruta permanente.
- Análisis de sintaxis bash de todos los scripts CI: pasa.
- Instantánea de los 162 archivos Android de referencia: sin cambios respecto a la fase anterior. No se ejecutó Gradle ni se escribieron bases productivas.

## Cambios y correcciones de preparación

Se conserva la app y sus cinco secciones. No se cambian los contratos API, autenticación, permisos, colas, backend, notificaciones locales ni voz en primer plano. Se añaden:

- Flujos manuales de pruebas Swift/simulador/dispositivo sin firma y archivo/exportación Ad Hoc. La compilación de preparación pasa de 1 a 2, manteniendo versión funcional 1.0.0. En CI se usa PROJECT_BUILD_NUMBER+1, compartido entre workflows.
- Ajustes muestra versión/número reales del bundle; elimina el valor fijo que habría identificado incorrectamente builds de nube.
- Verificación real macOS de firma, arquitectura, perfil y registro del iPhone; solo exportaciones verificadas entran en el directorio de artefactos IPA. No hay empaquetador de IPA sintético.
- Informes por paso con resultado/código de salida, ID real del servicio cuando exista, commit, logs y xcresult. No se generó un ID/URL/resultado Codemagic ficticio.
- Instalador local del propietario que conserva copias y rechaza sobrescritura/rutas Android.

No se han observado errores del compilador Apple porque no se ha ejecutado. Cualquier corrección de compilación queda condicionada a obtener el primer log real. El flujo está preparado para detenerse ante fallos y conservar evidencia; no se omiten tests con `|| true` (la única tolerancia es arrancar un simulador que ya puede estar encendido).

## Requisitos exactos para continuar

1. Ejecutar conservación permanente desde la terminal normal del propietario. La restricción es del sandbox de esta sesión; no se pidió elevación.
2. Autorización explícita de proveedor/organización/repositorio privado y acceso Git seguro para subir la entrega. No hay autorización de subida inferida de “preparar repositorio”.
3. Cuenta Codemagic y aplicación conectada a ese repositorio, acceso autorizado y minutos de máquina macOS. Entonces ejecutar ios-validate; no se necesita firma para ese primer paso.
4. Para ios-adhoc: membresía Apple Developer adecuada, App ID del propietario, certificado Distribution con clave privada, perfil Ad Hoc vigente que incluya el iPhone y variable segura IOS_TEST_DEVICE_UDID. Estos elementos no se incluyeron en código ni en el archivo.
5. Para el uso final: instalación por canal compatible, iPhone iOS 16+, URL raíz HTTPS existente de SPARTA accesible desde el teléfono y cuenta Lista Clara autorizada. Probar sincronización bidireccional, permisos, avisos/voz e historial en ambos dispositivos.

No se modificaron Android, clara.service, PostgreSQL, esquemas, servicios o permisos familiares. No se reinició nada ni se publicó una aplicación. APNs sigue fuera del alcance sin autorización nueva. Las limitaciones/pendientes funcionales anteriores continúan en PARITY.md; esta fase prepara compilación y firma, no declara paridad completa.

Guías: [Codemagic](CODEMAGIC.md), [conservación](CONSERVATION.md), [instalación iPhone](INSTALL_IPHONE.md).
