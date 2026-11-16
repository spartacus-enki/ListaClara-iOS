# Shared API contract — ios-contract-1.0.0 / backend protocol 1

Contract frozen from inspected Android `ServerSync.kt`, `SyncLocalStore.kt`, domain models and `server/app.py` (backend source SHA256 in test results). API prefix `/api/v1`. No server changes proposed or applied for this delivery.

| Route | Method | Existing semantics used by iOS |
|---|---|---|
| /auth/login | POST | username/password/client=android; returns Bearer token + identity/protocol |
| /auth/me | GET | id, serverId, protocol, role/family; bind before sync |
| /auth/logout | POST | revoke session, 204 |
| /changes?cursor=N&limit=100 | GET | records, cursor, hasMore; user-scoped feed, global sequence |
| /records/{kind}/{id} | GET | record or 404; exposed by generic API, sync uses feed |
| /mutations | POST | opId, kind, id, baseVersion, data (including null tombstone) |
| /family/current | GET | family or null, members with id/username/role |
| /family/tasks?scope=all | GET | existing family snapshot, including history |
| /family/tasks | POST | client UUID, title/note/assignedTo/dueAt/repeat/priority |
| /family/tasks/{id} | PUT | edit; clearDueAt=true explicitly removes due date |
| /family/tasks/{id}/complete | POST | PENDING/DONE/CANCELLED; recurring follow-up created by server |
| /family/tasks/{id} | DELETE | existing creator/parent/admin permission, 204 |
| /chismografo/stats?year=Y&month=M | GET | authoritative family period metrics, podium, ranking, overdue |

Bearer header is `Authorization: Bearer …`. iOS uses ephemeral URLSession, no cookie persistence, no redirects, normal system TLS certificate verification. Server URL is supplied by owner at login, never guessed. **HTTPS is required by this client.** An HTTP-only SPARTA deployment needs an approved TLS setup or a narrowly scoped development transport configuration; no global ATS bypass is enabled.

## Payloads

`Record = {kind,id,version,seq,data}`. All times epoch milliseconds. No new fields are sent into strict Pydantic models.

- list: name, category, color, icon, kind SHOPPING/TASKS/REVIEW, reminderAt|null, items[{id,name,quantity,unit,completed,position}]. Sort transport item arrays by id; positions remain actual display ordering.
- categories/catalog: names[]. Backend normalizes/deduplicates/sorts.
- event: title,note,start,repeat ONCE/WEEKLY/INTERVAL,hours,days|null,weekdays[ISO 1–7],times[HH:mm],zone IANA,voice,enabled,revision. Every edit generates a revision. Weekly times are normalized to saved-zone start clock.
- occurrence: eventId,at,revision,status DONE/SKIPPED/PENDING,silenced. ID `eventId~at`. PENDING requires silenced=true.
- family task repeats ONCE/WEEKLY/MONTHLY/INTERVAL; priorities HIGH/MEDIUM/LOW. Status history remains in snapshot. Server alone creates recurring follow-ups.

Local logout clears the Keychain session even when the server token is already expired. When offline, remote revocation is best-effort and the app reports that it could not confirm revocation; the existing server expiry still applies. Account data remains isolated.

## CAS and retry

Local edits are persisted atomically. Before POST, the exact opId/baseVersion/data is persisted. Network ambiguity retries that same operation; editor blocks a record with a pending request or unresolved conflict. On success backend-normalized data becomes local/base. A conflict response is HTTP 200 with conflict=true and a record, not necessarily HTTP 409. The user compares and chooses local or remote; choosing local advances baseVersion but requires a subsequent sync to send.

Merge decisions match Android: ignore older versions or unchanged same version/base; acknowledge identical local/remote; apply remote when local equals base and no conflict; otherwise retain both versions. Cursor advances in the same atomic state save as applied/conflicted records. Server identity mismatch stops uploads. HTTP 409 from cursor restoration stops for explicit reconciliation; no destructive reset.

Family outbox is ordered/durable but family endpoints have no opId/CAS. UUID creates can be retried; delete 404 is acknowledged; completion repetition behavior is inherited. Family edits can overwrite a concurrent edit and a retry after another client reopens a task can have effects: this is a limitation of the existing API. Denied/failed operations stay visible, can be discarded explicitly and re-fetched. No claim of transactional cross-platform exactly-once family synchronization.

## Compatibility evidence and limits

Seven ASGI contract tests passed against the existing backend module and disposable SQLite database. Tests cover wire shapes, strict login enum, idempotency, tombstones, CAS conflicts, feed pagination, identity shape, normalized event clock/revision validation, family role checks, recurring completion/history, due clearing and web-admin rejection. The tests use Python HTTP fixtures; they do not execute the Swift client or prove physical Android↔iPhone interoperability. Swift unit tests are supplied but unexecuted here. See VERIFICATION.md.

## Future version policy

Maintain this contract snapshot inside iOS, with references/hashes of Android/server source. Additive optional fields and `/api/v2` should coexist with v1; do not change strict request enums or required fields in place. A future explicit `client=ios` must preserve `android` and `web`; adding APNs requires an authenticated user/device token contract and provider. Any shared change requires owner authorization, temporary-DB contract tests for Android and iOS, stage rollout, backup/rollback design and independently releasable clients. None of that shared work was applied now.
