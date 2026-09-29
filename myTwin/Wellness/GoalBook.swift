import Foundation

/// The goals you write for each day, kept on this iPhone: what you typed, the goals read
/// from it, and which you finished. The demo keeps its own in memory.
@MainActor @Observable
final class GoalBook {
    struct Day: Codable, Equatable {
        var text = ""
        var goals: [Goal] = []
        var planned = false

        /// Every goal ticked off or carried over, and at least one of them done.
        var finished: Bool { goals.contains(where: \.done) && goals.allSatisfy { $0.done || $0.moved } }
    }

    private(set) var days: [String: Day]
    let isDemo: Bool
    private let defaults: UserDefaults
    private static let key = "goals.days.v1"

    init(demo: Bool = false, defaults: UserDefaults = .standard) {
        isDemo = demo
        self.defaults = defaults
        if demo {
            days = [Self.name(SampleDay.now): Day(text: DemoData.todaysGoals, goals: GoalParser.parse(DemoData.todaysGoals))]
        } else {
            days = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([String: Day].self, from: $0) } ?? [:]
        }
    }

    static func name(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    func day(_ date: Date) -> Day { days[Self.name(date)] ?? Day() }

    /// Saves what you typed and reads the goals out of it, keeping what you'd already
    /// ticked or planned for any line that's still there.
    func write(_ text: String, for date: Date) {
        var day = day(date)
        guard day.text != text else { return }
        let before = Dictionary(day.goals.map { ($0.title.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        day.text = text
        day.goals = GoalParser.parse(text).map { goal in
            guard let old = before[goal.title.lowercased()] else { return goal }
            var kept = goal
            kept.id = old.id
            kept.done = old.done
            kept.moved = old.moved
            kept.scheduled = goal.minutes == old.minutes ? old.scheduled : nil
            return kept
        }
        day.planned = day.planned && day.goals.allSatisfy { $0.scheduled != nil }
        store(day, for: date)
    }

    func toggle(_ goal: Goal, on date: Date) {
        var day = day(date)
        guard let index = day.goals.firstIndex(where: { $0.id == goal.id }) else { return }
        day.goals[index].done.toggle()
        store(day, for: date)
    }

    /// Unfinished goals from `date` go onto the next day's list. Returns how many moved.
    @discardableResult
    func moveUnfinished(from date: Date) -> Int {
        guard let next = Calendar.current.date(byAdding: .day, value: 1, to: date) else { return 0 }
        var today = day(date)
        let left = today.goals.filter { !$0.done && !$0.moved }
        guard !left.isEmpty else { return 0 }
        let tomorrow = day(next)
        let existing = Set(tomorrow.goals.map { $0.title.lowercased() })
        let lines = left.filter { !existing.contains($0.title.lowercased()) }.map { line(for: $0) }
        let text = ([tomorrow.text.trimmingCharacters(in: .whitespacesAndNewlines)] + lines)
            .filter { !$0.isEmpty }.joined(separator: "\n")
        for index in today.goals.indices where left.contains(where: { $0.id == today.goals[index].id }) {
            today.goals[index].moved = true
        }
        store(today, for: date)
        write(text, for: next)
        return left.count
    }

    /// Where Plan my day put each goal.
    func schedule(_ times: [UUID: Date], on date: Date) {
        var day = day(date)
        for index in day.goals.indices { day.goals[index].scheduled = times[day.goals[index].id] }
        day.planned = true
        store(day, for: date)
    }

    /// One planned goal moved to a time you picked. The others stay where they are.
    func reschedule(_ goal: Goal, to start: Date, on date: Date) {
        var day = day(date)
        guard let index = day.goals.firstIndex(where: { $0.id == goal.id }) else { return }
        day.goals[index].scheduled = start
        store(day, for: date)
    }

    /// A goal you changed by hand: its name, length or time. The day's text is written
    /// again from its goals, because adding the next goal reads that text back, and would
    /// otherwise bring the old line back over your change.
    func edit(_ goal: Goal, on date: Date) {
        var day = day(date)
        guard let index = day.goals.firstIndex(where: { $0.id == goal.id }) else { return }
        day.goals[index] = goal
        day.text = day.goals.map { line(for: $0, keepingTime: true) }.joined(separator: "\n")
        store(day, for: date)
    }

    func delete(_ goal: Goal, on date: Date) {
        var day = day(date)
        day.goals.removeAll { $0.id == goal.id }
        day.text = day.goals.map { line(for: $0, keepingTime: true) }.joined(separator: "\n")
        store(day, for: date)
    }

    /// A goal written back as a line, keeping its length, and if asked its time or part of
    /// the day, so it's read the same way again.
    private func line(for goal: Goal, keepingTime: Bool = false) -> String {
        let length = goal.minutes % 60 == 0 ? "\(goal.minutes / 60) hr" : "\(goal.minutes) min"
        var parts = [goal.title, length]
        if keepingTime, let hour = goal.hour {
            let minute = (goal.minute ?? 0) > 0 ? String(format: ":%02d", goal.minute ?? 0) : ""
            parts.append("at \(hour % 12 == 0 ? 12 : hour % 12)\(minute)\(hour < 12 ? "am" : "pm")")
        } else if keepingTime, let window = goal.window {
            parts.append(window.rawValue)
        }
        return parts.joined(separator: ", ")
    }

    private func store(_ day: Day, for date: Date) {
        days[Self.name(date)] = day
        guard !isDemo else { return }
        // A week back is plenty for the nightly check.
        let cutoff = Self.name(Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now)
        days = days.filter { $0.key >= cutoff }
        if let data = try? JSONEncoder().encode(days) { defaults.set(data, forKey: Self.key) }
    }
}
