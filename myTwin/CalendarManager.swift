import Foundation
import EventKit

/// A calendar change suggested by the chatbot. Nothing is saved until the user taps Confirm.
struct CalendarChange {
    let event: EKEvent?  // nil means a new event
    let title: String
    let start: Date
    let end: Date

    var question: String {
        let time = timeRangeText(start, end)
        return event == nil ? "Add \"\(title)\" at \(time)?" : "Move \"\(title)\" to \(time)?"
    }
}

@MainActor
@Observable
final class CalendarManager {
    private let store = EKEventStore()
    private let noAccessText = "Calendar access is not granted. The user can tap Connect Calendar on the home screen."

    var isAuthorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    var events: [EKEvent] = []
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
        return propose(CalendarChange(event: nil, title: title, start: start, end: end))
    }

    /// Suggests moving one of today's events to a new start time, keeping its length.
    func proposeMove(title: String, hour: Int, minute: Int) -> String {
        guard isAuthorized else { return noAccessText }
        loadTodayEvents()
        guard let event = events.first(where: { ($0.title ?? "").localizedCaseInsensitiveContains(title) }) else {
            return "There is no event called \(title) today. Ask the user which event they mean."
        }
        guard let start = todayAt(hour: hour, minute: minute) else { return "That time isn't valid." }
        let end = start.addingTimeInterval(event.endDate.timeIntervalSince(event.startDate))
        return propose(CalendarChange(event: event, title: event.title ?? "Untitled", start: start, end: end))
    }

    // MARK: - Confirming changes

    /// Saves the pending change to the calendar. Returns a message for the chat.
    func confirmPendingChange() -> String {
        guard let change = pendingChange else { return "There's nothing to confirm." }
        pendingChange = nil

        let event = change.event ?? EKEvent(eventStore: store)
        if change.event == nil {
            event.title = change.title
            event.calendar = store.defaultCalendarForNewEvents
        }
        event.startDate = change.start
        event.endDate = change.end

        do {
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
