import Foundation
import EventKit

/// A calendar change suggested by the chatbot. Nothing is saved until the user taps Confirm.
struct CalendarChange {
    enum Kind { case add, move, remove }

    let kind: Kind
    let event: EKEvent?  // nil means a new event
    let title: String
    let start: Date
    let end: Date

    var question: String {
        let time = timeRangeText(start, end)
        switch kind {
        case .add: return "Add \"\(title)\" at \(time)?"
        case .move: return "Move \"\(title)\" to \(time)?"
        case .remove: return "Remove \"\(title)\" at \(time)?"
        }
    }
}

@MainActor
@Observable
final class CalendarManager {
    private let store = EKEventStore()
    private let noAccessText = "Calendar access is not granted. The user can tap Connect Calendar on the home screen."

    var isAuthorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    var events: [EKEvent] = []
    /// The next seven days, today first, for the week view.
    var week: [EKEvent] = []
    var pendingChange: CalendarChange?
    var errorMessage: String?

    func requestAccess() async {
        do {
            isAuthorized = try await store.requestFullAccessToEvents()
            if isAuthorized {
                loadTodayEvents()
            } else {
                errorMessage = "Calendar access is off. Turn it on in Settings > Privacy > Calendars."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadTodayEvents() {
        guard isAuthorized else { return }
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    // MARK: - Chatbot tools

    /// Today's events as plain text, for the chatbot to read.
    /// Everything on the calendar between today and a week from now.
    func loadWeekEvents() {
        guard isAuthorized else { return }
        let days = Calendar.current
        let start = days.startOfDay(for: .now)
        guard let end = days.date(byAdding: .day, value: 7, to: start) else { return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        week = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    func todayEventsText() -> String {
        guard isAuthorized else { return noAccessText }
        loadTodayEvents()
        if events.isEmpty { return "No events today." }
        return events.map { "\($0.title ?? "Untitled"): \($0.timeText)" }.joined(separator: "\n")
    }

    /// Suggests a new event today. Returns a note for the chatbot.
    func proposeAdd(title: String, hour: Int, minute: Int, durationMinutes: Int) -> String {
        guard isAuthorized else { return noAccessText }
        guard let start = todayAt(hour: hour, minute: minute) else { return "That time isn't valid." }
        let end = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        return propose(CalendarChange(kind: .add, event: nil, title: title, start: start, end: end))
    }

    /// Suggests moving one of today's events to a new start time, keeping its length.
    func proposeMove(title: String, hour: Int, minute: Int) -> String {
        guard isAuthorized else { return noAccessText }
        guard let event = todayEvent(named: title) else { return notFoundText(title) }
        guard let start = todayAt(hour: hour, minute: minute) else { return "That time isn't valid." }
        let end = start.addingTimeInterval(event.endDate.timeIntervalSince(event.startDate))
        return propose(CalendarChange(kind: .move, event: event, title: event.title ?? "Untitled", start: start, end: end))
    }

    /// Suggests removing one of today's events.
    func proposeRemove(title: String) -> String {
        guard isAuthorized else { return noAccessText }
        guard let event = todayEvent(named: title) else { return notFoundText(title) }
        return propose(CalendarChange(kind: .remove, event: event, title: event.title ?? "Untitled",
                                      start: event.startDate, end: event.endDate))
    }

    /// Saves a suggestion you accepted straight to your default calendar: swiping it and
    /// tapping Add is the confirmation.
    func add(title: String, start: Date, end: Date) {
        guard isAuthorized else { errorMessage = noAccessText; return }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.calendar = store.defaultCalendarForNewEvents
        do {
            try store.save(event, span: .thisEvent)
            loadTodayEvents()
        } catch {
            errorMessage = "Couldn't add \"\(title)\": \(error.localizedDescription)"
        }
    }

    // MARK: - Confirming changes

    /// Saves the pending change to the calendar. Returns a message for the chat.
    func confirmPendingChange() -> String {
        guard let change = pendingChange else { return "There's nothing to confirm." }
        pendingChange = nil

        do {
            if change.kind == .remove {
                guard let event = change.event else { return "That event is no longer there." }
                try store.remove(event, span: .thisEvent)
                loadTodayEvents()
                return "Removed \"\(change.title)\" from your calendar."
            }

            let event = change.event ?? EKEvent(eventStore: store)
            if change.kind == .add {
                event.title = change.title
                event.calendar = store.defaultCalendarForNewEvents
            }
            event.startDate = change.start
            event.endDate = change.end
            try store.save(event, span: .thisEvent)  // for repeating events, only today's one changes
            loadTodayEvents()
            return "Done. \"\(change.title)\" is on your calendar at \(timeRangeText(change.start, change.end))."
        } catch {
            return "Sorry, I couldn't save that change. (\(error.localizedDescription))"
        }
    }

    private func propose(_ change: CalendarChange) -> String {
        pendingChange = change
        return "Not saved yet. The app is asking the user: \(change.question) Tell the user to tap Confirm to save it."
    }

    private func todayEvent(named title: String) -> EKEvent? {
        loadTodayEvents()
        if let match = events.first(where: { titleMatches($0.title ?? "", query: title) }) {
            return match
        }
        // People say "cancel my 3pm", so the title can be a time instead of a name.
        guard let hour = hour(in: title) else { return nil }
        return events.first { Calendar.current.component(.hour, from: $0.startDate) == hour }
    }

    private func notFoundText(_ title: String) -> String {
        "There is no event called \(title) today. Ask the user which event they mean."
    }

    private func todayAt(hour: Int, minute: Int) -> Date? {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now)
    }
}

extension EKEvent {
    /// "9:00 AM – 10:00 AM", or "All day".
    var timeText: String {
        isAllDay ? "All day" : timeRangeText(startDate, endDate)
    }
}

/// "9:00 AM – 10:00 AM"
func timeRangeText(_ start: Date, _ end: Date) -> String {
    "\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
}

/// Reads "3pm", "3 PM", "3 p.m." or "15:00" as an hour in 24-hour time.
/// Dictation writes "3 p.m." with dots, so the dots have to be allowed.
func hour(in text: String) -> Int? {
    let pattern = /(\d{1,2})\s*(?::\d{2})?\s*(?:([ap])\s*\.?\s*m\.?)?/
    guard let match = text.lowercased().firstMatch(of: pattern) else { return nil }
    guard var hour = Int(match.1) else { return nil }
    switch match.2.map(String.init) {
    case "p" where hour < 12: hour += 12
    case "a" where hour == 12: hour = 0
    default: break
    }
    return (0...23).contains(hour) ? hour : nil
}

/// Compares titles loosely, because dictation splits words: "stand up" must match "Team standup".
func titleMatches(_ eventTitle: String, query: String) -> Bool {
    let query = normalizedTitle(query)
    return !query.isEmpty && normalizedTitle(eventTitle).contains(query)
}

private func normalizedTitle(_ text: String) -> String {
    text.lowercased().filter { $0.isLetter || $0.isNumber }
}
