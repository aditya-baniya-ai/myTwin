import Foundation
import FoundationModels

struct ChatMessage: Identifiable {
    let id = UUID()
    let isUser: Bool
    let text: String
}

@MainActor
@Observable
final class ChatManager {
    var messages: [ChatMessage] = []
    var isResponding = false
    let calendar: CalendarManager

    private let session: LanguageModelSession

    init(calendar: CalendarManager) {
        self.calendar = calendar
        // Wording tested against Apple's safety filter: giving the assistant a name plus the date
        // got calendar questions blocked, and without the rules about saving the model claimed it
        // had changed events.
        session = LanguageModelSession(
            tools: [
                TodayEventsTool(calendar: calendar),
                AddEventTool(calendar: calendar),
                MoveEventTool(calendar: calendar),
            ],
            instructions: """
            Help the user plan their day.
            Use getTodayEvents to answer questions about today's schedule, and only mention events it returns.
            To add or move an event today, use addEvent or moveEvent. They don't save anything: the app shows the user a Confirm button. Tell the user to tap Confirm.
            You can only change today's events, and deleting isn't supported yet. If the user asks for that, suggest the Calendar app.
            Keep answers short and simple. When it helps, suggest one next step.
            """
        )
    }

    func send(_ text: String) async {
        messages.append(ChatMessage(isUser: true, text: text))
        calendar.pendingChange = nil  // a new message replaces any unconfirmed suggestion
        isResponding = true
        defer { isResponding = false }

        let reply: String
        do {
            reply = try await session.respond(to: text).content
        } catch LanguageModelSession.GenerationError.guardrailViolation {
            // The safety filter occasionally blocks normal requests. The session keeps working afterwards.
            reply = "Sorry, I can't answer that one. Try asking another way."
        } catch {
            reply = "Sorry, something went wrong. Please try again."
        }

        // When the model suggests a change, the app explains the next step itself:
        // in testing the model sometimes claimed the change was already saved.
        if calendar.pendingChange != nil {
            messages.append(ChatMessage(isUser: false, text: "Here's the change I suggest. Tap Confirm to save it."))
        } else {
            messages.append(ChatMessage(isUser: false, text: reply))
        }
    }

    func confirmChange() {
        messages.append(ChatMessage(isUser: false, text: calendar.confirmPendingChange()))
    }

    func cancelChange() {
        calendar.pendingChange = nil
        messages.append(ChatMessage(isUser: false, text: "Okay, I didn't change anything."))
    }
}

// MARK: - Tools the model can call

/// Reads today's calendar.
nonisolated struct TodayEventsTool: Tool {
    let name = "getTodayEvents"
    let description = "Gets the user's calendar events for today, with start and end times."
    let calendar: CalendarManager

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await calendar.todayEventsText()
    }
}

/// Suggests a new event today. Nothing is saved until the user taps Confirm.
nonisolated struct AddEventTool: Tool {
    let name = "addEvent"
    let description = "Suggests adding an event today. The user must tap Confirm before it is saved."
    let calendar: CalendarManager

    @Generable
    struct Arguments {
        @Guide(description: "Short event title, for example Gym")
        let title: String
        @Guide(description: "Start hour in 24-hour time", .range(0...23))
        let hour: Int
        @Guide(description: "Start minute", .range(0...59))
        let minute: Int
        @Guide(description: "Length in minutes. Use 60 if the user didn't say.", .range(5...720))
        let durationMinutes: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await calendar.proposeAdd(title: arguments.title, hour: arguments.hour,
                                  minute: arguments.minute, durationMinutes: arguments.durationMinutes)
    }
}

/// Suggests moving one of today's events. Nothing is saved until the user taps Confirm.
nonisolated struct MoveEventTool: Tool {
    let name = "moveEvent"
    let description = "Suggests moving one of today's events to a new start time. The user must tap Confirm before it is saved."
    let calendar: CalendarManager

    @Generable
    struct Arguments {
        @Guide(description: "Title of the event to move")
        let title: String
        @Guide(description: "New start hour in 24-hour time", .range(0...23))
        let hour: Int
        @Guide(description: "New start minute", .range(0...59))
        let minute: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await calendar.proposeMove(title: arguments.title, hour: arguments.hour, minute: arguments.minute)
    }
}
