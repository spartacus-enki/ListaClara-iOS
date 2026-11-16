import Foundation

public struct Reminder: Equatable {
    public var id: String
    public var at: Date
}
// Resolve the wall clock with Java LocalDateTime.atZone semantics. Do not use
// date(bySettingHour:): it can discard the preserving-components policy.
private func weeklyDate(on day: Date, clock: DateComponents, calendar: Calendar) -> Date? {
    guard let interval = calendar.dateInterval(of: .day, for: day) else { return nil }
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(secondsFromGMT: 0)!
    var wall = calendar.dateComponents([.year, .month, .day], from: day)
    wall.calendar = utc; wall.timeZone = utc.timeZone
    wall.hour = clock.hour; wall.minute = clock.minute; wall.second = 0
    guard let nominal = utc.date(from: wall) else { return nil }
    let zone = calendar.timeZone
    let offsets = Set([
        zone.secondsFromGMT(for: interval.start.addingTimeInterval(-1)),
        zone.secondsFromGMT(for: interval.start),
        zone.secondsFromGMT(for: interval.end.addingTimeInterval(-1))
    ])
    var exact: [Date] = []
    var gaps: [(date: Date, shift: Int)] = []
    for offset in offsets {
        let candidate = nominal.addingTimeInterval(-TimeInterval(offset))
        let shift = zone.secondsFromGMT(for: candidate) - offset
        if shift == 0 { exact.append(candidate) }
        else if shift > 0 { gaps.append((candidate, shift)) }
    }
    // An overlap has two exact instants: choose the earlier one. A gap has no
    // exact instant: use the pre-transition offset to advance by the actual gap,
    // including 30-minute transitions, rather than snapping to its first minute.
    if let first = exact.min() { return first }
    return gaps.min(by: { $0.shift < $1.shift })?.date
}
public func eventDates(_ event: JSON, after: Date, limit: Int = 12) -> [Date] {
    guard event["enabled"].bool, let zone = TimeZone(identifier: event["zone"].string) else { return [] }
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
    let start = Date(timeIntervalSince1970: event["start"].number / 1000)
    let days = event["days"] == .null ? nil : Int(event["days"].number)
    let mode = event["repeat"].string
    let end: Date? = days.flatMap {
        mode == "INTERVAL" ? start.addingTimeInterval(Double($0) * 86400) : calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: start))
    }
    func allowed(_ d: Date) -> Bool { d >= start && d > after && (end == nil || d < end!) }
    if mode == "ONCE" { return allowed(start) ? [start] : [] }
    if mode == "INTERVAL" {
        let step = event["hours"].number * 3600
        guard step >= 3600 else { return [] }
        let n = max(0, floor(after.timeIntervalSince(start) / step) + 1)
        return (0..<limit).map { start.addingTimeInterval((n + Double($0)) * step) }.filter(allowed)
    }
    guard mode == "WEEKLY" else { return [] }
    let clock = calendar.dateComponents([.hour, .minute], from: start)
    let selected = Set(event["weekdays"].array.map { Int($0.number) })
    var result: [Date] = []
    let first = calendar.startOfDay(for: max(start, after))
    // Match Java ZoneId behavior: shift a missing wall time forward by its DST gap;
    // choose the first occurrence of a repeated wall time.
    for offset in 0..<(max(limit, 1) * 7 + 7) {
        guard let day = calendar.date(byAdding: .day, value: offset, to: first) else { continue }
        let isoWeekday = (calendar.component(.weekday, from: day) + 5) % 7 + 1
        guard selected.contains(isoWeekday),
              let candidate = weeklyDate(on: day, clock: clock, calendar: calendar),
              allowed(candidate) else { continue }
        result.append(candidate)
        if result.count >= limit { break }
    }
    return result
}
public func reminderPlan(_ ledger: Ledger, now: Date = Date(), limit: Int = 60) -> [Reminder] {
    var result: [Reminder] = []
    for e in ledger.entries.values where e.local != .null {
        let record = e.record, data = e.local
        if record.kind == "list", data["reminderAt"] != .null {
            let at = Date(timeIntervalSince1970: data["reminderAt"].number / 1000)
            if at > now { result.append(Reminder(id: "list/" + record.id, at: at)) }
        }
        if record.kind == "event" {
            for date in eventDates(data, after: now, limit: limit) {
                let stamp = String(Int64((date.timeIntervalSince1970 * 1000).rounded()))
                let occurrence = ledger.entries["occurrence/" + record.id + "~" + stamp]?.local
                if let occurrence, occurrence["revision"] == data["revision"],
                   occurrence["status"].string != "PENDING" || occurrence["silenced"].bool { continue }
                result.append(Reminder(id: "event/" + record.id + "/" + stamp, at: date))
            }
        }
    }
    for task in ledger.tasks where task["status"].string == "PENDING" && task["dueAt"] != .null {
        let at = Date(timeIntervalSince1970: task["dueAt"].number / 1000)
        if at > now { result.append(Reminder(id: "task/" + task["id"].string, at: at)) }
    }
    return Array(result.sorted { $0.at == $1.at ? $0.id < $1.id : $0.at < $1.at }.prefix(limit))
}
