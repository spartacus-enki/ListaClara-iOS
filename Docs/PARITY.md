# Reuse and compatibility matrix

“Implemented” means present in Swift source, not verified on an iPhone. Apple compilation/device validation remains required for every app row.

| Android component/function | iOS implementation | Reuse/limits |
|---|---|---|
| Kotlin domain models and validation | Core/Models.swift, native editors | Wire fields, UUID identity and limits reused semantically; JVM code cannot directly run in Swift |
| Compose/Material3 navigation | SwiftUI five-tab NavigationStack | Spanish labels/tab order retained; native layouts; visual comparison pending |
| Guest and login | guest disk, API login, Keychain | Same existing account/backend; guest data stays separate |
| SecurityStore/Crypto/Room | LocalAuthentication, Keychain, iOS Data Protection + atomic JSON | No Android key/database migration; iOS does not duplicate Android app-level field encryption or custom PIN |
| Lists/items | CRUD, check, quantities, units, position, share, search, store mode, reuse/history | Same payload, IDs and color indices; native forms |
| Categories | catalog CRUD addition and list category field | Same `categories/catalog`; normalization follows backend |
| Plan de hoy | DailyPlanView | Local-day lists with reminders and completed-item totals; Android illustration not reproduced |
| Events | RecordEditor/EventDetail + Recurrence | ONCE/WEEKLY/INTERVAL, timezone, exclusive duration, weekdays, revisions and history |
| Occurrence completion/silencing | DONE/SKIPPED/PENDING+silenced records | Same eventId~milliseconds identity and revision; iOS does not emulate insistence voice services |
| Personal record synchronization | Synchronizer | Existing API v1, CAS, tombstones, opId retry, paginated cursor, conflicts; same merge decision table |
| WorkManager background sync | foreground polling/refresh | No dependable background polling on iOS; new remote changes wait for foreground refresh without APNs |
| Family membership and permissions | FamilyView + server enforcement | Existing roles; no provisioning or privilege change |
| Family tasks | create/edit/assign/complete/cancel/delete, repeats, priority, due-date clearing/history | Durable ordered outbox; snapshot after upload; existing API has no CAS |
| Chismógrafo | server metrics, podium/ranking/overdue | Uses existing statistics, not a second analytics database; Android's richer local offline analytics not reproduced |
| Appearance preferences | seven local named accent presets | Device-local; custom Android RGB/hex themes and identical surface styling remain a parity gap |
| Voice input | iPhone keyboard dictation | Native text entry; Android custom speech-review/parser workflow not ported identically |
| Ticket OCR | PhotosPicker + Vision + editable review | On-device selected-photo recognition; no direct in-app camera capture yet |
| Local reminders | UserNotifications | Nearest 60 pending occasions, renewed while active/on sync; no endless repeat/insistence |
| Voice announcements | AVSpeechSynthesizer foreground, opt-in automatic or manual read | Background uninterrupted/dynamic speech not supported/claimed |
| Custom alert sound | default system sound shipped | Apple permits short bundled custom audio; no custom sound asset or dynamic voice-file pipeline shipped |
| APNs | investigated, deferred | Requires authorized backend/provider/token registration work; no invented endpoint |

## Known parity gaps before production acceptance

Custom theme editing, Android-specific PIN flow, richer offline Chismógrafo calculations, direct camera capture, exact visual comparison and device reminder behavior remain open. These do not justify changing Android or its backend. Background voice and indefinite synchronization have inherent iOS limits; APNs would improve remote awareness but requires separate authorization.
