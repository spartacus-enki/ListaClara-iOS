import SwiftUI
import PhotosUI
import Vision

struct TicketImport: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let list: Record
    @State var selection: PhotosPickerItem?
    @State var text = ""
    @State var reading = false
    @State var error: String?
    var lines: [String] { text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
    var body: some View {
        NavigationStack {
            Form {
                PhotosPicker(selection: $selection, matching: .images) { Label("Elegir foto del ticket", systemImage: "photo") }.disabled(reading)
                Text("Revisa y corrige el resultado antes de guardar. Cada línea se agregará como un elemento. También puedes dictar con el teclado de iPhone.").font(.caption)
                if reading { ProgressView("Leyendo texto…") }
                if let error { Text(error).foregroundStyle(.red) }
                TextEditor(text: $text).frame(minHeight: 260)
                Text("\(lines.count) elementos · máximo 200")
            }.navigationTitle("Leer ticket")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Agregar") { save() }.disabled(reading || lines.isEmpty || lines.count > 200 || lines.contains { $0.count > 160 } || model.busy) }
                }
        }.task(id: selection) { await recognize() }
    }
    func recognize() async {
        guard let selection else { return }
        reading = true; defer { reading = false }
        do {
            guard let data = try await selection.loadTransferable(type: Data.self) else { return }
            guard data.count <= 25 * 1024 * 1024 else { throw CoreError.message("Selecciona una imagen de menos de 25 MB.") }
            text = try await Task.detached(priority: .userInitiated) {
                let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
                request.recognitionLanguages = ["es-MX", "en-US"]; request.usesLanguageCorrection = true
                try VNImageRequestHandler(data: data, options: [:]).perform([request])
                return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            }.value
        } catch { self.error = error.localizedDescription }
    }
    func save() {
        guard let current = model.records("list").first(where: { $0.id == list.id }) else { return }
        var data = current.data, items = data["items"].array
        let position = (items.map { $0["position"].number }.max() ?? -1) + 1
        for (offset, name) in lines.enumerated() { items.append(.object([
            "id": .string(UUID().uuidString), "name": .string(name), "quantity": .number(1), "unit": .string(""), "completed": .bool(false), "position": .number(position + Double(offset))])) }
        guard items.count <= 5000 else { error = "La lista admite hasta 5000 elementos."; return }
        data["items"] = .array(items.sorted { $0["id"].string < $1["id"].string }); model.edit("list", list.id, data)
        if model.message == nil { dismiss() }
    }
}
