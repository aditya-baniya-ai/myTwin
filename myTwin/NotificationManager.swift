import Foundation
import UserNotifications

/// The day's nudges, scheduled on the phone. There is nothing to switch on: allow
/// notifications once and you get all of them, because they are the point of the app
/// rather than a settings menu. Each one says *why*, so it is worth following.
@MainActor
@Observable
final class NotificationManager {
    private let centre = UNUserNotificationCenter.current()
    private(set) var permissionDenied = false
    private(set) var bedtime = (hour: 23, minute: 0)
    /// The line the morning nudge carries, written from the latest reading.
    private(set) var brief = "Here's how today looks."


    /// Asks the first time, and answers from the stored decision afterwards: iOS only
    /// ever shows the question once.
    private func allowed() async -> Bool {
        let granted = (try? await centre.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        permissionDenied = !granted
        return granted
    }

    /// Rebuilds the whole schedule. Cheap, and avoids duplicates piling up.
    func reschedule(bedtime: (hour: Int, minute: Int), brief: String? = nil,
                    events: [(title: String, start: Date, note: String)] = []) async {
        self.bedtime = bedtime
        if let brief { self.brief = brief }
        centre.removeAllPendingNotificationRequests()
        guard await allowed() else { return }

        let wind = shift(bedtime, byMinutes: -45)
        let sleepHours = 8

        // Eight hours after your usual bedtime: roughly when you are up and deciding what
        // the day looks like.
        add(id: "morning", at: shift(bedtime, byMinutes: sleepHours * 60),
            title: "Good morning", body: self.brief)

        // Ten minutes ahead of each of today's events, with the energy you'll have.
        for (index, event) in events.enumerated() where event.start.timeIntervalSinceNow > 600 {
            add(id: "event\(index)", on: event.start.addingTimeInterval(-600),
                title: event.title, body: event.note)
        }

        add(id: "bedtime", at: wind,
            title: "Time to wind down",
            body: "Lights out around \(clock(bedtime)) gives you about \(sleepHours) hours. Deep sleep comes mostly in the first half of the night, so going to bed on time matters more than sleeping in.")

        // Caffeine's half-life is roughly 5 hours, so stop about 8 before bed.
        add(id: "caffeine", at: shift(bedtime, byMinutes: -8 * 60),
            title: "Last coffee of the day",
            body: "Caffeine halves roughly every 5 hours. A cup now still leaves about a quarter of it in you at \(clock(bedtime)), which costs you deep sleep even if you fall asleep fine.")

        add(id: "nap", at: (14, 0),
            title: "Your dip is coming",
            body: "Energy falls hardest between 2pm and 4pm. A 20 minute nap now, or a short walk outside, beats another coffee you will still feel tonight.")

        let water = [
            "Even mild dehydration shows up as tiredness before you feel thirsty.",
            "A glass now keeps the afternoon dip shallower.",
            "Last good moment to drink: too late and it wakes you up at night.",
        ]
        for (index, hour) in [10, 14, 17].enumerated() {
            add(id: "hydration\(hour)", at: (hour, 0), title: "Water break", body: water[index])
        }
    }

    /// A one-off nudge at a given moment, for things that happen once: today's events.
    private func add(id: String, on date: Date, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let when = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
        centre.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    private func add(id: String, at time: (hour: Int, minute: Int), title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        var when = DateComponents()
        when.hour = time.hour
        when.minute = time.minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
        centre.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    private func shift(_ time: (hour: Int, minute: Int), byMinutes minutes: Int) -> (hour: Int, minute: Int) {
        let total = (time.hour * 60 + time.minute + minutes + 24 * 60) % (24 * 60)
        return (total / 60, total % 60)
    }

    private func clock(_ time: (hour: Int, minute: Int)) -> String {
        var parts = DateComponents()
        parts.hour = time.hour
        parts.minute = time.minute
        let date = Calendar.current.date(from: parts) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// The bedtime the reminders are built around, for showing in the app.
    var bedtimeText: String { clock(bedtime) }
}
