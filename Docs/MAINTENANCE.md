# Independent maintenance and rollback

## Scope rules

- “Update Lista Clara Android”: change only `/home/dexanox/Servicios/TaskFamily/ListaClara` under that explicit task. This iOS delivery changes none of it.
- “Update Lista Clara iOS”: change only the independent iOS checkout. Never edit Android, its Gradle settings, backend source, service units or production databases as a side effect.
- “Add this to both”: plan/review separate app patches and test each. A shared backend change is still a distinct authorization boundary.

Keep separate repositories, bundle/application IDs, dependency manifests, release tags, build numbers, signing credentials and release notes. No runtime path points into Android. `IntegrationTests` alone accepts `LISTACLARA_ANDROID_SOURCE` as a read-only reference to the backend code under test.

## iOS release process

Edit Swift source; add meaningful regression tests where needed. When adding/removing files or changing generated settings, update `Tools/generate_project.py`, regenerate and review the project diff. Run structural validation, portable tests, Xcode simulator build/tests and physical iPhone acceptance. Record results and remaining gaps in CHANGELOG.md. Increment iOS MARKETING_VERSION/CURRENT_PROJECT_VERSION in the generator independently of Android. Create a source-control release tag after owner review; no publication is implied.

Never run a backend import or test with its default DB path. Integration tests set LISTACLARA_DB to a new temporary directory before importing any backend module and disable bytecode output. Existing venv is read-only. Do not run Android Gradle or its in-tree tests as a routine iOS task if preserving its tree is required.

## Shared changes, only after authorization

Present route/schema/auth impact, old-client behavior, migration compatibility and rollback before changing anything shared. Validate Android and iOS request/response fixtures against both old and proposed backends in disposable databases. Use compatible optional additions or parallel versioned routes; keep v1 alive until independently released clients can migrate. Obtain owner authorization before production deployment/database changes.

No shared rollback is needed for this phase: there are no shared changes. For a future shared release, capture an owner-approved consistent database backup and old service artifact/config, test restoring a disposable copy, prefer expand/contract migrations, stage compatible server changes, monitor both clients and keep a documented revert path. A backup is not authorization to modify production.

## Local rollback

Preserve source archive/checksum and app data before a future iOS upgrade. Revert only iOS source/version; rebuilding/reinstalling the same bundle can preserve its sandbox, whereas uninstalling removes local data and unsent edits. Do not recommend deleting the app as a sync fix. Local guest/account ledgers are intentionally excluded from backups in this implementation; a user-facing export/recovery workflow remains future work.

Undoing the development delivery means removing its independent source checkout/archive; that does not undo user changes already sent through the existing backend. Use existing authorized application actions for data changes; never restore/delete a production DB to roll back an iOS source change.
