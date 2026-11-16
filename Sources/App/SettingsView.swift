import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("palette") var palette = 0
    @AppStorage("foregroundVoice") var foregroundVoice = false
    @AppStorage("biometricLock") var biometricLock = false
    @State var server = ""
    @State var username = ""
    @State var password = ""
    @State var category = ""
    @State var disconnect = false
    @State var pendingOperation: String?
    var body: some View {
        Form {
            Section("Cuenta y sincronización") {
                if let session = model.session {
                    Text(session.auth["username"].string + " · " + session.auth["role"].string)
                    Text(session.base.absoluteString).font(.caption)
                    Button("Sincronizar ahora") { Task { await model.sync() } }
                    Text("Se actualiza al abrir y al deslizar las pantallas. Los cambios locales se conservan sin conexión.").font(.caption)
                    Button("Cerrar sesión", role: .destructive) { disconnect = true }
                } else {
                    Text("Modo invitado. Tus datos de invitado permanecen separados de las cuentas.")
                    TextField("URL raíz HTTPS de SPARTA", text: $server).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Usuario", text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Contraseña", text: $password).textContentType(.password)
                    Button("Conectar") { Task { await model.login(url: server, username: username, password: password); password = "" } }.disabled(server.isEmpty || username.isEmpty || password.isEmpty)
                }
            }
            Section("Seguridad") {
                Toggle("Bloquear al salir · Face ID / código", isOn: $biometricLock)
                Text("El bloqueo usa la autenticación del iPhone. La sesión se guarda en el llavero y la información local usa Protección de Datos de iOS.").font(.caption)
            }
            Section("Notificaciones y voz") {
                Toggle("Leer avisos con la app abierta", isOn: $foregroundVoice)
                Button("Permitir notificaciones") { Task { do { if try await model.notifications.authorize() { await model.updateReminders() } else { model.message = "Las notificaciones están desactivadas. Puedes habilitarlas en Ajustes de iOS." } } catch { model.message = error.localizedDescription } } }
                Button("Probar voz en primer plano") { model.notifications.speak("Hola. Soy Lista Clara. Tus recordatorios están contigo.") }
                Text("iOS administra los avisos locales. Se programan las próximas 60 ocasiones y se renuevan al abrir o sincronizar. No hay voz continua en segundo plano ni push remoto en esta versión.").font(.caption)
            }
            Section("Apariencia") {
                Picker("Tema", selection: $palette) { ForEach(palettes.indices, id: \.self) { i in Text(palettes[i].0).tag(i) } }
            }
            Section("Categorías") {
                let names = model.records("categories").first?.data["names"].array.map(\.string) ?? []
                ForEach(names, id: \.self) { Text($0) }
                TextField("Nueva categoría", text: $category)
                Button("Agregar categoría") {
                    let clean = category.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
                    let all = Array(Set(names + [clean])).sorted { $0.lowercased() == $1.lowercased() ? $0 < $1 : $0.lowercased() < $1.lowercased() }
                    model.edit("categories", "catalog", .object(["names": .array(all.map { .string($0) })])); if model.message == nil { category = "" }
                }.disabled(category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || category.count > 40)
            }
            Section("Envíos familiares pendientes") {
                ForEach(model.ledger.familyOutbox ?? []) { operation in
                    VStack(alignment: .leading) {
                        Text(operation.preview?["title"].string ?? operation.taskID)
                        Text(operation.method + " · " + operation.taskID).font(.caption)
                        Button("Revisar envío") { pendingOperation = operation.id }
                    }
                }
            }
            Section("Conflictos") {
                ForEach(model.ledger.entries.keys.sorted().filter { model.ledger.entries[$0]?.conflict != nil }, id: \.self) { key in
                    NavigationLink(key) { ConflictView(key: key) }
                }
                Text("Los registros con conflicto se conservan hasta que elijas una versión.").font(.caption)
            }
            Section("Versión") { Text("Lista Clara iOS 1.0.0 (1) · API v1") }
        }.navigationTitle("Ajustes")
            .confirmationDialog("Descartar el envío local y volver a consultar el servidor. Un envío que ya llegó al servidor no se revierte.", isPresented: Binding(get: { pendingOperation != nil }, set: { if !$0 { pendingOperation = nil } }), titleVisibility: .visible) {
                Button("Descartar envío", role: .destructive) { if let pendingOperation { model.discardFamilyOperation(pendingOperation) }; pendingOperation = nil }
            }
            .confirmationDialog("¿Cerrar sesión? Los datos guardados permanecerán separados en este iPhone.", isPresented: $disconnect, titleVisibility: .visible) { Button("Cerrar sesión", role: .destructive) { Task { await model.logout() } } }
    }
}
struct ConflictView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let key: String
    var body: some View {
        List {
            if let e = model.ledger.entries[key], let remote = e.conflict {
                Section("En este iPhone") { Text(pretty(e.local)).font(.caption.monospaced()).textSelection(.enabled) }
                Section("En el servidor · versión \(remote.version)") { Text(pretty(remote.data)).font(.caption.monospaced()).textSelection(.enabled) }
                Button("Conservar versión del iPhone") { model.resolve(key, local: true); dismiss() }
                Button("Usar versión del servidor") { model.resolve(key, local: false); dismiss() }
            }
        }.navigationTitle("Resolver conflicto")
    }
    func pretty(_ value: JSON) -> String { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return (try? String(data: encoder.encode(value), encoding: .utf8)) ?? "" }
}
