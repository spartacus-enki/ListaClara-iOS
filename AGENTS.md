# Lista Clara iOS scope

This checkout is iOS only. Preserve the Android checkout, backend production, schemas, authentication and running SPARTA services. Never run migrations or point tests at real data. The owner must explicitly authorize shared changes after a compatibility/rollback plan.

Sources/App is SwiftUI/Apple platform code. Sources/Core is portable Foundation. Package.swift tests Core; ListaClara.xcodeproj builds the real app and hosted tests. Regenerate project settings/file membership through Tools/generate_project.py when needed.

Do not claim Swift tests, a signed build or device behavior passed without the actual tools/evidence. Check Docs/VERIFICATION.md and Docs/PARITY.md before promising parity. No App Store publishing is authorized.
