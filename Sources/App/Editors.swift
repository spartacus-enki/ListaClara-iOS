import SwiftUI

struct RecordEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let kind: String
    var existing: Record?
    @State var title = ""
    @State var category = "General"
    @State var icon = "🛒"
    @State var listKind = "SHOPPING"
    @State var color = 0
    @State var date = Date().addingTimeInterval(3600)
    @State var reminder = false
    @State var note = ""
    @State var mode = "ONCE"
    @State var hours = 8
    @State var duration = false
    @State var days = 7
    @State var weekdays: Set<Int> = [1,2,3,4,5,6,7]
    @State var enabled = true
    @State var voice = true
    @State var zone = TimeZone.current.identifier
    var valid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= (kind == "list" ? 80 : 120) &&
        (kind == "list" ? !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && category.count <= 40 && icon.unicodeScalars.count <= 32 && !icon.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) : note.count <= 500 && (mode != "WEEKLY" || !weekdays.isEmpty))
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre", text: $title)
                if kind == "list" {
                    TextField("Emoji", text: $icon)
                    Picker("Tipo", selection: $listKind) { Text("Compras").tag("SHOPPING"); Text("Tareas").tag("TASKS"); Text("Revisiones").tag("REVIEW") }
                    TextField("Categoría", text: $category)
                    let names = model.records("categories").first?.data["names"].array.map(\.string) ?? ["Compras", "Tareas", "Revisiones"]
                    Picker("Categorías guardadas", selection: $category) { ForEach(Array(Set(names + [category])).sorted(), id: \.self) { Text($0).tag($0) } }
                    Picker("Color", selection: $color) { Text("Menta").tag(0); Text("Violeta").tag(1); Text("Rosa").tag(2); Text("Ámbar").tag(3) }
                    Toggle("Recordatorio", isOn: $reminder)
                    if reminder { DatePicker("Fecha y hora", selection: $date) }
                } else {
                    TextField("Nota", text: $note, axis: .vertical)
                    DatePicker("Inicio", selection: $date)
                    Text("Zona: \(zone)").font(.caption)
                    Picker("Repetición", selection: $mode) { Text("Una vez").tag("ONCE"); Text("Semanal").tag("WEEKLY"); Text("Por intervalo").tag("INTERVAL") }
                    if mode == "INTERVAL" { Stepper("Cada \(hours) horas", value: $hours, in: 1...720) }
                    if mode == "WEEKLY" {
                        ForEach(1...7, id: \.self) { day in
                            Toggle(["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"][day - 1], isOn: Binding(get: { weekdays.contains(day) }, set: { if $0 { weekdays.insert(day) } else { weekdays.remove(day) } }))
                        }
                    }
                    if mode != "ONCE" { Toggle("Limitar duración", isOn: $duration); if duration { Stepper("\(days) días", value: $days, in: 1...3650) } }
                    Toggle("Activo", isOn: $enabled); Toggle("Voz con la app en primer plano", isOn: $voice)
                    Text("Los avisos en segundo plano usan el sonido de notificación de iOS. La lectura de voz funciona con la app abierta.").font(.caption)
                }
            }.navigationTitle(existing == nil ? (kind == "list" ? "Nueva lista" : "Nuevo evento") : "Editar")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Guardar") { save() }.disabled(!valid) }
                }
        }.onAppear { load() }
    }
    func load() {
        guard let d = existing?.data else { return }
        title = d[kind == "list" ? "name" : "title"].string
        if kind == "list" {
            category = d["category"].string; icon = d["icon"].string; listKind = d["kind"].string; color = Int(d["color"].number)
            reminder = d["reminderAt"] != .null
            if reminder { date = Date(timeIntervalSince1970: d["reminderAt"].number / 1000) }
        } else {
            note = d["note"].string; date = Date(timeIntervalSince1970: d["start"].number / 1000)
            mode = d["repeat"].string; hours = Int(d["hours"].number); duration = d["days"] != .null
            days = duration ? Int(d["days"].number) : 7; weekdays = Set(d["weekdays"].array.map { Int($0.number) })
            enabled = d["enabled"].bool; voice = d["voice"].bool; zone = d["zone"].string
        }
    }
    func save() {
        if let existing, model.records(kind).first(where: { $0.id == existing.id })?.data != existing.data {
            model.message = "El registro cambió mientras lo editabas. Cierra el formulario y revisa la versión actual."; return
        }
        var d = existing?.data ?? .object([:])
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind == "list" {
            d["name"] = .string(clean); d["category"] = .string(category.trimmingCharacters(in: .whitespacesAndNewlines)); d["icon"] = .string(icon)
            d["kind"] = .string(listKind); d["color"] = .number(Double(color)); d["reminderAt"] = reminder ? .ms(date) : .null
            if existing == nil { d["items"] = .array([]) }
        } else {
            d["title"] = .string(clean); d["note"] = .string(note); d["start"] = .ms(date); d["repeat"] = .string(mode)
            d["hours"] = .number(Double(hours)); d["days"] = duration ? .number(Double(days)) : .null
            d["weekdays"] = .array(weekdays.sorted().map { .number(Double($0)) })
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: zone) ?? .current
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            d["times"] = .array([.string(String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0))])
            d["zone"] = .string(zone); d["voice"] = .bool(voice); d["enabled"] = .bool(enabled); d["revision"] = .string(UUID().uuidString)
        }
        model.edit(kind, existing?.id ?? UUID().uuidString, d)
        if model.message == nil { dismiss() }
    }
}
struct EventsView: View {
    @EnvironmentObject var model: AppModel
    @State var create = false
    var body: some View {
        List {
            ForEach(model.records("event")) { record in
                NavigationLink { EventDetail(id: record.id) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.data["title"].string).font(.headline)
                        Text(record.data["repeat"].string + (record.data["enabled"].bool ? " · Activo" : " · Pausado")).font(.caption)
                        if let next = eventDates(record.data, after: Date(), limit: 1).first { Text(next, style: .date); Text(next, style: .time) }
                    }
                }
            }
            if model.records("event").isEmpty { Text("Organiza tus eventos y recordatorios.") }
        }.navigationTitle("Eventos").refreshable { await model.sync() }
            .toolbar { Button { create = true } label: { Label("Nuevo evento", systemImage: "plus") } }
            .sheet(isPresented: $create) { RecordEditor(kind: "event") }
    }
}
struct EventDetail: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let id: String
    @State var editing = false
    @State var delete = false
    var body: some View {
        if let r = model.records("event").first(where: { $0.id == id }) {
            List {
                Text(r.data["note"].string)
                Text("Zona: \(r.data["zone"].string)")
                Button("Leer evento") { model.notifications.speak(r.data["title"].string + ". " + r.data["note"].string) }
                Section("Próximas ocasiones") {
                    ForEach(eventDates(r.data, after: Date()), id: \.self) { date in
                        VStack(alignment: .leading) {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                            HStack { Button("Hecho") { mark(r, date, status: "DONE") }; Button("Omitir") { mark(r, date, status: "SKIPPED") }; Button("Silenciar") { mark(r, date, status: "PENDING") } }.buttonStyle(.borderless)
                        }
                    }
                }
                Section("Historial") {
                    ForEach(model.records("occurrence").filter { $0.data["eventId"].string == id }) { o in
                        Text(Date(timeIntervalSince1970: o.data["at"].number / 1000).formatted() + " · " + o.data["status"].string + (o.data["silenced"].bool ? " · silenciado" : ""))
                    }
                }
                Button("Eliminar evento", role: .destructive) { delete = true }
            }.navigationTitle(r.data["title"].string).toolbar { Button("Editar") { editing = true } }
                .sheet(isPresented: $editing) { RecordEditor(kind: "event", existing: r) }
                .confirmationDialog("¿Eliminar evento?", isPresented: $delete) { Button("Eliminar", role: .destructive) { model.edit("event", id, .null); if model.message == nil { dismiss() } } }
        } else { Text("Evento eliminado") }
    }
    func mark(_ r: Record, _ date: Date, status: String) {
        let stamp = Int64((date.timeIntervalSince1970 * 1000).rounded())
        model.edit("occurrence", id + "~" + String(stamp), .object([
            "eventId": .string(id), "at": .number(Double(stamp)), "revision": r.data["revision"], "status": .string(status), "silenced": .bool(status == "PENDING")]))
    }
}
