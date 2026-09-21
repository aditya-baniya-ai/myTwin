import Foundation
import WidgetKit

/// Works out today's energy and hands it to everything that shows it, whether or not the
/// app is open: the Home Screen widget, the app icon, and the morning nudge.
///
/// HealthKit calls `run()` in the background as soon as your watch syncs the night's
/// sleep, so the twin is already right when you first look at your phone.
@MainActor
enum TwinRefresh {
    /// The whole job, from reading Health to rescheduling the nudges.
    static func run() async {
        let health = HealthManager()
        await health.refreshAuthorizationState()
        guard health.isAuthorized, let model = EnergyModel() else { return }

        let (history, _) = await health.history()
        let reading = model.reading(from: history, diary: EnergyDiary())
        let dayStart = model.dayStart(for: reading)
        share(dayStart: dayStart)

        let calendar = CalendarManager()
        calendar.loadTodayEvents()
        let trained = await !health.workoutsToday().isEmpty
        await schedule(reading: reading, dayStart: dayStart,
                       bedtime: health.typicalBedtime(from: history), calendar: calendar,
                       trained: trained, through: NotificationManager())
    }

    /// The twin the widget and the app icon show. One number, so all three agree.
    static func share(dayStart: Double) {
        TwinState.save(dayStart: dayStart)
        WidgetCenter.shared.reloadAllTimelines()
        TwinIcon.show(AvatarEnergyState(score: DayCharge.remaining(from: dayStart) * 100))
    }

    /// The morning line: what today looks like, and when to spend it. Written from the
    /// reading itself, so the nudge says something instead of just ringing.
    static func brief(for reading: EnergyReading?, dayStart: Double? = nil,
                      plan: [PlanItem] = []) -> String {
        guard let reading else {
            return "myTwin needs a few more nights of sleep data before it can call your day."
        }
        let start = dayStart ?? EnergyModel()?.dayStart(for: reading) ?? DayCharge.unknownDay
        let charge = Int(DayCharge.remaining(from: start, at: .now) * 100)
        let dip = dipHour(from: reading)
        let opening: String
        switch reading.band {
        case .above: opening = "Today looks better than your normal, starting at \(charge)%."
        case .normal: opening = "Today looks about normal for you, starting at \(charge)%."
        case .below: opening = "Today looks below your normal, starting at \(charge)%."
        }

        // One thing worth doing, taken from the plan the app is already showing.
        if let move = plan.first(where: { $0.kind == .suggestion }) {
            let at = move.start.formatted(date: .omitted, time: .shortened)
            return "\(opening) Your dip lands around \(dip). Best move: \(move.title.lowercased()) at \(at)."
        }
        let advice = reading.band == .below
            ? "Keep it light and protect your evening."
            : "Put the hard thing before your dip."
        return "\(opening) Your dip lands around \(dip). \(advice)"
    }

    /// When the drain curve bottoms out today, in plain clock terms.
    private static func dipHour(from reading: EnergyReading) -> String {
        let start = EnergyModel()?.dayStart(for: reading) ?? DayCharge.unknownDay
        let today = Calendar.current.startOfDay(for: .now)
        let waking = (9...21).map { hour in
            (hour: hour, charge: DayCharge.remaining(from: start, at: today.addingTimeInterval(Double(hour) * 3600)))
        }
        let low = waking.min { $0.charge < $1.charge } ?? (hour: 17, charge: 0)
        let at = Calendar.current.date(bySettingHour: low.hour, minute: 0, second: 0, of: today) ?? today
        return at.formatted(date: .omitted, time: .shortened)
    }
}

extension TwinRefresh {
    /// Rebuilds today's nudges from what is actually true right now: the morning line, a
    /// heads-up before each event with the energy you'll have, and the evening reminders.
    static func schedule(reading: EnergyReading?, dayStart: Double, bedtime: (hour: Int, minute: Int),
                         calendar: CalendarManager, trained: Bool,
                         through notifications: NotificationManager) async {
        let plan = DayPlanner.plan(events: DayPlanner.items(from: calendar.events), dayStart: dayStart,
                                   now: .now, bedtime: tonight(bedtime),
                                   excluding: DismissedSuggestions.today(),
                                   trained: trained, easyDay: reading?.band == .below)
        let events = plan.filter { $0.kind == .event }.map { event in
            (title: event.title, start: event.start, note: headsUp(at: event.start, dayStart: dayStart))
        }
        await notifications.reschedule(bedtime: bedtime,
                                       brief: brief(for: reading, dayStart: dayStart, plan: plan),
                                       events: events)
    }

    /// What you will have in the tank when something starts.
    private static func headsUp(at start: Date, dayStart: Double) -> String {
        let charge = Int(DayCharge.remaining(from: dayStart, at: start) * 100)
        let starts = start.formatted(date: .omitted, time: .shortened)
        switch charge {
        case 80...: return "Starts at \(starts). You'll be at \(charge)%, near your best."
        case 55..<80: return "Starts at \(starts). You'll be at \(charge)%."
        default: return "Starts at \(starts). You'll be at \(charge)%, so keep it light."
        }
    }

    private static func tonight(_ bedtime: (hour: Int, minute: Int)) -> Date {
        let at = Calendar.current.date(bySettingHour: bedtime.hour, minute: bedtime.minute,
                                       second: 0, of: .now) ?? .now
        return bedtime.hour < 12 ? at.addingTimeInterval(86_400) : at
    }
}
