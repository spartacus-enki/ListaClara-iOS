import Foundation

public enum JSON: Codable, Equatable {
    case object([String: JSON]), array([JSON]), string(String), number(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let x = try? c.decode(Bool.self) { self = .bool(x) }
        else if let x = try? c.decode(Double.self) { self = .number(x) }
        else if let x = try? c.decode(String.self) { self = .string(x) }
        else if let x = try? c.decode([String: JSON].self) { self = .object(x) }
        else { self = .array(try c.decode([JSON].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let x): try c.encode(x)
        case .array(let x): try c.encode(x)
        case .string(let x): try c.encode(x)
        case .number(let x): try c.encode(x)
        case .bool(let x): try c.encode(x)
        case .null: try c.encodeNil()
        }
    }
    public subscript(_ key: String) -> JSON {
        get { if case .object(let x) = self { return x[key] ?? .null }; return .null }
        set { var x = object; x[key] = newValue; self = .object(x) }
    }
    public var object: [String: JSON] { if case .object(let x) = self { return x }; return [:] }
    public var array: [JSON] { if case .array(let x) = self { return x }; return [] }
    public var string: String { if case .string(let x) = self { return x }; return "" }
    public var number: Double { if case .number(let x) = self { return x }; return 0 }
    public var bool: Bool { if case .bool(let x) = self { return x }; return false }
    public static func ms(_ date: Date) -> JSON { .number((date.timeIntervalSince1970 * 1000).rounded(.down)) }
}
public struct Record: Codable, Equatable, Identifiable {
    public var kind: String
    public var id: String
    public var version: Int
    public var seq: Int
    public var data: JSON
    public var key: String { kind + "/" + id }
    public init(kind: String, id: String, version: Int = 0, seq: Int = 0, data: JSON) {
        self.kind = kind; self.id = id; self.version = version; self.seq = seq; self.data = data
    }
}
public struct Mutation: Codable, Equatable {
    public var opId: String = UUID().uuidString
    public var kind: String
    public var id: String
    public var baseVersion: Int
    public var data: JSON
}
public struct Entry: Codable {
    public var record: Record
    public var local: JSON
    public var pending: Mutation?
    public var conflict: Record?
}
public struct FamilyOperation: Codable, Identifiable {
    public var id: String = UUID().uuidString
    public var taskID: String
    public var path: String
    public var method: String
    public var body: JSON?
    public var preview: JSON?
}
public struct Ledger: Codable {
    public var familyOutbox: [FamilyOperation]? = []
    public var cursor = 0
    public var entries: [String: Entry] = [:]
    public var family: JSON = .null
    public var tasks: [JSON] = []
    public var stats: JSON = .null
    public init() {}
    public mutating func edit(kind: String, id: String, data: JSON) throws {
        let key = kind + "/" + id
        var e = entries[key] ?? Entry(record: Record(kind: kind, id: id, data: .null), local: .null)
        guard e.pending == nil, e.conflict == nil else { throw CoreError.message("Sincroniza o resuelve el conflicto antes de editar este registro.") }
        e.local = data; entries[key] = e
    }
    public mutating func integrate(_ remote: Record) {
        guard var e = entries[remote.key] else {
            entries[remote.key] = Entry(record: remote, local: remote.data); return
        }
        switch merge(local: e.local, base: e.record.data, remote: remote.data,
                     baseVersion: e.record.version, remoteVersion: remote.version, conflict: e.conflict != nil) {
        case .ignore: return
        case .acknowledge: e.record = remote; e.conflict = nil
        case .apply: e.local = remote.data; e.record = remote
        case .conflict: e.conflict = remote
        }
        entries[remote.key] = e
    }
    public mutating func resolve(_ key: String, local: Bool) {
        guard var e = entries[key], let remote = e.conflict else { return }
        if !local { e.local = remote.data }
        e.record = remote; e.pending = nil; e.conflict = nil; entries[key] = e
    }
}
public enum MergeDecision: Equatable { case ignore, acknowledge, apply, conflict }
public func merge(local: JSON, base: JSON, remote: JSON, baseVersion: Int, remoteVersion: Int, conflict: Bool) -> MergeDecision {
    if remoteVersion < baseVersion { return .ignore }
    if !conflict && remoteVersion == baseVersion && remote == base { return .ignore }
    if local == remote { return .acknowledge }
    if !conflict && local == base { return .apply }
    return .conflict
}
public enum CoreError: LocalizedError {
    case message(String), http(Int)
    public var errorDescription: String? {
        switch self {
        case .message(let s): return s
        case .http(let c): return [401: "Sesión vencida o credenciales incorrectas.", 403: "Permiso rechazado por el servidor.", 409: "Reconciliación necesaria; se conservaron los datos.", 422: "Datos rechazados por el servidor.", 429: "Espera antes de volver a intentar."][c] ?? "Error del servidor (\(c))."
        }
    }
}
public func validServer(_ raw: String) throws -> URL {
    guard let c = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
          c.scheme == "https", let host = c.host, !host.isEmpty,
          c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
          c.path.isEmpty || c.path == "/", let url = c.url else {
        throw CoreError.message("Usa la URL raíz HTTPS del servidor, sin ruta ni credenciales.")
    }
    return url
}
public func canEditTask(_ task: JSON, user: String, role: String, delete: Bool = false) -> Bool {
    role == "admin" || role == "padre" || task["createdBy"].string == user || (!delete && task["assignedTo"].string == user)
}
