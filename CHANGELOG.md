# Independent iOS release history

## Preparación — corrección de portabilidad del preflight

Corregida la comparación de rutas temporales resueltas en las pruebas CI; añadida regresión para padres con enlace simbólico conservando el rechazo de directorios existentes. Reproducción local anterior: salida 1; tras la corrección: siete pruebas pasan con ruta normal y con alias. No se confirma la causa del build 6afb5ce701609fea8f6918ec sin su log. No se declara éxito Xcode/Codemagic. Detalles en Docs/phase1.2/PREFLIGHT_FIX.md.

## 1.0.0 (2) — Fase 1.2 — cloud-build preparation

Preserved original archive and Git baseline. Added manual Codemagic validation/Ad Hoc workflows, real macOS tests/device compilation, signature/profile/registered-device checks, runner evidence, independent Git bundle and an owner-run permanent installer. App screens/backend remain unchanged; Settings reads actual bundle version/build instead of a hardcoded number. No cloud build, signed IPA or physical installation is claimed.


## 1.0.0 (1) — 2026-11-16 — source candidate, not a verified device release

Initial isolated SwiftUI project, portable core, API v1 sync, per-account persistence and Keychain login, lists/tasks/events/history, family outbox/permissions, Chismógrafo, local notification scheduling, foreground Spanish speech, selected-photo OCR and native preferences.

Seven isolated backend contract tests passed. Structural Xcode project validation passed. Twelve XCTest cases provided but not executed because Swift/Xcode are unavailable. No signed application, `.ipa`, physical installation or App Store publication. See Docs/PARITY.md for remaining feature differences and Docs/VERIFICATION.md for acceptance blockers.
