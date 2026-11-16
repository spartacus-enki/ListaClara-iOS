# Independent iOS release history

## Fase 1.5 — política DST compatible con Android

Reemplazada únicamente la resolución de hora semanal que redondeaba huecos DST. Ahora usa offsets reales de la zona guardada: avanza por la duración del hueco y elige el primer instante de un solapamiento, como Java atZone. Expectativa original conservada; diez nuevas regresiones, 22 casos XCTest preparados. Referencias Python/IANA verificadas; Swift/Xcode y el oracle Java pendientes por falta de herramientas locales. Detalles en Docs/phase1.5/DST_POLICY.md.

## Fase 1.4 — corrección de typechecking en XCTest

Separadas dos comparaciones de arrays temporales en variables explícitas `[TimeInterval]`; se conservan todos los valores y las doce pruebas. Corrige la expresión indicada por el error de Xcode 26.6/Swift 6.3.3 en el build 6afb636601609fea8f691b8a. Sin cambios productivos ni de configuración. La nueva compilación real sigue pendiente; ver Docs/phase1.4/XCODE_TYPECHECK_FIX.md.

## Preparación — corrección de portabilidad del preflight

Corregida la comparación de rutas temporales resueltas en las pruebas CI; añadida regresión para padres con enlace simbólico conservando el rechazo de directorios existentes. Reproducción local anterior: salida 1; tras la corrección: siete pruebas pasan con ruta normal y con alias. No se confirma la causa del build 6afb5ce701609fea8f6918ec sin su log. No se declara éxito Xcode/Codemagic. Detalles en Docs/phase1.2/PREFLIGHT_FIX.md.

## 1.0.0 (2) — Fase 1.2 — cloud-build preparation

Preserved original archive and Git baseline. Added manual Codemagic validation/Ad Hoc workflows, real macOS tests/device compilation, signature/profile/registered-device checks, runner evidence, independent Git bundle and an owner-run permanent installer. App screens/backend remain unchanged; Settings reads actual bundle version/build instead of a hardcoded number. No cloud build, signed IPA or physical installation is claimed.


## 1.0.0 (1) — 2026-11-16 — source candidate, not a verified device release

Initial isolated SwiftUI project, portable core, API v1 sync, per-account persistence and Keychain login, lists/tasks/events/history, family outbox/permissions, Chismógrafo, local notification scheduling, foreground Spanish speech, selected-photo OCR and native preferences.

Seven isolated backend contract tests passed. Structural Xcode project validation passed. Twelve XCTest cases provided but not executed because Swift/Xcode are unavailable. No signed application, `.ipa`, physical installation or App Store publication. See Docs/PARITY.md for remaining feature differences and Docs/VERIFICATION.md for acceptance blockers.
