# Corrección de preparación — build 6afb5ce701609fea8f6918ec

## Diagnóstico y límites de evidencia

El propietario reporta fallo de `ios-validate`, rama `main`, commit `a135e02`, máquina Mac mini M2, paso `Check Xcode/project and capture build metadata`, script `ci/prepare.sh`, salida 1. No se dispone del log real del servicio ni de conexión/token Codemagic en esta sesión. Se solicitó el traceback; **no se confirma aún la causa de ese build concreto**.

Se encontró y reprodujo un defecto real en la primera batería ejecutada por prepare.sh: `test_refuse_existing_or_android_destination` comparaba el resultado canónico de `safe_destination` con la ruta de entrada sin resolver. Si el directorio temporal se alcanza mediante un enlace simbólico, ambas rutas designan el mismo destino pero no son iguales como objetos Path. La prueba falla y unittest devuelve 1. `set -euo pipefail` propaga ese resultado a través de `tee` y detiene el paso antes de `xcodebuild -version`.

La reproducción se realizó realmente en Debian mediante TMPDIR apuntando a un alias simbólico de un directorio temporal nuevo. Es un caso de portabilidad relevante para macOS, pero no prueba que el TMPDIR del build reportado tuviera esa condición. Si su log muestra ese test fallando con rutas equivalentes resueltas/no resueltas, quedará confirmada la correspondencia.

## Inspección de las otras condiciones de fallo

| Punto de prepare/common | Condición | Estado |
|---|---|---|
| source/common y mkdir | Directorio inaccesible o sin permiso de escritura | Posible; no observada |
| ci_step / evidence.py | Fallo al leer Git o crear/escribir evidencia | Posible; no observado |
| ci_macos | Plataforma distinta de Darwin | En Debian devuelve 2, no 1; no se atribuye a la máquina Mac indicada |
| ci_version | PROJECT_BUILD_NUMBER no numérico, IOS_VERSION o IOS_BUILD_NUMBER inválidos | Puede provocar excepción/assert y salida 1; no se proporcionaron valores reales del runner |
| ci/test_tools.py | Cualquier test fallido | **Fallo de rutas simbólicas reproducido con salida 1** |
| xcodebuild -version / swift --version | Herramientas o selección SDK no disponibles | Posible salida no cero; no comprobable sin runner/log |
| Tools/validate_delivery.py | Fallo al analizar/referenciar proyecto, fuentes o Info.plist | Pasa localmente para el proyecto actual |
| xcodebuild -list | Error de carga del proyecto por Xcode | Sin evidencia de ejecución real aquí; no se cambiaron settings por suposición |
| Metadata Python final | Error de Git, entorno o escritura | Posible; no observado |

Se revisaron `ci/prepare.sh`, `ci/common.sh`, `codemagic.yaml`, `Tools/validate_delivery.py`, generador, project.pbxproj, Info.plist y esquema compartido. No se encontraron razones demostradas para modificar esos archivos, cambiar Xcode, omitir pruebas o alterar firma/autenticación.

## Cambios mínimos

- `ci/test_tools.py`: la expectativa ahora compara con `allowed.resolve()`, respetando el contrato que ya tenía el instalador.
- Nueva prueba de regresión: un alias simbólico hacia un padre real devuelve el destino canónico; no crea el destino y sigue rechazando el directorio existente a través del alias.
- `CHANGELOG.md`: documenta la corrección.
- Este informe y `MANIFEST.sha256`: documentación e integridad actualizadas.

No cambian el instalador, las protecciones de Android, las pantallas, los scripts de compilación, el contrato backend ni la versión funcional. No se cambia `latest` por una imagen arbitraria ni se convierte un test fallido en éxito mediante excepciones genéricas.

## Pruebas realizadas

| Comprobación real local | Antes | Después |
|---|---|---|
| Suite CI con TMPDIR ordinario | 6 tests, salida 0 | 7 tests, salida 0 |
| Suite CI con TMPDIR mediante symlink | 6 tests, un fallo, salida 1 | 7 tests, salida 0 |
| Estructura Xcode, referencias, esquema e Info.plist | — | PASS; no equivale a ejecutar Xcode |
| Python AST, sintaxis Bash, parseo YAML compatible JSON, git diff --check | — | PASS |
| Ejecución real de prepare.sh en Debian | — | Detención correcta por ci_macos, salida 2; no se simula macOS/Xcode |

Logs de reproducción antes/después y validación: entrega externa `/tmp/ListaClara-iOS-preflight-evidence`. No se ejecutaron tests que importen el backend, ni se escribieron bases productivas. La validación estructural comprobó además los hashes Android de referencia sin modificarlos. **No se ejecutaron Swift/XCTest ni una nueva compilación Codemagic.**

## Incorporar el commit correctivo al checkout del propietario

La carpeta iOS permanente está fuera de las rutas de escritura de esta sesión. Se preparó un commit independiente sobre `main` en `/tmp/ListaClara-iOS-fix-preflight`, partiendo exactamente de a135e022ebd6396009e0e595efbe1b9a9113b17d, y un bundle Git verificable. No se reescribió historial ni se modificó el checkout permanente.

Desde la terminal normal del propietario (el bloque se detiene si main ya cambió o hay cambios locales):

```bash
(
set -e
cd /home/dexanox/Servicios/TaskFamily/ListaClara-iOS
test "$(git branch --show-current)" = main
test -z "$(git status --porcelain)"
test "$(git rev-parse HEAD)" = a135e022ebd6396009e0e595efbe1b9a9113b17d
git bundle verify /tmp/ListaClara-iOS-preflight-fix.bundle
git fetch /tmp/ListaClara-iOS-preflight-fix.bundle main
git merge --ff-only FETCH_HEAD
PYTHONDONTWRITEBYTECODE=1 python3 ci/test_tools.py
sha256sum -c MANIFEST.sha256
)
```

No requiere privilegios elevados. No se hizo git push; tampoco está autorizado por esta corrección. El remoto GitHub conserva el commit anterior hasta que el propietario autorice y efectúe la subida.

## Volver a ejecutar en Codemagic

**Primero** incorporar el commit y, solo tras autorización separada, subirlo a GitHub. Repetir la compilación de `a135e02` sin cambiar el código remoto no probará la corrección.

En la cuenta Codemagic: aplicación ListaClara-iOS → Start new build → rama `main` → workflow `ios-validate` → comprobar que usa el nuevo SHA → Start build. No elegir un rebuild anclado al commit anterior. Guardar ID real, SHA, log del paso inicial y artefactos `build/logs/ci-safeguard-tests.log` y `build/evidence/preflight.json`.

Alternativa por API, **para ejecución posterior por el propietario**, con token almacenado en su entorno seguro y el App ID real (el Build ID reportado no es el App ID):

```bash
: "${CM_APP_ID:?Configura el App ID de ListaClara-iOS en Codemagic}"
: "${CODEMAGIC_API_TOKEN:?Configura el token de Codemagic de forma segura}"
export CM_APP_ID CODEMAGIC_API_TOKEN
python3 - <<'PY'
import json, os, urllib.request
body = json.dumps({'appId': os.environ['CM_APP_ID'],
                   'workflowId': 'ios-validate', 'branch': 'main'}).encode()
request = urllib.request.Request('https://api.codemagic.io/builds', data=body,
    headers={'Content-Type': 'application/json',
             'x-auth-token': os.environ['CODEMAGIC_API_TOKEN']}, method='POST')
with urllib.request.urlopen(request, timeout=30) as response:
    result = json.load(response)
print(json.dumps({'buildId': result['buildId']}))
PY
```

Comando basado en la [API oficial de builds](https://docs.codemagic.io/rest-api/builds/). No se ejecutó esta solicitud en la sesión. No se incluyen secretos en código, argumentos de proceso o informes. Una respuesta con buildId confirma inicio, no éxito: esperar al resultado real del servicio. Solo una compilación Xcode terminada y sus logs permiten declarar ese éxito.
