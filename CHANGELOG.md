# Independent iOS release history

## 1.0.0 (2) — Fase 1.2 — cloud-build preparation

Preserved original archive and Git baseline. Added manual Codemagic validation/Ad Hoc workflows, real macOS tests/device compilation, signature/profile/registered-device checks, runner evidence, independent Git bundle and an owner-run permanent installer. App screens/backend remain unchanged; Settings reads actual bundle version/build instead of a hardcoded number. No cloud build, signed IPA or physical installation is claimed.


## 1.0.0 (1) — 2026-11-16 — source candidate, not a verified device release

Initial isolated SwiftUI project, portable core, API v1 sync, per-account persistence and Keychain login, lists/tasks/events/history, family outbox/permissions, Chismógrafo, local notification scheduling, foreground Spanish speech, selected-photo OCR and native preferences.

Seven isolated backend contract tests passed. Structural Xcode project validation passed. Twelve XCTest cases provided but not executed because Swift/Xcode are unavailable. No signed application, `.ipa`, physical installation or App Store publication. See Docs/PARITY.md for remaining feature differences and Docs/VERIFICATION.md for acceptance blockers.
