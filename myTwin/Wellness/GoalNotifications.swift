import Foundation
import UserNotifications

/// The two goal notifications: the morning list of a planned day (Pro), and the evening
/// "did you finish?" (everyone). Named by day, so the app's other reminders never clear them.
enum GoalNotifications {
    /// Asks on the evening of `day` whether its goals got done, half an hour before quiet
    /// hours begin, or at 8:30 PM.
    static func nightly(for day: Date, count: Int, preferences: PlanningPreferences) async {
        let id = "goals.night." + GoalBook.name(day)
        let centre = UNUserNotificationCenter.current()
        centre.removePendingNotificationRequests(withIdentifiers: [id])
        guard count > 0 else { return }
        let quiet = (17...23).contains(preferences.quietStart) ? preferences.quietStart : 21
        guard let at = Calendar.current.date(bySettingHour: quiet - 1, minute: 30, second: 0, of: day), at > .now else { return }
        await add(id: id, at: at, title: "Did you finish today's goals?",
                  body: "Tick off what you did. Anything left can move to tomorrow.")
    }

    /// The planned day's goals and times, when your day starts.
    static func morning(for day: Date, goals: [(goal: Goal, start: Date)], wake: Int) async {
        let id = "goals.morning." + GoalBook.name(day)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        guard !goals.isEmpty,
              let at = Calendar.current.date(bySettingHour: max(wake, 6), minute: 0, second: 0, of: day), at > .now else { return }
        let list = goals.sorted { $0.start < $1.start }.prefix(4)
            .map { "\($0.goal.title) at \($0.start.formatted(date: .omitted, time: .shortened))" }
            .joined(separator: ", ")
        await add(id: id, at: at, title: "Today's goals", body: list)
    }

    private static func add(id: String, at date: Date, title: String, body: String) async {
        let centre = UNUserNotificationCenter.current()
        let status = await centre.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        try? await centre.add(UNNotificationRequest(identifier: id, content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
    }
}
