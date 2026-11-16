import SwiftUI
import UIKit
import AVFoundation

@main struct ListaClaraApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model)
                .onChange(of: phase) { value in
                    if value != .active {
                        model.notifications.speech.stopSpeaking(at: .immediate)
                        if UserDefaults.standard.bool(forKey: "biometricLock") { model.locked = true }
                    } else if !model.locked { Task { await model.sync() } }
                }
        }
    }
}
let palettes: [(String, UInt, UInt)] = [
    ("Plan claro", 0xC65035, 0xF5F2EB), ("Noche violeta", 0xB7A1FF, 0x101321),
    ("Azul océano", 0x8DBBFF, 0x101321), ("Verde menta", 0x79D9BF, 0x101321),
    ("Rosa suave", 0xF0A7C4, 0x101321), ("Ámbar", 0xEBC182, 0x101321), ("Hielo", 0xC4D3E8, 0x101321)]
let listColors: [UInt] = [0x79D9BF, 0xB7A1FF, 0xF0A7C4, 0xEBC182]
extension Color {
    init(hex: UInt) { self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255) }
}
struct RootView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("palette") var palette = 0
    var body: some View {
        Group {
            if !model.ready { VStack { Text("No se pudo abrir el almacenamiento."); Text(model.message ?? "") } }
            else if model.locked {
                VStack(spacing: 24) { Image(systemName: "lock.shield").font(.largeTitle); Text("Lista Clara").font(.largeTitle)
                    Button("Desbloquear") { Task { await model.unlock(); if !model.locked { await model.sync() } } } }
            } else {
                TabView {
                    NavigationStack { EventsView() }.tabItem { Label("Eventos", systemImage: "calendar") }
                    NavigationStack { ListsView() }.tabItem { Label("Listas", systemImage: "checklist") }
                    NavigationStack { FamilyView() }.tabItem { Label("Tareas", systemImage: "person.2") }
                    NavigationStack { StatsView() }.tabItem { Label("Chismo", systemImage: "chart.bar") }
                    NavigationStack { SettingsView() }.tabItem { Label("Ajustes", systemImage: "gearshape") }
                }
                .disabled(model.busy)
                .overlay(alignment: .top) { if model.busy { ProgressView("Sincronizando…").padding().background(.regularMaterial).clipShape(Capsule()) } }
            }
        }
        .sheet(isPresented: Binding(get: { model.reminderToOpen != nil && !model.locked }, set: { if !$0 { model.reminderToOpen = nil } })) {
            NavigationStack {
                if let key = model.reminderToOpen {
                    let parts = key.split(separator: "/").map(String.init)
                    if parts.count >= 2 {
                        if parts[0] == "list" { ListDetail(id: parts[1]) }
                        else if parts[0] == "event" { EventDetail(id: parts[1]) }
                        else { FamilyTaskDetail(taskID: parts[1]) }
                    }
                }
            }
        }
        .tint(Color(hex: palettes[min(max(palette, 0), palettes.count - 1)].1))
        .preferredColorScheme(palette == 0 ? .light : .dark)
        .alert("Lista Clara", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("Aceptar") { model.message = nil }
        } message: { Text(model.message ?? "") }
        .task {
            if !model.locked { await model.sync(); await model.updateReminders() }
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { break }
                if !model.locked && UIApplication.shared.applicationState == .active { await model.sync() }
            }
        }
    }
}
struct ListsView: View {
    @EnvironmentObject var model: AppModel
    @State var search = ""
    @State var create = false
    var body: some View {
        List {
            Section {
                Text("Todo en su lugar.").font(.title2.bold())
                Text("Tus listas, siempre contigo.").foregroundStyle(.secondary)
                NavigationLink("Plan de hoy") { DailyPlanView() }
            }
            ForEach(model.records("list").filter { search.isEmpty || $0.data["name"].string.localizedCaseInsensitiveContains(search) || $0.data["category"].string.localizedCaseInsensitiveContains(search) }) { record in
                NavigationLink { ListDetail(id: record.id) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text(record.data["icon"].string.isEmpty ? "🛒" : record.data["icon"].string).font(.title).padding(12).background(Color(hex: listColors[min(max(Int(record.data["color"].number), 0), 3)]).opacity(0.2), in: RoundedRectangle(cornerRadius: 16))
                            VStack(alignment: .leading) { Text(record.data["name"].string).font(.headline); Text(record.data["category"].string).font(.caption) } }
                        let items = record.data["items"].array
                        if !items.isEmpty { ProgressView(value: Double(items.filter { $0["completed"].bool }.count), total: Double(items.count)) }
                    }.padding(.vertical, 8)
                }
            }
            if model.records("list").isEmpty { Text("Tu día empieza con una lista. Organiza compras, tareas o revisiones sin una cuenta.") }
        }.navigationTitle("Lista Clara").searchable(text: $search, prompt: "Lista o categoría")
            .refreshable { await model.sync() }
            .toolbar { Button { create = true } label: { Label("Nueva lista", systemImage: "plus") } }
            .sheet(isPresented: $create) { RecordEditor(kind: "list") }
    }
}
struct DailyPlanView: View {
    @EnvironmentObject var model: AppModel
    var today: [Record] { model.records("list").filter { $0.data["reminderAt"] != .null && Calendar.current.isDateInToday(Date(timeIntervalSince1970: $0.data["reminderAt"].number / 1000)) } }
    var body: some View {
        List {
            Text("Pequeños pasos, grandes cambios.").font(.title2)
            let items = today.flatMap { $0.data["items"].array }
            Text("\(items.filter { $0["completed"].bool }.count) de \(items.count) elementos completados")
            ForEach(today) { r in NavigationLink(r.data["name"].string) { ListDetail(id: r.id) } }
            if today.isEmpty { Text("Tu día tiene espacio. Asigna un recordatorio a una lista.") }
        }.navigationTitle("Plan de hoy")
    }
}
struct ListDetail: View {
    @EnvironmentObject var model: AppModel
    let id: String
    @State var editing = false
    @State var add = false
    @State var ticket = false
    @State var item: JSON?
    @State var storeMode = false
    @State var delete = false
    @Environment(\.dismiss) var dismiss
    var record: Record? { model.records("list").first { $0.id == id } }
    var body: some View {
        Group {
            if let r = record {
                List {
                    Toggle("Modo tienda", isOn: $storeMode)
                    Section("Pendientes") { itemRows(r, completed: false) }
                    Section("Historial · completados") { itemRows(r, completed: true) }
                    Button("Agregar elemento") { item = nil; add = true }
                    Button("Leer ticket desde foto") { ticket = true }
                    Button("Leer lista") { model.notifications.speak(r.data["name"].string + ". " + r.data["items"].array.filter { !$0["completed"].bool }.map { $0["name"].string }.joined(separator: ", ")) }
                    ShareLink(item: share(r)) { Label("Compartir", systemImage: "square.and.arrow.up") }
                    Button("Reutilizar lista") { var data = r.data; data["items"] = .array(data["items"].array.map { var i = $0; i["completed"] = .bool(false); return i }); model.edit("list", id, data) }
                    Button("Eliminar lista", role: .destructive) { delete = true }
                }.navigationTitle(r.data["name"].string)
                    .toolbar { Button("Editar") { editing = true } }
                    .sheet(isPresented: $editing) { RecordEditor(kind: "list", existing: r) }
                    .sheet(isPresented: $add) { ItemEditor(list: r, existing: item) }
                    .sheet(isPresented: $ticket) { TicketImport(list: r) }
                    .confirmationDialog("¿Eliminar la lista y sus elementos?", isPresented: $delete, titleVisibility: .visible) {
                        Button("Eliminar", role: .destructive) { model.edit("list", id, .null); if model.records("list").allSatisfy({ $0.id != id }) { dismiss() } }
                    }
            } else { Text("Lista eliminada") }
        }
    }
    @ViewBuilder func itemRows(_ r: Record, completed: Bool) -> some View {
        ForEach(r.data["items"].array.filter { $0["completed"].bool == completed }.sorted { $0["position"].number < $1["position"].number }, id: \.selfID) { i in
            HStack {
                Button { change(r, i, remove: false) } label: { Image(systemName: completed ? "checkmark.circle.fill" : "circle").font(storeMode ? .largeTitle : .title2) }.buttonStyle(.borderless).accessibilityLabel(completed ? "Reabrir elemento" : "Completar elemento")
                Button { item = i; add = true } label: {
                    Text("\(i["quantity"].number.formatted()) \(i["unit"].string) \(i["name"].string)").font(storeMode ? .title2 : .body).strikethrough(completed)
                }.buttonStyle(.plain)
                if !storeMode {
                    Button { move(r, i, direction: -1) } label: { Image(systemName: "arrow.up") }.buttonStyle(.borderless).accessibilityLabel("Subir elemento")
                    Button { move(r, i, direction: 1) } label: { Image(systemName: "arrow.down") }.buttonStyle(.borderless).accessibilityLabel("Bajar elemento")
                }
            }.padding(.vertical, storeMode ? 12 : 3)
                .swipeActions { Button("Eliminar", role: .destructive) { item = i; deleteItem = true } }
        }
        .confirmationDialog("¿Eliminar elemento?", isPresented: $deleteItem) {
            Button("Eliminar", role: .destructive) { if let item { change(r, item, remove: true) } }
        }
    }
    @State private var deleteItem = false
    func move(_ r: Record, _ item: JSON, direction: Int) {
        var ordered = r.data["items"].array.sorted { $0["position"].number < $1["position"].number }
        guard let index = ordered.firstIndex(where: { $0["id"] == item["id"] }), ordered.indices.contains(index + direction) else { return }
        ordered.swapAt(index, index + direction)
        ordered = ordered.enumerated().map { index, value in var next = value; next["position"] = .number(Double(index)); return next }
        var data = r.data; data["items"] = .array(ordered.sorted { $0["id"].string < $1["id"].string }); model.edit("list", id, data)
    }
    func change(_ r: Record, _ item: JSON, remove: Bool) {
        var data = r.data
        data["items"] = .array(data["items"].array.compactMap { i in
            guard i["id"] == item["id"] else { return i }
            if remove { return nil }; var next = i; next["completed"] = .bool(!i["completed"].bool); return next
        }); model.edit("list", id, data)
    }
    func share(_ r: Record) -> String {
        r.data["name"].string + "\n" + r.data["items"].array.map { "\($0["completed"].bool ? "☑" : "☐") \($0["quantity"].number.formatted()) \($0["unit"].string) \($0["name"].string)" }.joined(separator: "\n")
    }
}
extension JSON { var selfID: String { self["id"].string } }
struct ItemEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let list: Record
    var existing: JSON?
    @State var name = ""
    @State var quantity = 1.0
    @State var unit = ""
    var body: some View {
        NavigationStack {
            Form { TextField("Nombre", text: $name); TextField("Cantidad", value: $quantity, format: .number).keyboardType(.decimalPad); TextField("Unidad", text: $unit) }
                .navigationTitle(existing == nil ? "Agregar elemento" : "Editar elemento")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Guardar") { save() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 160 || !quantity.isFinite || quantity <= 0 || quantity > 999999 || unit.count > 30) } }
        }.onAppear { if let existing { name = existing["name"].string; quantity = existing["quantity"].number; unit = existing["unit"].string } }
    }
    func save() {
        guard let latest = model.records("list").first(where: { $0.id == list.id }) else { return }
        var data = latest.data, items = data["items"].array
        let currentItem = existing.flatMap { old in items.first { $0["id"] == old["id"] } }
        if let existing {
            guard let currentItem, ["name", "quantity", "unit"].allSatisfy({ currentItem[$0] == existing[$0] }) else {
                model.message = "El elemento cambió o fue eliminado. Cierra el formulario y revisa la lista."; return
            }
        }
        var i = currentItem ?? .object(["id": .string(UUID().uuidString), "position": .number((items.map { $0["position"].number }.max() ?? -1) + 1), "completed": .bool(false)])
        i["name"] = .string(name.trimmingCharacters(in: .whitespacesAndNewlines)); i["quantity"] = .number(quantity); i["unit"] = .string(unit.trimmingCharacters(in: .whitespacesAndNewlines))
        if let index = items.firstIndex(where: { $0["id"] == i["id"] }) { items[index] = i } else { items.append(i) }
        guard items.count <= 5000 else { model.message = "La lista admite hasta 5000 elementos."; return }
        data["items"] = .array(items.sorted { $0["id"].string < $1["id"].string }); model.edit("list", list.id, data); if model.message == nil { dismiss() }
    }
}
