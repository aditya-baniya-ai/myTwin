import EventKit
import Foundation
import UserNotifications

/// Every couple of hours in the day: will your steps reach your goal? If not, a short walk
/// goes on your calendar and a notification says why. Runs whenever the app is open and
/// when Apple Health wakes it with new steps, so the timing is "about every two hours",
/// never exact.
@MainActor
enum StepCheck {
    static let gap: TimeInterval = 2 * 3600
    static let walksPerDay = 3

    /// When it last looked, and the walks it has added today. Kept in memory for the demo.
    struct Log: Codable, Equatable {
        var checked: Date?
        var walkDay: Date?
        var walks = 0

        static let key = "steps.check.log"
        static func load(_ defaults: UserDefaults = .standard) -> Log {
            defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Log.self, from: $0) } ?? Log()
        }
        func save(_ defaults: UserDefaults = .standard) {
            if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
        }
        func walks(on day: Date) -> Int {
            walkDay.map { Calendar.current.isDate($0, inSameDayAs: day) } == true ? walks : 0
        }
    }

    enum Outcome: Equatable { case onTrack(StepPace), walk(StepPace, Date?) }

    /// Nil when it's not time to look: no goal, turned off, night-time, or looked recently.
    static func run(health: HealthManager, calendar: CalendarManager, preferences: PlanningPreferences,
                    now: Date = .now, log: inout Log, notify: Bool = true) async -> Outcome? {
        guard preferences.addsStepWalks, let goal = preferences.stepGoal, goal > 0,
              !preferences.isQuiet(now),
              now < preferences.bedtime(on: now).addingTimeInterval(-3600) else { return nil }
        if let checked = log.checked, now.timeIntervalSince(checked) < gap { return nil }

        let steps = health.isDemo ? (health.snapshot.steps ?? 0)
            : await health.steps(since: Calendar.current.startOfDay(for: now)) ?? 0
        let pace = StepPace.estimate(steps: steps, goal: goal, now: now, history: await health.hourlySteps())
        log.checked = now
        guard !pace.onTrack else { return .onTrack(pace) }

        // One walk waiting at a time, and a few a day at most.
        var start: Date?
        calendar.loadTodayEvents()
        if calendar.upcomingWalk(after: now) == nil, log.walks(on: now) < walksPerDay {
            let busy = calendar.events.filter { !$0.isAllDay }.map { DateInterval(start: $0.startDate, end: $0.endDate) }
            if let slot = StepPace.slot(minutes: pace.walkMinutes, after: now, busy: busy,
                                        latest: preferences.bedtime(on: now).addingTimeInterval(-3600)),
               calendar.addWalk(at: slot, minutes: pace.walkMinutes) {
                start = slot
                log.walks = log.walks(on: now) + 1
                log.walkDay = now
            }
        }
        if notify { await send(pace.message(walkAt: start)) }
        return .walk(pace, start)
    }

    /// Straight away, and under its own name so the day's other reminders never clear it.
    private static func send(_ body: String) async {
        let centre = UNUserNotificationCenter.current()
        let status = await centre.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "A short walk for your step goal"
        content.body = body
        content.sound = .default
        try? await centre.add(UNNotificationRequest(identifier: "steps.walk", content: content, trigger: nil))
    }
}
