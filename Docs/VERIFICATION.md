> Documento de la fase inicial. La ruta sin Mac propia y el estado actual están en [Fase 1.2](phase1.2/REPORT.md).

# Verified results and remaining blockers — 2026-11-16

## Verified on SPARTA

- Inspected current Android source, domains, data stores, screens, platform integrations and backend implementation without editing Android or running its build.
- Delivered an independent iOS source tree with an actual OpenStep `.xcodeproj`, application target, hosted unit-test target and shared scheme; no Android build references.
- Dependency-free structural validator parses the project, checks every object reference, source membership, app/test target, scheme reference and Info.plist. This is **not** Swift parsing or Xcode compilation.
- **7/7 isolated ASGI backend contract tests passed.** Evidence: `contract-test-results.txt`. They import existing backend code only after assigning a disposable `/tmp` database and disable bytecode writes. No production HTTP/database access, migration or service restart.
- Default ASGI/TestClient attempts stalled on this sandbox's thread/event-loop wakeups. The successful run used `LISTACLARA_INLINE_TEST_EXECUTOR=1`, a test-only inline worker executor. FastAPI routes, middleware, validators, auth and DB logic execute; real network transport/threadpool scheduling/concurrent requests do not. Do not present this as an end-to-end iPhone integration pass.
- Read-only delivery snapshot of 162 Android source/reference files saved in `android-source-sha256.json`; unchanged in subsequent validation. Snapshot was taken during delivery, not before the first inspection, and does not assert production database/build-product identity or external concurrent activity.
- No Android edits, database writes to production, deployment, elevation, service interruption, credential copying, backend/schema/auth changes, or App Store actions were performed.

## Automated tests supplied

Twelve XCTest cases cover Android merge decisions, tombstones/conflict choice, JSON semantic equality/millisecond precision, secure URL validation/permissions, intervals/exclusive duration, weekly clock normalization, silenced reminders/queue limit, login wire mode, ambiguous-operation idempotent retry, paginated success/family outbox flush, DST gap scheduling and identity mismatch. **None executed here:** no `swift`, `swiftc` or `xcodebuild` available. Core uses Foundation/URLSession and a mock transport; app target adds Apple frameworks.

Reproduce the completed Linux checks from this directory (adjust the Android path if moved):

```sh
python3 Tools/validate_delivery.py
PYTHONDONTWRITEBYTECODE=1 LISTACLARA_INLINE_TEST_EXECUTOR=1 LISTACLARA_ANDROID_SOURCE=/home/dexanox/Servicios/TaskFamily/ListaClara /home/dexanox/Servicios/TaskFamily/ListaClara/server/.venv/bin/python IntegrationTests/test_contract.py
```

The backend venv is reused read-only, not installed or changed. On an unrestricted test runner, omit the inline flag to test its ordinary ASGI executor too. Use Mac commands in BUILD.md for actual Swift/Xcode validation.

## Blockers to release/complete acceptance

1. **Mac/Xcode:** compile/typecheck the source, execute all XCTest cases, simulator and iPhone tests. Resolve any errors before calling the application build verified. No iOS binary was generated.
2. **Signing/device:** owner Apple account/team, unique bundle ID if needed, provisioning and Developer Mode; physical iPhone iOS 16+.
3. **Backend reachability:** confirm owner-provided HTTPS root URL, certificate trust and network access from iPhone. No production login/credentials/end-to-end device sync was attempted. Existing HTTP-only installations need an approved TLS/development transport decision.
4. **Cross-device acceptance:** test an approved non-production account on Android/iPhone with same-account records, different-account family permissions, offline edits, conflict choices, account switching, family repeats, retries and history. Python fixtures are not the Android APK or Swift client.
5. **Notification acceptance:** device permission denial/regrant, Focus/silent mode, app termination, timezone/DST, notification navigation/lock, finite-queue renewal and obsolete remote schedule cancellation after refresh. APNs remains unavailable without separately authorized provider work; no unrestricted background voice.
6. **Parity review:** see PARITY.md. Custom theme editing, Android-specific custom PIN, richer local offline metrics, camera capture and exact visual matching remain gaps; preset appearance, device authentication, server metrics, photo OCR and native controls are implemented alternatives. App icon/launch branding polishing is also pending.
7. **Durable destination:** `/tmp/ListaClara-iOS` and its archive are temporary. Preferred sibling location is outside this session's writable roots. Owner must copy the isolated artifact to durable storage; no elevated privileges are inherently required.

This is a substantive source delivery and compatibility candidate, **not a declaration that full Phase 1 acceptance or functional equivalence has been verified**.
