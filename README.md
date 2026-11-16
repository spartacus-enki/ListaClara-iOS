# Fase 1.2 — compilación en Codemagic

Se reutiliza íntegramente la aplicación existente. Preparados repositorio Git local independiente, `codemagic.yaml`, pruebas macOS/simulador y exportación/verificación de IPA Ad Hoc. **No se ha ejecutado Codemagic, no hay IPA firmado y la conservación permanente requiere ejecutar el instalador con acceso normal del propietario.**

- [Configuración y desbloqueo de Codemagic](Docs/phase1.2/CODEMAGIC.md)
- [Instalación en iPhone sin Mac propia](Docs/phase1.2/INSTALL_IPHONE.md)
- [Estado verificable, pruebas y bloqueos](Docs/phase1.2/REPORT.md)
- [Conservación permanente](Docs/phase1.2/CONSERVATION.md)

Versión de aplicación: **1.0.0**; compilación local de preparación: **2**. Codemagic usa `PROJECT_BUILD_NUMBER + 1` para distinguir compilaciones entre flujos. Fase 1.2 es el número del trabajo, no una nueva versión funcional de la app.

---

# Lista Clara iOS — Phase 1.0 candidate

Independent native SwiftUI iPhone application, version **1.0.0 (2)**, deployment target **iOS 16**. Uses the existing SPARTA `/api/v1` backend. No Android files, production services, authentication rules or production databases are changed.

**Status:** source and a real Xcode app/test project delivered. Xcode/Swift are unavailable on SPARTA; no iOS build, Swift test pass, signing, installation, device test or full visual parity is claimed.

Open `ListaClara.xcodeproj` on a Mac. See [build and installation](Docs/BUILD.md), [architecture analysis](Docs/ANDROID_ANALYSIS.md), [reuse/parity matrix](Docs/PARITY.md), [API compatibility](Docs/API_COMPATIBILITY.md), [notifications](Docs/NOTIFICATIONS.md), [verified results and blockers](Docs/VERIFICATION.md), and [maintenance/rollback](Docs/MAINTENANCE.md).

## Included implementation

- Spanish SwiftUI tabs matching Android: Eventos, Listas, Tareas, Chismo, Ajustes; daily plan, search, store mode, quantities/units, ordering, sharing, list reuse and completed-item history.
- Guest storage; existing account login/logout; Keychain bearer sessions; separate files per `serverId/userId`; device-owner authentication; atomic iOS Data Protection storage. Guest records do not silently upload into an account.
- Versioned CAS records, tombstones, durable idempotent operations, paginated changes, explicit conflicts; categories/events/occurrences. Polling every 30 seconds while active, on foreground, after edits and by pull-to-refresh. No continuous background synchronization promise.
- Family profile, membership, priorities, assignment, recurring tasks, completion/cancellation/history, server-side permissions, durable ordered offline family outbox. Existing family API has no CAS conflict protection.
- Server Chismógrafo statistics by period, podium, ranking and overdue tasks.
- Local notifications for the nearest 60 occasions, event recurrence in saved timezone, silenced/completed occurrence suppression, notification navigation after local lock. Foreground speech is opt-in. Default system sound.
- On-device ticket OCR from a selected photo with manual review; keyboard dictation available in editable text fields.

## Directory

`Sources/Core` contains portable Foundation models, HTTP transport, sync and recurrence logic. `Sources/App` contains SwiftUI and Apple platform adapters. `Tests` contains XCTest cases. `IntegrationTests` exercises the existing Python backend in a disposable database. `Tools/generate_project.py` regenerates the checked-in Xcode project without dependencies.

There are no external iOS package dependencies and no copied Android signing keys, data or credentials.

## Location

The preferred `/home/dexanox/Servicios/TaskFamily/ListaClara-iOS` is outside this session's writable roots. The isolated project is delivered at `/tmp/ListaClara-iOS` plus a sibling `.tar.gz` archive. `/tmp` is temporary: copy it to durable storage with normal owner access. The project has no hardcoded dependency on its temporary location. Do not copy it into or reorganize Android.
