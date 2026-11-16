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
        let actual: [TimeInterval] = dates.map(\.timeIntervalSince1970)
        let expected: [TimeInterval] = [28_800.0, 57_600.0]
        XCTAssertEqual(actual, expected)
        XCTAssertTrue(eventDates(event("ONCE"), after: Date(timeIntervalSince1970: 0)).isEmpty)
    }
    func testWeeklyUsesStartClockInsteadOfLegacyTimes() {
        var e = event("WEEKLY"); e["days"] = .null; e["start"] = .number(4 * 86400000 + 10 * 3600000)
        e["weekdays"] = .array([.number(1)]); e["times"] = .array([.string("23:59")])
        let next = eventDates(e, after: Date(timeIntervalSince1970: 0), limit: 2)
        let actual: [TimeInterval] = next.map(\.timeIntervalSince1970)
        let expected: [TimeInterval] = [
            4.0 * 86_400.0 + 10.0 * 3_600.0,
            11.0 * 86_400.0 + 10.0 * 3_600.0
        ]
        XCTAssertEqual(actual, expected)
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

    private func weekly(_ start: String, zone: String = "America/New_York", weekdays: [Int] = [7]) -> JSON {
        var e = event("WEEKLY")
        e["zone"] = .string(zone); e["days"] = .null
        e["weekdays"] = .array(weekdays.map { .number(Double($0)) })
        e["start"] = .ms(ISO8601DateFormatter().date(from: start)!)
        return e
    }
    private func iso(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    func testWeeklySpringGapDoesNotShiftFollowingWeeks() {
        let e = weekly("2026-03-01T07:30:00Z")
        let actual: [Date] = eventDates(e, after: iso("2026-03-08T00:00:00Z"), limit: 2)
        let expected: [Date] = [iso("2026-03-08T07:30:00Z"), iso("2026-03-15T06:30:00Z")]
        XCTAssertEqual(actual, expected)
    }
    func testWeeklyFallOverlapUsesEarlierInstant() {
        let e = weekly("2026-10-25T05:30:00Z") // 01:30 in the saved zone.
        let actual: [Date] = eventDates(e, after: iso("2026-11-01T00:00:00Z"), limit: 2)
        let expected: [Date] = [iso("2026-11-01T05:30:00Z"), iso("2026-11-08T06:30:00Z")]
        XCTAssertEqual(actual, expected)
    }
    func testWeeklyFallDoesNotDeliverSecondFoldAfterFirstHasPassed() {
        let e = weekly("2026-10-25T05:30:00Z")
        let next = eventDates(e, after: iso("2026-11-01T06:00:00Z"), limit: 1)
        XCTAssertEqual(next.first, iso("2026-11-08T06:30:00Z"))
    }
    func testWeeklyNormalDateAndMidnightKeepTheirClock() {
        let e = weekly("2026-03-15T06:30:00Z") // 02:30 after the transition.
        XCTAssertEqual(eventDates(e, after: iso("2026-03-22T00:00:00Z"), limit: 1).first,
                       iso("2026-03-22T06:30:00Z"))
        let midnight = weekly("2026-03-16T00:00:00Z", zone: "UTC", weekdays: [1])
        XCTAssertEqual(eventDates(midnight, after: iso("2026-03-15T23:59:59Z"), limit: 1).first,
                       iso("2026-03-16T00:00:00Z"))
    }
    func testWeeklyUsesSavedZoneWhenDeviceZoneDiffers() {
        let previous = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "Asia/Tokyo")!
        defer { NSTimeZone.default = previous }
        let e = weekly("2026-03-01T07:30:00Z")
        XCTAssertEqual(eventDates(e, after: iso("2026-03-08T00:00:00Z"), limit: 1).first,
                       iso("2026-03-08T07:30:00Z"))
    }
    func testWeeklyHalfHourSpringGapAdvancesByActualGap() {
        let e = weekly("2026-09-26T15:45:00Z", zone: "Australia/Lord_Howe") // 02:15.
        XCTAssertEqual(eventDates(e, after: iso("2026-10-03T00:00:00Z"), limit: 1).first,
                       iso("2026-10-03T15:45:00Z")) // 02:45, not the first valid 02:30.
    }
    func testWeeklyHalfHourFallOverlapChoosesEarlierInstant() {
        let e = weekly("2026-03-28T14:45:00Z", zone: "Australia/Lord_Howe") // 01:45.
        XCTAssertEqual(eventDates(e, after: iso("2026-04-04T00:00:00Z"), limit: 1).first,
                       iso("2026-04-04T14:45:00Z"))
    }
    func testOtherRecurrencesRemainAbsoluteAcrossDST() {
        var e = weekly("2026-03-07T13:00:00Z", weekdays: [1,2,3,4,5,6,7])
        e["repeat"] = .string("INTERVAL"); e["hours"] = .number(24)
        let actual: [Date] = eventDates(e, after: iso("2026-03-07T13:00:00Z"), limit: 2)
        let expected: [Date] = [iso("2026-03-08T13:00:00Z"), iso("2026-03-09T13:00:00Z")]
        XCTAssertEqual(actual, expected)
        e["repeat"] = .string("ONCE")
        XCTAssertEqual(eventDates(e, after: iso("2026-03-07T12:59:59Z"), limit: 1).first,
                       iso("2026-03-07T13:00:00Z"))
        XCTAssertTrue(eventDates(e, after: iso("2026-03-07T13:00:00Z")).isEmpty)
    }
    func testWeeklyDurationEndsAtSavedZoneMidnightAcrossDST() {
        var e = weekly("2026-03-01T07:30:00Z")
        e["days"] = .number(7)
        XCTAssertTrue(eventDates(e, after: iso("2026-03-08T00:00:00Z")).isEmpty)
        e["days"] = .number(8)
        XCTAssertEqual(eventDates(e, after: iso("2026-03-08T00:00:00Z"), limit: 1).first,
                       iso("2026-03-08T07:30:00Z"))
    }
    func testWeeklyMatchesAndroidAtZoneReferenceCases() {
        // Expected instants follow Events.kt day.atTime(startTime).atZone(tz).
        // Tools/AndroidWeeklyOracle.java evaluates the same Java API without Android writes.
        let cases: [(zone: String, start: String, after: String, expected: String)] = [
            ("America/New_York", "2026-03-01T07:30:00Z", "2026-03-08T00:00:00Z", "2026-03-08T07:30:00Z"),
            ("America/New_York", "2026-10-25T05:30:00Z", "2026-11-01T00:00:00Z", "2026-11-01T05:30:00Z"),
            ("America/New_York", "2026-03-15T06:30:00Z", "2026-03-22T00:00:00Z", "2026-03-22T06:30:00Z"),
            ("Europe/Berlin", "2026-03-22T01:15:00Z", "2026-03-29T00:00:00Z", "2026-03-29T01:15:00Z"),
            ("Australia/Lord_Howe", "2026-09-26T15:45:00Z", "2026-10-03T00:00:00Z", "2026-10-03T15:45:00Z"),
            ("Australia/Lord_Howe", "2026-03-28T14:45:00Z", "2026-04-04T00:00:00Z", "2026-04-04T14:45:00Z")
        ]
        for c in cases {
            let e = weekly(c.start, zone: c.zone)
            let next = eventDates(e, after: iso(c.after), limit: 1)
            XCTAssertEqual(next.first, iso(c.expected), c.zone)
        }
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
