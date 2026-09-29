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
    private(set) var revision = 0

    /// The guest demo: a fictional week held in memory. Changes you confirm edit it, and
    /// nothing is read from or saved to your calendar.
    let isDemo: Bool
    private var demoEvents: [EKEvent] = []

    init(demo: Bool = false) {
        isDemo = demo
        if demo {
            isAuthorized = true
            demoEvents = DemoData.events(in: store)
            loadTodayEvents()
            loadWeekEvents()
        }
    }

    func requestAccess() async {
        guard !isDemo else { return }
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
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        if isDemo { events = demoEvents(from: start, to: end); return }
        isAuthorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        guard isAuthorized else { events = []; week = []; return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    private func demoEvents(from start: Date, to end: Date) -> [EKEvent] {
        demoEvents.filter { $0.startDate < end && $0.endDate > start }.sorted { $0.startDate < $1.startDate }
    }

    /// Saves to the calendar, or in the demo to the fictional week.
    private func save(_ event: EKEvent) throws {
        if isDemo {
            if !demoEvents.contains(where: { $0 === event }) { demoEvents.append(event) }
        } else {
            try store.save(event, span: .thisEvent)  // for repeating events, only today's one changes
        }
    }

    private func delete(_ event: EKEvent) throws {
        if isDemo { demoEvents.removeAll { $0 === event } } else { try store.remove(event, span: .thisEvent) }
    }

    // MARK: - Chatbot tools

    /// Today's events as plain text, for the chatbot to read.
    /// Everything on the calendar between today and a week from now.
    func loadWeekEvents() {
        guard isAuthorized else { return }
        let days = Calendar.current
        let start = days.startOfDay(for: .now)
        guard let end = days.date(byAdding: .day, value: 7, to: start) else { return }
        if isDemo { week = demoEvents(from: start, to: end); return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        week = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    func todayEventsText() -> String {
        guard isAuthorized else { return noAccessText }
        loadTodayEvents()
        if events.isEmpty { return "No events today." }
        return events.map { "\($0.title ?? "Untitled"): \($0.timeText)" }.joined(separator: "\n")
    }

    /// The next seven days as plain text, a day at a time, for the chatbot to read.
    /// Today is included, so a question like "am I free tomorrow" and one about Friday are
    /// answered from the same place.
    func weekEventsText() -> String {
        guard isAuthorized else { return noAccessText }
        loadWeekEvents()
        if week.isEmpty { return "Nothing on the calendar for the next seven days." }

        let days = Calendar.current
        let today = days.startOfDay(for: .now)
        let byDay = Dictionary(grouping: week) { days.startOfDay(for: $0.startDate) }

        var lines: [String] = []
        for ahead in 0..<7 {
            guard let date = days.date(byAdding: .day, value: ahead, to: today) else { continue }
            let name = switch ahead {
            case 0: "Today"
            case 1: "Tomorrow"
            default: date.formatted(.dateTime.weekday(.wide).month().day())
            }
            guard let onThatDay = byDay[date], !onThatDay.isEmpty else {
                lines.append("\(name): nothing")
                continue
            }
            let listed = onThatDay.map {
                $0.isAllDay ? "\($0.title ?? "Untitled") (all day)"
                            : "\($0.title ?? "Untitled") \($0.timeText)"
            }
            lines.append("\(name): " + listed.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    /// Suggests a new event today. Returns a note for the chatbot.
    func proposeAdd(title: String, hour: Int, minute: Int, durationMinutes: Int) -> String {
        guard isAuthorized else { return noAccessText }
        guard let start = todayAt(hour: hour, minute: minute) else { return "That time isn't valid." }
        guard (5...1440).contains(durationMinutes) else { return "Choose a duration from 5 minutes to 24 hours." }
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
        if !isDemo { event.calendar = store.defaultCalendarForNewEvents }
        do {
            try save(event)
            didMutate()
        } catch {
            errorMessage = "Couldn't add \"\(title)\": \(error.localizedDescription)"
        }
    }

    private func didMutate() {
        errorMessage = nil
        loadTodayEvents()
        loadWeekEvents()
        revision += 1
    }

    enum PlanningError: LocalizedError {
        case unavailable, changed, conflict, invalidTime
        var errorDescription: String? {
            switch self {
            case .unavailable: "Connect a writable calendar to save this plan."
            case .changed: "That activity changed in Calendar. Refresh the preview before trying again."
            case .conflict: "Your calendar changed and this time is no longer free. Make a new preview."
            case .invalidTime: "This time has passed or runs past bedtime. Make a new preview."
            }
        }
    }

    /// Only an event created by this installation and still matching the preview is mutable.
    func matches(_ action: PlannedAction) -> Bool {
        guard let id = action.eventID, let event = store.event(withIdentifier: id) else { return false }
        return event.url?.absoluteString == "mytwin://activity/\(action.id.uuidString)"
            && event.title == action.title && event.startDate == action.start && event.endDate == action.end
            && event.calendar.allowsContentModifications && !event.hasRecurrenceRules
    }

    func saveActivity(_ action: PlannedAction, replacing original: PlannedAction?, bedtime: Date) throws -> PlannedAction {
        loadTodayEvents()
        guard isAuthorized else { throw PlanningError.unavailable }
        guard action.end > action.start, action.start >= Date.now, action.end <= bedtime else { throw PlanningError.invalidTime }
        if let original, !matches(original) { throw PlanningError.changed }
        let predicate = store.predicateForEvents(withStart: action.start, end: action.end, calendars: nil)
        let busy = store.events(matching: predicate).filter { !$0.isAllDay && $0.eventIdentifier != original?.eventID }
        guard !busy.contains(where: { $0.startDate < action.end && $0.endDate > action.start }) else { throw PlanningError.conflict }
        let event: EKEvent
        if let id = original?.eventID, let existing = store.event(withIdentifier: id) { event = existing }
        else {
            guard let calendar = store.defaultCalendarForNewEvents, calendar.allowsContentModifications else { throw PlanningError.unavailable }
            event = EKEvent(eventStore: store)
            event.calendar = calendar
        }
        event.title = action.title
        event.startDate = action.start
        event.endDate = action.end
        event.url = URL(string: "mytwin://activity/\(action.id.uuidString)")
        try store.save(event, span: .thisEvent)
        var saved = action
        saved.eventID = event.eventIdentifier
        didMutate()
        return saved
    }

    func undoActivity(_ action: PlannedAction, restoring original: PlannedAction?) throws {
        guard matches(action), let id = action.eventID, let event = store.event(withIdentifier: id) else { throw PlanningError.changed }
        if let original {
            let predicate = store.predicateForEvents(withStart: original.start, end: original.end, calendars: nil)
            guard !store.events(matching: predicate).contains(where: {
                !$0.isAllDay && $0.eventIdentifier != id && $0.startDate < original.end && $0.endDate > original.start
            }) else { throw PlanningError.conflict }
            event.title = original.title
            event.startDate = original.start
            event.endDate = original.end
            event.url = URL(string: "mytwin://activity/\(original.id.uuidString)")
            try store.save(event, span: .thisEvent)
        } else { try store.remove(event, span: .thisEvent) }
        didMutate()
    }

    // MARK: - Walks for the step goal

    private static let walkURL = URL(string: "mytwin://walk")!

    /// A walk myTwin added that hasn't happened yet today, if there is one. Reads what's
    /// loaded, so a screen can ask while it draws.
    func upcomingWalk(after now: Date = .now) -> EKEvent? {
        events.first { $0.url == Self.walkURL && $0.startDate > now }
    }

    /// Adds a short walk. Returns whether it was saved.
    @discardableResult
    func addWalk(at start: Date, minutes: Int) -> Bool {
        guard isAuthorized else { return false }
        let event = EKEvent(eventStore: store)
        event.title = "Walk · \(minutes) min"
        event.notes = "Added by myTwin for your step goal. Turn it off in myTwin → Make it yours."
        event.url = Self.walkURL
        event.startDate = start
        event.endDate = start.addingTimeInterval(Double(minutes) * 60)
        if !isDemo {
            guard let calendar = store.defaultCalendarForNewEvents, calendar.allowsContentModifications else { return false }
            event.calendar = calendar
        }
        do { try save(event); didMutate(); return true } catch { return false }
    }

    // MARK: - Goals

    private static let goalPrefix = "mytwin://goal/"

    /// Events on `day` other than goals myTwin planned, which get replaced on a re-plan.
    func busy(on day: Date) -> [DateInterval] {
        loadWeekEvents()
        let days = Calendar.current
        return week.filter { !$0.isAllDay && days.isDate($0.startDate, inSameDayAs: day)
            && !($0.url?.absoluteString.hasPrefix(Self.goalPrefix) ?? false) }
            .map { DateInterval(start: $0.startDate, end: $0.endDate) }
    }

    /// Puts planned goals on the calendar with a reminder ten minutes before, replacing any
    /// goals planned for that day before. Returns how many were saved.
    @discardableResult
    func placeGoals(_ goals: [(goal: Goal, start: Date)], on day: Date) -> Int {
        guard isAuthorized else { return 0 }
        loadWeekEvents()
        let days = Calendar.current
        for old in week where days.isDate(old.startDate, inSameDayAs: day)
            && (old.url?.absoluteString.hasPrefix(Self.goalPrefix) ?? false) {
            try? delete(old)
        }
        var saved = 0
        for (goal, start) in goals {
            let event = EKEvent(eventStore: store)
            event.title = goal.title
            event.notes = "A goal you set in myTwin."
            event.url = URL(string: Self.goalPrefix + goal.id.uuidString)
            event.startDate = start
            event.endDate = start.addingTimeInterval(Double(goal.minutes) * 60)
            if !isDemo {
                guard let calendar = store.defaultCalendarForNewEvents, calendar.allowsContentModifications else { break }
                event.calendar = calendar
                event.addAlarm(EKAlarm(relativeOffset: -600))
            }
            if (try? save(event)) != nil { saved += 1 }
        }
        didMutate()
        return saved
    }

    /// Moves a planned goal's event to a time you picked, keeping its length. Its reminder
    /// moves with it. Returns false when the event is gone, say deleted in Calendar.
    @discardableResult
    func moveGoal(_ goal: Goal, to start: Date) -> Bool {
        guard isAuthorized else { return false }
        loadWeekEvents()
        guard let event = week.first(where: { $0.url?.absoluteString == Self.goalPrefix + goal.id.uuidString })
        else { return false }
        let length = event.endDate.timeIntervalSince(event.startDate)
        event.startDate = start
        event.endDate = start.addingTimeInterval(length)
        guard (try? save(event)) != nil else { return false }
        didMutate()
        return true
    }

    // MARK: - Bedtime

    private static let bedtimeKey = "calendar.bedtime.event"
    private static let bedtimeURL = URL(string: "mytwin://bedtime")!

    /// Keeps one repeating "Bedtime" event at your bedtime: added when it's missing, moved
    /// when your bedtime changes, removed when you turn it off. Nothing in the demo.
    func syncBedtime(on: Bool, hour: Int, minute: Int, defaults: UserDefaults = .standard) {
        guard !isDemo, isAuthorized else { return }
        let saved = defaults.string(forKey: Self.bedtimeKey)
            .flatMap { store.calendarItem(withIdentifier: $0) as? EKEvent }
            .flatMap { $0.url == Self.bedtimeURL ? $0 : nil }
        guard on else {
            if let saved { try? store.remove(saved, span: .futureEvents) }
            defaults.removeObject(forKey: Self.bedtimeKey)
            return
        }
        let days = Calendar.current
        guard let start = days.date(bySettingHour: hour, minute: minute, second: 0,
                                    of: days.startOfDay(for: .now)) else { return }
        if let saved, days.component(.hour, from: saved.startDate) == hour,
           days.component(.minute, from: saved.startDate) == minute { return }

        let event = saved ?? EKEvent(eventStore: store)
        if saved == nil {
            guard let calendar = store.defaultCalendarForNewEvents, calendar.allowsContentModifications else { return }
            event.calendar = calendar
            event.title = "Bedtime"
            event.notes = "Added by myTwin. Turn it off in myTwin → Make it yours."
            event.url = Self.bedtimeURL
        }
        event.startDate = start
        event.endDate = start.addingTimeInterval(15 * 60)
        // After the dates: a rule added to an event without them is quietly dropped.
        if !event.hasRecurrenceRules {
            event.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil))
        }
        do {
            try store.save(event, span: .futureEvents)
            defaults.set(event.calendarItemIdentifier, forKey: Self.bedtimeKey)
            didMutate()
        } catch {
            errorMessage = "Couldn't add Bedtime to your calendar: \(error.localizedDescription)"
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
                try delete(event)
                didMutate()
                return "Removed \"\(change.title)\" from your calendar."
            }

            let event = change.event ?? EKEvent(eventStore: store)
            if change.kind == .add {
                event.title = change.title
                if !isDemo { event.calendar = store.defaultCalendarForNewEvents }
            }
            event.startDate = change.start
            event.endDate = change.end
            try save(event)
            didMutate()
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
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now)
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
