import SwiftUI
import LocalAuthentication

@MainActor final class AppModel: ObservableObject {
    @Published var ledger = Ledger()
    @Published var session: Session?
    @Published var busy = false
    @Published var message: String?
    @Published var locked = false
    @Published var ready = false
    @Published var reminderToOpen: String?
    let notifications = Notifications()
    private var disk: DiskStore?
    var userID: String { session?.auth["userId"].string ?? "" }
    var role: String { session?.auth["role"].string ?? "" }
    var api: API? { session?.api }
    init() {
        do {
            session = try Vault.read()
            disk = try DiskStore(identity: session?.identity ?? "guest")
            ledger = try disk!.load(); ready = true
            locked = UserDefaults.standard.bool(forKey: "biometricLock")
        } catch { message = error.localizedDescription }
        notifications.onOpenReminder = { [weak self] key in self?.reminderToOpen = key }
        notifications.onForegroundReminder = { [weak self] key in
            guard let self, !self.locked, UserDefaults.standard.bool(forKey: "foregroundVoice") else { return }
            let parts = key.split(separator: "/").map(String.init)
            guard parts.count >= 2 else { return }
            if parts[0] == "event", let event = self.ledger.entries["event/" + parts[1]]?.local, event["voice"].bool {
                self.notifications.speak(event["title"].string + ". " + event["note"].string)
            } else if parts[0] == "task", let task = self.ledger.tasks.first(where: { $0["id"].string == parts[1] }) {
                self.notifications.speak(task["title"].string)
            } else if parts[0] == "list", let list = self.ledger.entries["list/" + parts[1]]?.local {
                self.notifications.speak(list["name"].string)
            }
        }
    }
    func persist(_ value: Ledger) throws {
        guard ready, let disk else { throw CoreError.message("Almacenamiento no disponible; no se guardaron cambios.") }
        try disk.save(value); ledger = value
    }
    func edit(_ kind: String, _ id: String, _ data: JSON) {
        guard !busy else { message = "Espera a que termine la sincronización y vuelve a guardar el formulario."; return }
        do {
            var next = ledger; try next.edit(kind: kind, id: id, data: data); try persist(next)
            Task { await updateReminders(); await sync() }
        } catch { message = error.localizedDescription }
    }
    func resolve(_ key: String, local: Bool) {
        do { var next = ledger; next.resolve(key, local: local); try persist(next) }
        catch { message = error.localizedDescription }
    }
    func records(_ kind: String) -> [Record] {
        ledger.entries.values.filter { $0.record.kind == kind && $0.local != .null }.map {
            var r = $0.record; r.data = $0.local; return r
        }.sorted { $0.id < $1.id }
    }
    func perform(_ action: () async throws -> Void) async {
        guard !busy, ready else { return }; busy = true
        defer { busy = false }
        do { try await action() } catch { message = error.localizedDescription }
    }
    func login(url: String, username: String, password: String) async {
        await perform {
            let base = try validServer(url)
            let auth = try await API(base: base).login(username: username, password: password)
            let newSession = Session(base: base, auth: auth)
            let newDisk = try DiskStore(identity: newSession.identity)
            let next = try newDisk.load()
            try Vault.write(newSession)
            notifications.clear(); disk = newDisk; ledger = next; session = newSession
        }
        if session != nil { await sync() }
    }
    func logout() async {
        await perform {
            var unconfirmedRevocation = false
            if let api {
                do { _ = try await api.call("/api/v1/auth/logout", method: "POST") }
                catch CoreError.http(401) { /* Already expired/revoked; local logout must still work. */ }
                catch { unconfirmedRevocation = true }
            }
            let guestDisk = try DiskStore(identity: "guest"), guest = try guestDisk.load()
            try Vault.write(nil); session = nil; disk = guestDisk; ledger = guest; notifications.clear()
            if unconfirmedRevocation { message = "Sesión cerrada en este iPhone. No se pudo confirmar la revocación remota; la sesión del servidor conserva su vencimiento actual." }
        }
    }
    func sync() async {
        guard let session else { return }
        await perform {
            try await Synchronizer(api: session.api, identity: session.identity).run(load: { self.ledger }, save: { try self.persist($0) })
            try await notifications.reconcile(ledger)
        }
    }
    func updateReminders() async {
        do { try await notifications.reconcile(ledger) } catch { message = error.localizedDescription }
    }
    func familyMutation(_ path: String, method: String, body: JSON? = nil) async {
        guard let session else { message = "Conecta tu cuenta primero."; return }
        guard !busy else { return }
        do {
            let parts = path.split(separator: "/")
            let taskID = method == "POST" && parts.last == "tasks" ? body?["id"].string ?? "" : String(parts[4])
            guard !taskID.isEmpty else { throw CoreError.message("Tarea sin identidad") }
            guard !(ledger.familyOutbox ?? []).contains(where: { $0.taskID == taskID }) else { throw CoreError.message("Esta tarea ya tiene un cambio pendiente. Sincronízalo primero.") }
            var next = ledger
            var preview = next.tasks.first { $0["id"].string == taskID } ?? .object([
                "id": .string(taskID), "createdBy": .string(userID), "createdByName": session.auth["username"],
                "familyId": next.family["family"]["id"], "status": .string("PENDING"), "dueAt": .null])
            if let body {
                for (key, value) in body.object where key != "clearDueAt" { preview[key] = value }
                if body["clearDueAt"].bool { preview["dueAt"] = .null }
                if let member = next.family["members"].array.first(where: { $0["id"] == preview["assignedTo"] }) { preview["assignedToName"] = member["username"] }
            }
            next.tasks.removeAll { $0["id"].string == taskID }
            if method != "DELETE" { next.tasks.append(preview) }
            let operation = FamilyOperation(taskID: taskID, path: path, method: method, body: body, preview: method == "DELETE" ? nil : preview)
            next.familyOutbox = (next.familyOutbox ?? []) + [operation]
            try persist(next)
            await updateReminders()
        } catch { message = error.localizedDescription; return }
        await sync()
        if let error = message { message = "Cambio guardado en este iPhone y pendiente de confirmar en el servidor. " + error }
    }
    func discardFamilyOperation(_ id: String) {
        do {
            var next = ledger
            next.familyOutbox?.removeAll { $0.id == id }; try persist(next)
            Task { await sync() }
        } catch { message = error.localizedDescription }
    }
    func stats(year: Int, month: Int) async {
        guard let api else { return }
        await perform {
            var next = ledger
            next.stats = try await api.call("/api/v1/chismografo/stats?year=\(year)&month=\(month)")
            try persist(next)
        }
    }
    func unlock() async {
        do {
            locked = !(try await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Abrir Lista Clara"))
        } catch { message = error.localizedDescription }
    }
}
