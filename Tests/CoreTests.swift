import XCTest
@testable import ListaClaraCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class CoreTests: XCTestCase {
    func testMergeMatchesAndroidDecisions() {
        let a = JSON.string("a"), b = JSON.string("b"), c = JSON.string("c")
        XCTAssertEqual(merge(local: a, base: a, remote: b, baseVersion: 2, remoteVersion: 1, conflict: false), .ignore)
        XCTAssertEqual(merge(local: b, base: a, remote: a, baseVersion: 1, remoteVersion: 1, conflict: false), .ignore)
        XCTAssertEqual(merge(local: b, base: a, remote: b, baseVersion: 1, remoteVersion: 2, conflict: true), .acknowledge)
        XCTAssertEqual(merge(local: a, base: a, remote: b, baseVersion: 1, remoteVersion: 2, conflict: false), .apply)
        XCTAssertEqual(merge(local: b, base: a, remote: c, baseVersion: 1, remoteVersion: 2, conflict: false), .conflict)
    }
    func testTombstoneAndResolutionPreserveLocal() throws {
        var ledger = Ledger()
        ledger.integrate(Record(kind: "list", id: "x", version: 1, data: .string("base")))
        try ledger.edit(kind: "list", id: "x", data: .string("local"))
        ledger.integrate(Record(kind: "list", id: "x", version: 2, data: .null))
        XCTAssertEqual(ledger.entries["list/x"]?.local, .string("local"))
        XCTAssertNotNil(ledger.entries["list/x"]?.conflict)
        ledger.resolve("list/x", local: true)
        XCTAssertEqual(ledger.entries["list/x"]?.record.version, 2)
        XCTAssertEqual(ledger.entries["list/x"]?.local, .string("local"))
        XCTAssertEqual(ledger.entries["list/x"]?.record.data, .null)
    }
    func testJSONSemanticEqualityAndMilliseconds() throws {
        let a = try JSONDecoder().decode(JSON.self, from: Data("{\"n\":1,\"x\":null}".utf8))
        let b = try JSONDecoder().decode(JSON.self, from: Data("{\"x\":null,\"n\":1.0}".utf8))
        XCTAssertEqual(a, b)
        let ms = JSON.number(1794848400123)
        XCTAssertEqual(try JSONDecoder().decode(JSON.self, from: JSONEncoder().encode(ms)), ms)
    }
    func testURLAndPermissions() throws {
        XCTAssertNoThrow(try validServer("https://sparta.example:8443/"))
        for s in ["http://sparta.example", "https://a@sparta.example", "https://sparta.example/api", "https://sparta.example/?token=a"] { XCTAssertThrowsError(try validServer(s)) }
        let task = JSON.object(["createdBy": .string("creator"), "assignedTo": .string("child")])
        XCTAssertTrue(canEditTask(task, user: "child", role: "hijo"))
        XCTAssertFalse(canEditTask(task, user: "child", role: "hijo", delete: true))
        XCTAssertTrue(canEditTask(task, user: "parent", role: "padre", delete: true))
        XCTAssertFalse(canEditTask(task, user: "other", role: "user"))
    }
    func event(_ mode: String = "INTERVAL") -> JSON {
        .object(["enabled": .bool(true), "zone": .string("UTC"), "start": .number(0), "repeat": .string(mode), "hours": .number(8), "days": .number(1), "weekdays": .array([1,2,3,4,5,6,7].map { .number(Double($0)) }), "revision": .string("r")])
    }
    func testIntervalExclusiveEndAndStrictAfter() {
        let dates = eventDates(event(), after: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(dates.map(\.timeIntervalSince1970), [28800, 57600])
        XCTAssertTrue(eventDates(event("ONCE"), after: Date(timeIntervalSince1970: 0)).isEmpty)
    }
    func testWeeklyUsesStartClockInsteadOfLegacyTimes() {
        var e = event("WEEKLY"); e["days"] = .null; e["start"] = .number(4 * 86400000 + 10 * 3600000)
        e["weekdays"] = .array([.number(1)]); e["times"] = .array([.string("23:59")])
        let next = eventDates(e, after: Date(timeIntervalSince1970: 0), limit: 2)
        XCTAssertEqual(next.map(\.timeIntervalSince1970), [4 * 86400 + 10 * 3600, 11 * 86400 + 10 * 3600])
    }
    func testSilencedOccurrenceAndQueueBudget() {
        var ledger = Ledger(); var e = event(); e["days"] = .null
        ledger.integrate(Record(kind: "event", id: "e", data: e))
        ledger.integrate(Record(kind: "occurrence", id: "e~28800000", data: .object(["eventId": .string("e"), "at": .number(28800000), "revision": .string("r"), "status": .string("PENDING"), "silenced": .bool(true)])))
        let plan = reminderPlan(ledger, now: Date(timeIntervalSince1970: 0), limit: 60)
        XCTAssertEqual(plan.count, 59)
        XCTAssertFalse(plan.contains { $0.at.timeIntervalSince1970 == 28800 })
    }
    func testLoginUsesExistingBearerMode() async throws {
        let mock = MockTransport([(.object(["protocol": .number(1), "token": .string("secret")]), 200)])
        _ = try await API(base: URL(string: "https://sparta.example")!, transport: mock).login(username: " user ", password: "pass")
        let request = try XCTUnwrap(mock.requests.first)
        let body = try JSONDecoder().decode(JSON.self, from: request.httpBody!)
        XCTAssertEqual(body["client"], .string("android")); XCTAssertEqual(body["username"], .string("user"))
    }
    func testAmbiguousMutationRetryReusesOperation() async throws {
        var state = Ledger(); try state.edit(kind: "list", id: "x", data: .string("local"))
        let me = JSON.object(["protocol": .number(1), "serverId": .string("s"), "id": .string("u")])
        let first = MockTransport([(me, 200), (.null, 503)])
        do { try await Synchronizer(api: API(base: URL(string: "https://sparta.example")!, transport: first), identity: "s/u").run(load: { state }, save: { state = $0 }); XCTFail("must fail") } catch {}
        let pending = try XCTUnwrap(state.entries["list/x"]?.pending)
        XCTAssertThrowsError(try state.edit(kind: "list", id: "x", data: .string("changed")))
        let second = MockTransport([(me, 200), (.null, 503)])
        do { try await Synchronizer(api: API(base: URL(string: "https://sparta.example")!, transport: second), identity: "s/u").run(load: { state }, save: { state = $0 }) } catch {}
        XCTAssertEqual(state.entries["list/x"]?.pending?.opId, pending.opId)
        XCTAssertEqual(first.requests[1].httpBody, second.requests[1].httpBody)
    }
    func testSuccessfulSyncPersistsPagesAndFlushesFamilyOutbox() async throws {
        var state = Ledger()
        try state.edit(kind: "categories", id: "catalog", data: .object(["names": .array([.string("Compras")])]))
        state.familyOutbox = [FamilyOperation(taskID: "task", path: "/api/v1/family/tasks/task/complete", method: "POST", body: .object(["status": .string("DONE")]), preview: nil)]
        let record = JSON.object(["kind": .string("categories"), "id": .string("catalog"), "version": .number(1), "seq": .number(1), "data": .object(["names": .array([.string("Compras")])])])
        let mock = MockTransport([
            (.object(["protocol": .number(1), "serverId": .string("s"), "id": .string("u")]), 200),
            (.object(["conflict": .bool(false), "record": record]), 200),
            (.object(["records": .array([record]), "cursor": .number(1), "hasMore": .bool(true)]), 200),
            (.object(["records": .array([]), "cursor": .number(4), "hasMore": .bool(false)]), 200),
            (.object(["family": .object(["id": .string("f")]), "members": .array([])]), 200),
            (.object(["id": .string("task"), "status": .string("DONE")]), 200),
            (.object(["tasks": .array([.object(["id": .string("task"), "status": .string("DONE")])])]), 200)
        ])
        var saves = 0
        try await Synchronizer(api: API(base: URL(string: "https://sparta.example")!, token: "token", transport: mock), identity: "s/u").run(load: { state }, save: { state = $0; saves += 1 })
        XCTAssertEqual(state.cursor, 4)
        XCTAssertEqual(state.entries["categories/catalog"]?.record.version, 1)
        XCTAssertNil(state.entries["categories/catalog"]?.pending)
        XCTAssertTrue(state.familyOutbox?.isEmpty == true)
        XCTAssertEqual(state.tasks.first?["status"], .string("DONE"))
        XCTAssertGreaterThanOrEqual(saves, 6)
        XCTAssertEqual(mock.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer token")
        XCTAssertTrue(mock.replies.isEmpty)
    }
    func testWeeklyDSTGapUsesSavedTimeZone() {
        let format = ISO8601DateFormatter()
        var e = event("WEEKLY")
        e["zone"] = .string("America/New_York")
        e["days"] = .null
        e["weekdays"] = .array([.number(7)])
        e["start"] = .ms(format.date(from: "2026-03-01T07:30:00Z")!)
        let next = eventDates(e, after: format.date(from: "2026-03-08T00:00:00Z")!, limit: 1)
        XCTAssertEqual(next.first, format.date(from: "2026-03-08T07:30:00Z"))
    }

    func testIdentityMismatchStopsBeforeUpload() async throws {
        let mock = MockTransport([(.object(["protocol": .number(1), "serverId": .string("other"), "id": .string("u")]), 200)])
        do { try await Synchronizer(api: API(base: URL(string: "https://sparta.example")!, transport: mock), identity: "s/u").run(load: { Ledger() }, save: { _ in }); XCTFail("must stop") } catch {}
        XCTAssertEqual(mock.requests.count, 1)
    }
}
final class MockTransport: Transport {
    var replies: [(JSON, Int)]
    var requests: [URLRequest] = []
    init(_ replies: [(JSON, Int)]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard !replies.isEmpty else { throw CoreError.message("Unexpected request") }
        let (body, code) = replies.removeFirst(); return (try JSONEncoder().encode(body), code)
    }
}
