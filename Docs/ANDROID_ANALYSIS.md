# Existing Android architecture — inspected 2026-11-16

Source root: `/home/dexanox/Servicios/TaskFamily/ListaClara`.

## Actual code takes precedence over older documents

`app/build.gradle.kts`: Android application `mx.listaclara.voicefix`, version 3.8.4 (18), min SDK 26, target/compile 35. Kotlin/JVM 17, Compose, Material3, Navigation Compose, ViewModels/StateFlow. Dependencies flow `app → domain`, `app → data → domain`. Composition root: `app/.../ListaApp.kt`; lifecycle/local authentication: `MainActivity.kt`.

Older `docs/ARQUITECTURA.md` says sync is not implemented, and `docs/SINCRONIZACION_0.1.11.md` describes a backend not yet deployed. These statements are historical. Current `app/.../sync/ServerSync.kt` and `server/app.py` implement authentication, CAS sync, family tasks and metrics. Deployment reachability and production host settings were not assumed from these documents.

## Presentation/navigation

`presentation/Screens.kt`: five bottom destinations Eventos, Listas, Tareas, Chismo, Ajustes. List detail, guest/lock screen and secondary Plan de hoy. Dedicated `EventsScreen.kt`, `FamilyTasksScreen.kt`, `ChismografoScreen.kt`, `PlanScreen.kt`; editors in `Dialogs.kt`. Search by list/category; shopping/task/review types, quantities and units, check/uncheck, item positions, store mode, share/reuse and reminder dates.

`Appearance.kt` defaults to Plan claro: terracotta `C65035`, green `278365`, cream `F5F2EB`. Six other presets and custom RGB/hex colors. `Theme.kt` defines stable list colors mint/violet/rose/amber and rounded cards. iOS retains Spanish labels, tab order, accent presets and native controls; exact screenshots have not been compared.

## Persistence and domain

- `domain/.../Models.kt`: UUID lists/items; validation; repository interfaces; share text; explicit separators for manual batch entry.
- `Categories.kt`: catalog names; `DailyPlan.kt`: progress only from lists with today's reminders.
- `Events.kt`: ONCE/WEEKLY/INTERVAL, ISO weekdays 1–7, absolute epoch milliseconds, timezone, exclusive duration end and revision. Weekly scheduling uses the start's saved local clock, rather than arbitrary legacy `times` entries.
- `FamilyModels.kt`: family/member roles, task due/repeat/priority/status/history and pending sync states.
- `data`: Room list/items/categories DB, separate events and family DBs, migrations/schemas; encrypted payloads via `Crypto.kt`. Do not copy SQLite files or device-bound Keystore material to iOS.
- `SyncLocalStore.kt`: canonical JSON, transactions, compare-before-apply, UUIDs, categories/list/event/occurrence snapshots and tombstones.

## Backend/auth/authorization

`server/app.py`: FastAPI/Pydantic, SQLite WAL and opaque token sessions (hashed on server), password hashing with Argon2, login attempt limits, protocol 1. No evidence in this source of PostgreSQL being the API's persistence implementation. No production database was opened to infer runtime deployment.

Login returns token, userId, serverId, role, familyId/familyName, expiresAt milliseconds and protocol. `/auth/me` returns `id`, not `userId`. Tokens expire after 30 days and are revocable. Login currently accepts `client=android` (Bearer) or `web` (cookie); native iOS reuses the Bearer wire mode without changing the backend.

Roles: admin, padre, hijo, user. Personal records are scoped to user, not automatically shared with everyone in the family. Family tasks belong to family; edit/complete is allowed for admin/padre, creator or assignee; delete for admin/padre or creator. Server enforces these rules. `scope=all` follows Android to display the group's tasks; seeing a row does not grant mutation permission. Administration/user provisioning endpoints require the existing web-admin cookie/CSRF flow; iOS must not expose them as Bearer administration.

## Sync

Android `ServerSync.kt` keeps encrypted configuration and ledger, serialized uploads, durable opId/baseVersion/data, server versions, paginated changes and explicit conflicts. Identity binding is serverId/userId. WorkManager schedules periodic 15-minute jobs and immediate work with connectivity/backoff. Family task synchronization is a separate last-write API with pending create/update/delete, snapshot fetch and server-driven recurring follow-ups. Android/iOS same-account personal records synchronize; different accounts share only what existing family authorization permits.

## Android platform services

`platform/Reminders.kt` and event/family counterparts: AlarmManager/WorkManager, receiver reconciliation and notification delivery. Spoken-reminder and event/family voice services support more persistent background voice than iOS permits. `SpokenReminderPolicy.kt`, `SpanishSpeechPolicy.kt` and event repeat logic guide behavior. `VoiceController.kt` uses Android speech services; `TicketReader.kt` uses ML Kit OCR. `SecurityStore.kt` uses platform local authentication/security. These integrations are recreated using Apple APIs, with explicit platform differences.

Android Gradle builds, migrations and its test suite were not run here: they may write build/generated state. No service restart, production health change, credential query or live login was performed.
