import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol Transport {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}
public final class HTTPTransport: NSObject, Transport, URLSessionTaskDelegate {
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CoreError.message("Respuesta no válida") }
        guard data.count <= 32 * 1024 * 1024 else { throw CoreError.message("Respuesta demasiado grande") }
        return (data, response.statusCode)
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // Never forward the bearer token to a redirect destination.
    }
}
public struct API {
    public var base: URL
    public var token: String
    public var transport: any Transport
    public init(base: URL, token: String = "", transport: any Transport = HTTPTransport()) {
        self.base = base; self.token = token; self.transport = transport
    }
    public func call(_ path: String, method: String = "GET", body: JSON? = nil) async throws -> JSON {
        guard path.hasPrefix("/api/v1/"), !path.contains(".."),
              let url = URL(string: base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else { throw CoreError.message("Ruta no válida") }
        var request = URLRequest(url: url); request.httpMethod = method; request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !token.isEmpty { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let body {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            request.httpBody = try encoder.encode(body)
            guard request.httpBody!.count <= 2 * 1024 * 1024 else { throw CoreError.message("Registro demasiado grande") }
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, code) = try await transport.send(request)
        guard (200..<300).contains(code) else { throw CoreError.http(code) }
        return code == 204 ? .null : try JSONDecoder().decode(JSON.self, from: data)
    }
    public func login(username: String, password: String) async throws -> JSON {
        // Protocol 1 calls all non-cookie bearer clients "android"; "ios" is not accepted.
        let result = try await call("/api/v1/auth/login", method: "POST", body: .object([
            "username": .string(username.trimmingCharacters(in: .whitespacesAndNewlines)),
            "password": .string(password), "client": .string("android")]))
        guard result["protocol"].number == 1, !result["token"].string.isEmpty else { throw CoreError.message("Protocolo incompatible") }
        return result
    }
    public func record(_ json: JSON) throws -> Record {
        try JSONDecoder().decode(Record.self, from: JSONEncoder().encode(json))
    }
}

// Serial caller owns durable storage. Every pending operation is persisted BEFORE HTTP.
// Failed/ambiguous HTTP leaves the exact opId and payload available for an idempotent retry.
public struct Synchronizer {
    public var api: API
    public var identity: String
    public init(api: API, identity: String) { self.api = api; self.identity = identity }
    public func run(load: () -> Ledger, save: (Ledger) throws -> Void) async throws {
        let me = try await api.call("/api/v1/auth/me")
        guard me["protocol"].number == 1, me["serverId"].string + "/" + me["id"].string == identity else {
            throw CoreError.message("La identidad del servidor cambió; sincronización detenida.")
        }
        var state = load()
        for key in state.entries.keys.sorted(by: { priority($0) < priority($1) }) {
            guard var e = state.entries[key], e.conflict == nil else { continue }
            if e.pending == nil && e.local != e.record.data {
                e.pending = Mutation(kind: e.record.kind, id: e.record.id, baseVersion: e.record.version, data: e.local)
                state.entries[key] = e; try save(state)
            }
            guard let pending = e.pending else { continue }
            let body = try JSONDecoder().decode(JSON.self, from: JSONEncoder().encode(pending))
            let result = try await api.call("/api/v1/mutations", method: "POST", body: body)
            let remote = try api.record(result["record"])
            if result["conflict"].bool { e.conflict = remote }
            else { e.record = remote; if e.local == pending.data { e.local = remote.data } }
            e.pending = nil; state.entries[key] = e; try save(state)
        }
        var more = true
        while more {
            let page = try await api.call("/api/v1/changes?cursor=\(state.cursor)&limit=100")
            for json in page["records"].array { state.integrate(try api.record(json)) }
            let next = Int(page["cursor"].number)
            more = page["hasMore"].bool
            guard next >= state.cursor, !more || next > state.cursor else { throw CoreError.message("Cursor inválido") }
            state.cursor = next; try save(state)
        }
        state.family = try await api.call("/api/v1/family/current")
        // Family API has no CAS versions/opId. Persist order and UUID creates, and
        // leave denied/failed operations in the queue for user inspection.
        while let operation = state.familyOutbox?.first {
            do { _ = try await api.call(operation.path, method: operation.method, body: operation.body) }
            catch CoreError.http(404) where operation.method == "DELETE" { /* already deleted */ }
            state.familyOutbox?.removeFirst(); try save(state)
        }
        // A user without a family receives an error for tasks; do not mask actual permission errors.
        if state.family["family"] != .null {
            state.tasks = try await api.call("/api/v1/family/tasks?scope=all")["tasks"].array
        } else { state.tasks = [] }
        try save(state)
    }
    private func priority(_ key: String) -> String {
        let kind = key.components(separatedBy: "/")[0]
        return (["categories": "0", "list": "1", "event": "2", "occurrence": "3"][kind] ?? "4") + key
    }
}
