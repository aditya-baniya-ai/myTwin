import Foundation

/// Whether today's steps will reach your goal, judged by how you usually walk for the rest
/// of the day. No model: your steps so far, plus what you typically add from this time on.
struct StepPace: Equatable {
    let steps: Double
    let goal: Double
    let projected: Double

    var onTrack: Bool { projected >= goal }
    var shortfall: Double { max(goal - projected, 0) }
    /// A brisk walk is about 100 steps a minute: five minutes for a small gap, ten otherwise.
    var walkMinutes: Int { shortfall > 500 ? 10 : 5 }

    /// `history` is recent days, 24 hourly step counts each. Days with almost no steps are
    /// left out: that's a watch left on the charger, not a quiet day.
    static func estimate(steps: Double, goal: Double, now: Date, history: [[Double]]) -> StepPace {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let passed = Double(calendar.component(.minute, from: now)) / 60
        let rests = history
            .filter { $0.count == 24 && $0.reduce(0, +) >= 500 }
            .map { day in day[(hour + 1)...].reduce(0, +) + day[hour] * (1 - passed) }
            .sorted()
        let usual = rests.isEmpty ? 0 : rests[rests.count / 2]      // the median day
        return StepPace(steps: steps, goal: goal, projected: steps + usual)
    }

    /// The first free start for a walk in the next 90 minutes, on a five-minute mark and
    /// clear of everything on the calendar, or nil if the next hour and a half is full.
    static func slot(minutes: Int, after now: Date, busy: [DateInterval], latest: Date) -> Date? {
        let step: TimeInterval = 5 * 60
        var start = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / step).rounded(.up) * step)
        if start.timeIntervalSince(now) < step { start += step }       // a moment to get going
        let end = min(now.addingTimeInterval(90 * 60), latest)
        while start.addingTimeInterval(Double(minutes) * 60) <= end {
            let walk = DateInterval(start: start, duration: Double(minutes) * 60)
            guard let clash = busy.filter({ $0.start < walk.end && $0.end > walk.start })
                .max(by: { $0.end < $1.end }) else { return start }
            start = Date(timeIntervalSinceReferenceDate: (clash.end.timeIntervalSinceReferenceDate / step).rounded(.up) * step)
        }
        return nil
    }

    /// What Dash says: where you are, where you're heading, and the walk.
    func message(walkAt start: Date?) -> String {
        let so = steps.formatted(.number.precision(.fractionLength(0)))
        let aim = goal.formatted(.number.precision(.fractionLength(0)))
        let heading = (projected / 100).rounded() * 100
        var text = "You're at \(so) of \(aim) steps. At your usual pace you'll end near \(heading.formatted(.number.precision(.fractionLength(0))))."
        if let start {
            text += " A \(walkMinutes)-minute walk at \(start.formatted(date: .omitted, time: .shortened)) is on your calendar."
        } else {
            text += " A \(walkMinutes)-minute walk when you're free would close the gap."
        }
        return text
    }
}
