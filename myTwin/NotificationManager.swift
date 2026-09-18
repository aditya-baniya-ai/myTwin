import Foundation
import UserNotifications

/// Daily nudges, scheduled on the phone. Each one says *why*, because a reminder you
/// understand is one you might actually follow.
@MainActor
@Observable
final class NotificationManager {
    enum Kind: String, CaseIterable, Identifiable {
        case bedtime, caffeine, hydration, nap
        var id: String { rawValue }

        var title: String {
            switch self {
            case .bedtime: "Bedtime"
            case .caffeine: "Last coffee"
            case .hydration: "Water breaks"
            case .nap: "Afternoon dip"
            }
        }

        var explanation: String {
            switch self {
            case .bedtime: "A wind-down nudge before your usual bedtime"
            case .caffeine: "So caffeine has cleared before you sleep"
            case .hydration: "Three reminders through the day"
            case .nap: "When your energy drops hardest"
            }
        }
    }

    private let centre = UNUserNotificationCenter.current()
    private static let enabledKey = "reminderKinds"

    var enabled: Set<String> {
        didSet { UserDefaults.standard.set(Array(enabled), forKey: Self.enabledKey) }
    }
    private(set) var permissionDenied = false
    private(set) var bedtime = (hour: 23, minute: 0)

    init() {
        enabled = Set(UserDefaults.standard.stringArray(forKey: Self.enabledKey) ?? [])
    }

    func isOn(_ kind: Kind) -> Bool { enabled.contains(kind.rawValue) }

    func toggle(_ kind: Kind) async {
        if enabled.contains(kind.rawValue) {
            enabled.remove(kind.rawValue)
        } else {
            guard await requestPermission() else { permissionDenied = true; return }
            enabled.insert(kind.rawValue)
        }
        await reschedule(bedtime: bedtime)
    }

    private func requestPermission() async -> Bool {
        (try? await centre.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Rebuilds the whole schedule. Cheap, and avoids duplicates piling up.
    func reschedule(bedtime: (hour: Int, minute: Int)) async {
        self.bedtime = bedtime
        centre.removeAllPendingNotificationRequests()
        guard !enabled.isEmpty else { return }

        let wind = shift(bedtime, byMinutes: -45)
        let sleepHours = 8

        if isOn(.bedtime) {
            add(id: "bedtime", at: wind,
                title: "Time to wind down",
                body: "Lights out around \(clock(bedtime)) gives you about \(sleepHours) hours. Deep sleep comes mostly in the first half of the night, so going to bed on time matters more than sleeping in.")
        }
        if isOn(.caffeine) {
            // Caffeine's half-life is roughly 5 hours, so stop about 8 before bed.
            add(id: "caffeine", at: shift(bedtime, byMinutes: -8 * 60),
                title: "Last coffee of the day",
                body: "Caffeine halves roughly every 5 hours. A cup now still leaves about a quarter of it in you at \(clock(bedtime)), which costs you deep sleep even if you fall asleep fine.")
        }
        if isOn(.nap) {
            add(id: "nap", at: (14, 0),
                title: "Your dip is coming",
                body: "Energy falls hardest between 2pm and 4pm. A 20 minute nap now, or a short walk outside, beats another coffee you will still feel tonight.")
        }
        if isOn(.hydration) {
            let bodies = [
                "Even mild dehydration shows up as tiredness before you feel thirsty.",
                "A glass now keeps the afternoon dip shallower.",
                "Last good moment to drink: too late and it wakes you up at night.",
            ]
            for (index, hour) in [10, 14, 17].enumerated() {
                add(id: "hydration\(hour)", at: (hour, 0), title: "Water break", body: bodies[index])
            }
        }
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
