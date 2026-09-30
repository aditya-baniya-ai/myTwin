import Foundation

/// Something Dash brings up on his own instead of waiting to be asked.
struct DashNudge: Equatable {
    enum Kind: String, CaseIterable {
        case lowEnergyEvent, dipSoon, suggestionSoon, stepWalk, sitting, weekRecap
    }

    let kind: Kind
    /// What he says.
    let line: String
    /// What "Tell me more" asks him, worded the way the user would.
    let question: String
}

/// Decides whether anything is worth interrupting for, and what.
///
/// The bar is deliberately high: something is about to happen, or has been going on a
/// while, and there is a small thing to do about it. Each kind comes up at most once a
/// day, never within 90 minutes of another, and never in quiet hours.
enum DashNudges {
    /// Everything the decision needs, read from the screen at one moment.
    struct Situation {
        let now: Date
        let dayStart: Double                 // the morning's charge, 0-1
        let forecast: [EnergyPoint]
        let events: [PlanItem]               // what's really on the calendar
        let suggestions: [PlanItem]          // what myTwin suggested
        let stepsLastTwoHours: Double?
        let hasWeekRecap: Bool
        /// What the step check said when it last booked a walk, while that walk is still ahead.
        var stepWalk: String? = nil
    }

    static let gapBetweenNudges: TimeInterval = 90 * 60

    /// The single most worthwhile thing to say now, or nil. Remembers what it picked.
    static func next(_ situation: Situation, quiet: Bool, log: inout Log) -> DashNudge? {
        guard !quiet, log.canNudge(at: situation.now) else { return nil }
        guard let nudge = candidates(situation).first(where: { !log.said($0.kind, near: situation.now) })
        else { return nil }
        log.record(nudge.kind, at: situation.now)
        return nudge
    }

    /// Every nudge that applies right now, most urgent first.
    static func candidates(_ s: Situation) -> [DashNudge] {
        let minutes = { (date: Date) in date.timeIntervalSince(s.now) / 60 }
        var found: [DashNudge] = []

        // An event is close and you'll be low for it.
        if let event = s.events.first(where: { (20...60).contains(minutes($0.start)) }) {
            let charge = DayCharge.remaining(from: s.dayStart, at: event.start)
            if charge < 0.45 {
                found.append(.init(kind: .lowEnergyEvent,
                    line: "\(event.title) at \(clock(event.start)) lands when you'll be around \(percent(charge)). Want a way to go in fresher?",
                    question: "\(event.title) is at \(clock(event.start)) and my energy will be low then. How can I get through it?"))
            }
        }

        // The day's low point is coming, and nothing is booked in the half hour before it.
        let current = DayCharge.remaining(from: s.dayStart, at: s.now)
        if let dip = s.forecast.filter({ $0.date > s.now }).min(by: { $0.charge < $1.charge }),
           (15...75).contains(minutes(dip.date)), dip.charge < current - 0.05 {
            let before = dip.date.addingTimeInterval(-30 * 60)
            if !s.events.contains(where: { $0.start < dip.date && $0.end > before }) {
                found.append(.init(kind: .dipSoon,
                    line: "Your energy dips around \(clock(dip.date)). A short walk or some water before then helps.",
                    question: "My energy dips around \(clock(dip.date)). What should I do before it?"))
            }
        }

        // Something myTwin suggested is about to start.
        if let item = s.suggestions.first(where: { (0...20).contains(minutes($0.start)) }) {
            let why = item.note.map { " \($0)" } ?? ""
            found.append(.init(kind: .suggestionSoon,
                line: "Coming up at \(clock(item.start)): \(item.title).\(why)",
                question: "Why do you suggest \(item.title) at \(clock(item.start))?"))
        }

        // Behind on steps, and a walk is already on the calendar for it.
        if let walk = s.stepWalk {
            found.append(.init(kind: .stepWalk, line: walk,
                question: "How can I close the gap on my steps today?"))
        }

        // Daytime, and barely a step in two hours. Watches like Garmin sync to Health only a
        // few times a day, so the recent count is often just the phone's: it says so.
        let hour = Calendar.current.component(.hour, from: s.now)
        if let steps = s.stepsLastTwoHours, steps < 250, (9...19).contains(hour) {
            found.append(.init(kind: .sitting,
                line: "Barely a step in the last two hours, by your phone's count. If you've been sitting, five minutes on your feet would help.",
                question: "I've been sitting for a while. What's a quick way to get moving?"))
        }

        // The week is over: Sunday evening, or Monday morning if Sunday was missed.
        let weekday = Calendar.current.component(.weekday, from: s.now)    // 1 is Sunday
        if s.hasWeekRecap, (weekday == 1 && hour >= 17) || (weekday == 2 && hour < 12) {
            found.append(.init(kind: .weekRecap,
                line: "Your week's done. Want it in a few sentences?",
                question: "How was my week?"))
        }
        return found
    }

    private static func clock(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
    private static func percent(_ charge: Double) -> String { "\(Int((charge * 100).rounded()))%" }

    // MARK: - Memory

    /// When each kind was last said, kept between launches so reopening the app doesn't
    /// repeat him.
    struct Log: Codable {
        private var last: [String: Date] = [:]
        private var any: Date?

        func canNudge(at now: Date) -> Bool {
            any.map { now.timeIntervalSince($0) >= DashNudges.gapBetweenNudges } ?? true
        }

        /// The week recap comes once a week; everything else once a day.
        func said(_ kind: DashNudge.Kind, near now: Date) -> Bool {
            guard let when = last[kind.rawValue] else { return false }
            if kind == .weekRecap { return now.timeIntervalSince(when) < 6 * 86_400 }
            return Calendar.current.isDate(when, inSameDayAs: now)
        }

        mutating func record(_ kind: DashNudge.Kind, at now: Date) {
            last[kind.rawValue] = now
            any = now
        }

        private static let key = "dash.nudges"
        static func load() -> Log {
            UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Log.self, from: $0) } ?? Log()
        }
        func save() {
            if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
        }
    }
}
