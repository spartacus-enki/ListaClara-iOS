import SwiftUI

struct FamilyView: View {
    @EnvironmentObject var model: AppModel
    @State var create = false
    @State var history = false
    @State var priority = "ALL"
    var body: some View {
        List {
            Section(model.ledger.family["family"]["name"].string.isEmpty ? "Familia" : model.ledger.family["family"]["name"].string) {
                ForEach(model.ledger.family["members"].array, id: \.selfID) { member in Text(member["username"].string + " · " + member["role"].string) }
                if model.session == nil { Text("Conecta tu cuenta en Ajustes.") }
                else if model.ledger.family["family"] == .null { Text("Tu cuenta no tiene un grupo familiar asignado.") }
            }
            Toggle("Ver historial", isOn: $history)
            Picker("Prioridad", selection: $priority) { Text("Todas").tag("ALL"); Text("Alta").tag("HIGH"); Text("Media").tag("MEDIUM"); Text("Baja").tag("LOW") }
            ForEach(model.ledger.tasks.filter { ($0["status"].string != "PENDING") == history && (priority == "ALL" || $0["priority"].string == priority) }, id: \.selfID) { task in
                NavigationLink { FamilyTaskDetail(taskID: task["id"].string) } label: {
                    VStack(alignment: .leading) {
                        Text(task["title"].string).font(.headline)
                        Text(task["assignedToName"].string + " · " + task["priority"].string + " · " + task["status"].string).font(.caption)
                        if task["dueAt"] != .null { Text(Date(timeIntervalSince1970: task["dueAt"].number / 1000).formatted()).font(.caption) }
                    }
                }
            }
            Text("Los cambios se guardan en este iPhone y se envían al sincronizar. Desliza para actualizar.").font(.caption).foregroundStyle(.secondary)
        }.navigationTitle("Tareas familiares").refreshable { await model.sync() }
            .toolbar { Button { create = true } label: { Label("Nueva tarea", systemImage: "plus") }.disabled(model.ledger.family["family"] == .null) }
            .sheet(isPresented: $create) { FamilyTaskEditor() }
    }
}
struct FamilyTaskDetail: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let taskID: String
    @State var edit = false
    @State var delete = false
    var body: some View {
        if let t = model.ledger.tasks.first(where: { $0["id"].string == taskID }) {
            List {
                Text(t["title"].string).font(.title2); Text(t["note"].string)
                Text("Asignada a: " + t["assignedToName"].string)
                Text("Creada por: " + t["createdByName"].string)
                Text("Estado: " + t["status"].string); Text("Repetición: " + t["repeat"].string)
                Button("Leer tarea") { model.notifications.speak(t["title"].string + ". " + t["note"].string) }
                if canEditTask(t, user: model.userID, role: model.role) {
                    Button("Editar tarea") { edit = true }
                    Button(t["status"].string == "PENDING" ? "Completar tarea" : "Reabrir tarea") {
                        Task { await model.familyMutation("/api/v1/family/tasks/\(taskID)/complete", method: "POST", body: .object(["status": .string(t["status"].string == "PENDING" ? "DONE" : "PENDING")])) }
                    }
                    Button("Cancelar tarea") { Task { await model.familyMutation("/api/v1/family/tasks/\(taskID)/complete", method: "POST", body: .object(["status": .string("CANCELLED")])) } }
                }
                if canEditTask(t, user: model.userID, role: model.role, delete: true) { Button("Eliminar tarea", role: .destructive) { delete = true } }
            }.navigationTitle("Tarea").sheet(isPresented: $edit) { FamilyTaskEditor(existing: t) }
                .confirmationDialog("¿Eliminar tarea?", isPresented: $delete) {
                    Button("Eliminar", role: .destructive) { Task { await model.familyMutation("/api/v1/family/tasks/\(taskID)", method: "DELETE"); if model.message == nil { dismiss() } } }
                }
        } else { Text("Tarea no disponible") }
    }
}
struct FamilyTaskEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    var existing: JSON?
    @State var title = ""
    @State var note = ""
    @State var assigned = ""
    @State var mode = "ONCE"
    @State var priority = "MEDIUM"
    @State var hasDue = false
    @State var due = Date().addingTimeInterval(3600)
    @State private var draftID = UUID().uuidString
    var body: some View {
        NavigationStack {
            Form {
                TextField("Título", text: $title); TextField("Nota", text: $note, axis: .vertical)
                Picker("Asignar a", selection: $assigned) { ForEach(model.ledger.family["members"].array, id: \.selfID) { m in Text(m["username"].string).tag(m["id"].string) } }
                Picker("Prioridad", selection: $priority) { Text("Alta").tag("HIGH"); Text("Media").tag("MEDIUM"); Text("Baja").tag("LOW") }
                Picker("Repetición", selection: $mode) { Text("Una vez").tag("ONCE"); Text("Semanal").tag("WEEKLY"); Text("Mensual").tag("MONTHLY"); Text("Intervalo del servidor").tag("INTERVAL") }
                Toggle("Vencimiento", isOn: $hasDue); if hasDue { DatePicker("Fecha", selection: $due) }
                Text("Se guardará localmente y se enviará con los permisos de tu cuenta.").font(.caption)
            }.navigationTitle(existing == nil ? "Nueva tarea" : "Editar tarea")
                .disabled(model.busy)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(model.busy) }
                    ToolbarItem(placement: .confirmationAction) { Button("Guardar") { Task { await save() } }.disabled(model.busy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 120 || note.count > 500 || assigned.isEmpty) }
                }
        }.interactiveDismissDisabled(model.busy).onAppear {
            assigned = model.userID
            if let t = existing { title = t["title"].string; note = t["note"].string; assigned = t["assignedTo"].string; mode = t["repeat"].string; priority = t["priority"].string; hasDue = t["dueAt"] != .null; if hasDue { due = Date(timeIntervalSince1970: t["dueAt"].number / 1000) } }
        }
    }
    func save() async {
        var body: JSON = .object(["title": .string(title.trimmingCharacters(in: .whitespacesAndNewlines)), "note": .string(note), "assignedTo": .string(assigned), "repeat": .string(mode), "priority": .string(priority)])
        if hasDue { body["dueAt"] = .ms(due) }
        if existing == nil { body["id"] = .string(draftID) } else { body["clearDueAt"] = .bool(!hasDue) }
        await model.familyMutation("/api/v1/family/tasks" + (existing.map { "/" + $0["id"].string } ?? ""), method: existing == nil ? "POST" : "PUT", body: body)
        if model.message == nil { dismiss() }
    }
}
struct StatsView: View {
    @EnvironmentObject var model: AppModel
    @State var period = Date()
    var body: some View {
        List {
            DatePicker("Período", selection: $period, displayedComponents: .date)
            Button("Consultar") { Task { await load() } }.disabled(model.session == nil)
            Text(model.ledger.stats["period"]["label"].string).font(.title2)
            Section("Estadísticas") {
                ForEach(model.ledger.stats["metrics"].object.keys.sorted(), id: \.self) { key in
                    LabeledContent(metricLabel(key), value: display(model.ledger.stats["metrics"][key]))
                }
            }
            Section("Podio") { ForEach(model.ledger.stats["podium"].array, id: \.userID) { r in Text(r["medal"].string + " " + r["username"].string + " · " + display(r["closedCount"])) } }
            Section("Ranking") { ForEach(model.ledger.stats["ranking"].array, id: \.userID) { r in LabeledContent(r["username"].string, value: display(r["closedCount"])) } }
            Section("Tareas vencidas") { ForEach(model.ledger.stats["overdueTasks"].array, id: \.selfID) { r in Text(r["title"].string + " · " + r["assignedToName"].string) } }
        }.navigationTitle("Chismógrafo").task { await load() }
    }
    func load() async { let c = Calendar.current; await model.stats(year: c.component(.year, from: period), month: c.component(.month, from: period)) }
    func display(_ json: JSON) -> String { if case .number(let n) = json { return n.formatted() }; return json.string }
    func metricLabel(_ key: String) -> String { ["closedTasks": "Tareas cerradas", "openTasks": "Pendientes", "highPriorityPending": "Prioridad alta", "recurringActive": "Recurrentes", "activeUsers": "Miembros activos", "averagePerUser": "Promedio por miembro", "bestRecord": "Mejor marca"][key] ?? key }
}
extension JSON { var userID: String { self["userId"].string } }
