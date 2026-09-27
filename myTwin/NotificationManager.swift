import Foundation
import UserNotifications

@MainActor @Observable
final class NotificationManager {
    private let centre = UNUserNotificationCenter.current()
    private var generation = 0
    private(set) var permissionDenied = false
    private(set) var bedtime = (hour: 23, minute: 0)
    private(set) var brief = "Open myTwin for a fresh check-in."

    func requestPermission() async {
        permissionDenied = !((try? await centre.requestAuthorization(options: [.alert, .sound])) ?? false)
    }

    /// Forecast wording only applies to today. Tomorrow's reminder asks for a fresh check-in.
    /// One-shot requests never repeat yesterday's health information indefinitely.
    func reschedule(bedtime: (hour: Int, minute: Int), brief: String? = nil,
                    events: [(title: String, start: Date, note: String)] = []) async {
        generation += 1
        let mine = generation
        self.bedtime = bedtime
        if let brief { self.brief = brief }
        let existing = await centre.pendingNotificationRequests()
        guard mine == generation else { return }
        let legacy = Set(["morning", "bedtime", "caffeine", "nap", "hydration10", "hydration14", "hydration17"])
        centre.removePendingNotificationRequests(withIdentifiers: existing.filter {
            $0.identifier.hasPrefix("mytwin.") || $0.identifier.hasPrefix("event") || legacy.contains($0.identifier)
        }.map(\.identifier))
        let settings = await centre.notificationSettings()
        guard mine == generation else { return }
        permissionDenied = settings.authorizationStatus == .denied
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let preferences = PlanningPreferences.load()
        let now = Date.now
        let calendar = Calendar.current
        var requests: [UNNotificationRequest] = []
        func append(_ id: String, _ date: Date, _ title: String, _ body: String) {
            guard date > now, !preferences.isQuiet(date), requests.count < 60 else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            requests.append(UNNotificationRequest(identifier: "mytwin." + id, content: content,
                            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
        }
        if preferences.morningReminder {
            let morningHour = (bedtime.hour + 8) % 24
            if let morning = calendar.date(bySettingHour: morningHour, minute: bedtime.minute, second: 0, of: now) {
                if morning > now { append("morning", morning, "A moment for your day", self.brief) }
                else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: morning) {
                    append("morning", tomorrow, "How are you feeling today?", "Open myTwin for a fresh check-in and today's plan.")
                }
            }
        }
        if preferences.eventReminders {
            for (index, event) in events.sorted(by: { $0.start < $1.start }).enumerated() {
                append("event.\(index)", event.start.addingTimeInterval(-600), event.title, event.note)
            }
        }
        if preferences.bedtimeReminder {
            append("bedtime", preferences.bedtime(on: now).addingTimeInterval(-45 * 60),
                   "Time to wind down", "Your chosen bedtime is \(bedtimeText). Take a moment to wind down if you can.")
        }
        for request in requests {
            guard mine == generation else { return }
            try? await centre.add(request)
        }
    }
    var bedtimeText: String {
        let date = Calendar.current.date(bySettingHour: bedtime.hour, minute: bedtime.minute, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}
