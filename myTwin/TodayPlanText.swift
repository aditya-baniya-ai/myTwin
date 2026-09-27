import Foundation

/// Puts today's forecast and the plan built from it into words, so both the on-device
/// model and Gemini can talk about them.
///
/// Everything here is worked out on the spot from the forecast, the calendar and bedtime.
/// Nothing new is measured, recorded or kept: a nap or a last coffee is something myTwin
/// is *suggesting*, never something it watched you do.
enum TodayPlanText {
    struct Inputs {
        let dayStart: Double            // the day's starting charge, 0-100
        let bedtime: Date
        let events: [PlanItem]
        let dismissed: Set<String>
        let trainedToday: Bool
        let easyDay: Bool
        var preferences: PlanningPreferences = .load()
    }

    static func summary(_ inputs: Inputs, now: Date = .now) -> String {
        let points = DayCharge.forecast(from: inputs.dayStart, now: now, until: inputs.bedtime)
        guard !points.isEmpty else { return "No forecast for today yet." }

        var lines: [String] = []

        let peak = points.max { $0.charge < $1.charge }
        let dip = points.min { $0.charge < $1.charge }
        if let peak {
            lines.append("Strongest around \(clock(peak.date)) at \(percent(peak.charge)).")
        }
        if let dip, let peak, dip.date != peak.date {
            lines.append("Lowest around \(clock(dip.date)) at \(percent(dip.charge)).")
        }
        lines.append("Bedtime is \(clock(inputs.bedtime)).")
        if inputs.trainedToday { lines.append("Already worked out today.") }
        if inputs.easyDay { lines.append("Running below their normal, so today should be an easy one.") }

        let plan = DayPlanner.plan(events: inputs.events, dayStart: inputs.dayStart, now: now,
                                   bedtime: inputs.bedtime, excluding: inputs.dismissed,
                                   trained: inputs.trainedToday, easyDay: inputs.easyDay, preferences: inputs.preferences)
        let suggestions = plan.filter { $0.kind == .suggestion }
        if suggestions.isEmpty {
            lines.append("No suggestions for the rest of today.")
        } else {
            lines.append("Suggested, not yet in their calendar — they have to accept each one:")
            for item in suggestions {
                let why = item.note.map { " — \($0)" } ?? ""
                lines.append("• \(item.title), \(clock(item.start)) to \(clock(item.end))\(why)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private static func percent(_ charge: Double) -> String {
        "\(Int((charge * 100).rounded()))% charged"
    }
}


/// Where the models get today's plan from. The screen owns the day's numbers, so it fills
/// this in; the tools only read it.
@MainActor
final class TodayPlanSource {
    var summary: () -> String = { "No forecast for today yet." }
    /// The last seven days as a few sentences; see WeekRecap.
    var weekRecap: () -> String = { "Not enough nights of sleep data yet to recap the week." }
}
