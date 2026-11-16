# Codemagic: pasos concretos para obtener la compilación real

## Estado y autorización

No se dispone de conexión a Codemagic, token API ni aplicación Codemagic identificada. La búsqueda de integración no encontró un plugin Codemagic disponible. No hay GitHub/GitLab conectado ni token configurado para este trabajo. La cuenta Apple Developer, certificado, perfil y UDID no se han proporcionado/verificado. **No se intentó una compilación remota ni se subió código.**

El repositorio local tiene rama `main`, historial propio y ningún remoto externo. La orden de preparar el repositorio no autoriza publicar/subir su contenido. Primero el propietario debe identificar proveedor/organización/nombre y autorizar expresamente la subida a un repositorio privado. También debe autorizar el acceso de Codemagic a ese repositorio y disponer de minutos de compilación en su cuenta.

## 1. Conservar antes de conectar

Ejecutar el instalador de CONSERVATION.md y verificar el checkout permanente. No usar la carpeta Android para conectar Codemagic. El bundle permite reconstruir todo el historial iOS sin acceso a una red.

## 2. Repositorio privado

Después de autorización explícita, crear un repositorio **vacío y privado** llamado, por ejemplo, `ListaClara-iOS` en la organización que el propietario elija. No activar README/licencia automáticos al crearlo, pues ya existe historial local. Revisar los archivos antes de subirlos. Nunca incluir `.p12`, `.p8`, perfiles, tokens, claves o bases de datos.

Desde el checkout iOS permanente, y solo después de dicha autorización:

```sh
git remote add origin URL_PRIVADA_APROBADA
git push -u origin main
```

Sustituir `URL_PRIVADA_APROBADA` por la URL real sin credenciales incrustadas. Usar la autenticación segura del proveedor. No se ejecutaron estos comandos en esta entrega.

## 3. Conectar y ejecutar sin firma

En Codemagic, añadir aplicación desde el repositorio privado autorizado, seleccionar proyecto iOS nativo y configuración `codemagic.yaml` de la raíz. Conceder al servicio acceso solo al repositorio necesario. Elegir rama `main` y workflow **ios-validate**, e iniciar manualmente.

El flujo configura máquina macOS `mac_mini_m2` con Xcode `latest`; recoge la versión real del SDK/Swift en logs. Tras la primera compilación válida, puede fijarse la imagen Xcode observada para repetir el entorno. La configuración no incluye webhooks, cron, App Store, TestFlight, correo ni publicación externa de artefactos. Los artefactos quedan en el panel de la compilación para el propietario.

Pasos ejecutados por CI: validación estructural/configuración, seis pruebas de herramientas, `swift test` (12 casos de Core), selección de un simulador iPhone disponible, XCTest hospedado del proyecto completo y compilación Release para dispositivo iOS **sin firma**. Este flujo no exige cuenta Apple para probar/compilar, pero su resultado sin firma no se instala en iPhone.

`codemagic.yaml` usa sintaxis JSON, válida en YAML 1.2, para poder validarla sin instalar dependencias de Debian. No es un marcador de posición: contiene los dos workflows y comandos reales. El esquema/ejecución definitivos se comprobarán al importarlo y correrlo en Codemagic. Referencias oficiales: [iOS nativo](https://docs.codemagic.io/yaml-quick-start/building-a-native-ios-app/), [configuración YAML](https://docs.codemagic.io/yaml-basic-configuration/yaml-getting-started/).

## 4. Preparar firma Ad Hoc, sin Mac física

Se requiere una membresía Apple Developer Program adecuada, App ID explícito `mx.listaclara.ios`, certificado Apple Distribution con su clave privada y perfil **Ad Hoc** que incluya el iPhone. Si ese bundle ID no pertenece al propietario, elegir uno propio y cambiarlo en `Tools/generate_project.py`, en ambos `IOS_BUNDLE_ID` y en `environment.ios_signing.bundle_identifier` de Codemagic; regenerar y revisar antes de subir el cambio. Cambiar el ID de iOS no cambia Android.

En Team settings → Code signing identities de Codemagic:

1. Añadir certificado de distribución `.p12` y su contraseña por el almacenamiento seguro del servicio. Si todavía no existe, el propietario puede usar la integración Apple Developer/App Store Connect de Codemagic para generar/gestionar la identidad en la nube; no hace falta una Mac propia. La clave API Apple, si se usa, va en la integración segura, nunca en Git.
2. Registrar el UDID del iPhone en Apple Developer. Codemagic ofrece un flujo de registro de dispositivos; el propietario puede usarlo desde el iPhone. Generar/renovar el perfil Ad Hoc del App ID con ese dispositivo y ese certificado, y añadirlo en Codemagic. Un `.cer` sin su clave privada no basta para firmar.
3. Crear grupo de variables **lista_clara_ios_adhoc** y guardar `IOS_TEST_DEVICE_UDID` como secreto. No pegar el valor en código, issues ni logs.

El bloque `ios_signing` usa `ad_hoc` y `mx.listaclara.ios` para obtener los archivos cargados. No exige una clave API Apple dentro del YAML si se usan los archivos previamente cargados. Ver [firma iOS](https://docs.codemagic.io/yaml-code-signing/signing-ios/) y [registro de dispositivos](https://docs.codemagic.io/testing/ios-provisioning/).

## 5. Ejecutar la generación firmada

Iniciar manualmente **ios-adhoc** desde `main`. Repite pruebas antes de firmar. Ejecuta `xcode-project use-profiles`, archiva/exporta con `xcode-project build-ipa` y verifica el resultado con `ci/verify_ipa.py`. Solo tras superar la comprobación se mueve el IPA a `build/ios/ipa`, el directorio de artefactos.

La comprobación exige ejecutable arm64 para iPhoneOS, firma válida, perfil de distribución no vencido, App ID/equipo coherentes y UDID del iPhone incluido. No acepta archivos fuente comprimidos, un simulador ni perfiles de desarrollo/enterprise. No sube nada a App Store Connect. Guía de comandos: [use-profiles](https://github.com/codemagic-ci-cd/cli-tools/blob/master/docs/xcode-project/use-profiles.md), [build-ipa](https://github.com/codemagic-ci-cd/cli-tools/blob/master/docs/xcode-project/build-ipa.md).

## 6. Recoger evidencia y corregir fallos

Guardar URL/ID real de la compilación, commit, workflow, estado final, logs, `.xcresult`, `build/evidence/*.json`, IPA y SHA-256 del informe de verificación. Los scripts escriben estados reales de cada paso; no existe un resultado de compilación inventado en este repositorio. Un flujo fallido no debe declararse instalable aunque existan archivos intermedios.

Si Swift/Xcode falla, conservar el log original, corregir únicamente iOS, repetir el flujo y registrar el nuevo commit. Si falla firma, comprobar bundle ID, caducidad, clave privada, certificado asociado al perfil y UDID; renovar el perfil después de registrar un nuevo dispositivo. Sin acceso autorizado a Codemagic no puede ejecutarse este ciclo desde la sesión actual.

Para reanudar trabajo del agente: autorizar el repositorio privado concreto y conectar un acceso seguro a Codemagic/Git, o ejecutar el flujo desde la cuenta del propietario y facilitar el ID/URL y los logs no secretos. No es necesario enviar contraseñas Apple ni claves privadas en el chat.
