import Foundation
import FoundationModels

struct ChatMessage: Identifiable {
    let id = UUID()
    let isUser: Bool
    var text: String
    /// Gemini answered, and speaks for itself: the iPhone voice stays quiet.
    var byGemini = false
}

@MainActor
@Observable
final class ChatManager {
    var messages: [ChatMessage] = []
    var isResponding = false
    let calendar: CalendarManager
    let gemini: GeminiAccess

    private let session: LanguageModelSession
    private let geminiChat: GeminiChat

    init(calendar: CalendarManager, health: HealthManager, gemini: GeminiAccess, voice: VoiceManager) {
        self.calendar = calendar
        self.gemini = gemini
        geminiChat = GeminiChat(access: gemini, voice: voice, calendar: calendar, health: health)
        // Wording tested against Apple's safety filter: giving the assistant a name plus the date
        // got calendar questions blocked, and without the rules about saving the model claimed it
        // had changed events.
        session = LanguageModelSession(
            tools: [
                TodayEventsTool(calendar: calendar),
                AddEventTool(calendar: calendar),
                MoveEventTool(calendar: calendar),
                RemoveEventTool(calendar: calendar),
                HealthSummaryTool(health: health),
            ],
            instructions: """
            Help the user plan their day.
            Use getTodayEvents to answer questions about today's schedule, and only mention events it returns.
            Use getHealthSummary to answer questions about sleep, heart rate, HRV, steps or energy, and only use numbers it returns.
            To add, move or remove an event today, use addEvent, moveEvent or removeEvent. They don't save anything: the app shows the user a Confirm button. Tell the user to tap Confirm.
            You can only change today's events.
            Keep answers short and simple. When it helps, suggest one next step.
            """
        )
    }

    /// Gemini answers when you've allowed it and you're online; otherwise, or if it can't be
    /// reached, the model on the iPhone does.
    func send(_ text: String) async {
        messages.append(ChatMessage(isUser: true, text: text))
        calendar.pendingChange = nil  // a new message replaces any unconfirmed suggestion
        isResponding = true
        defer { isResponding = false }

        if gemini.isActive, await answerWithGemini(text) { return }

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

    /// Streams Gemini's words into one message as they arrive.
    private func answerWithGemini(_ text: String) async -> Bool {
        var index: Int?
        return await geminiChat.answer(text) { [weak self] words in
            guard let self else { return }
            if let index {
                messages[index].text += words
            } else {
                // Only the leading space goes: the trailing one separates the next piece.
                messages.append(ChatMessage(isUser: false, text: String(words.drop(while: \.isWhitespace)),
                                            byGemini: true))
                index = messages.count - 1
            }
        }
    }

    /// Drops the connection to Gemini, for example when the app goes to the background.
    func endGemini() {
        geminiChat.close()
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

/// Reads today's health numbers.
nonisolated struct HealthSummaryTool: Tool {
    let name = "getHealthSummary"
    let description = "Gets the user's latest health numbers: sleep, HRV, resting heart rate, respiratory rate, steps and active energy."
    let health: HealthManager

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await health.summaryText()
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

/// Suggests removing one of today's events. Nothing is removed until the user taps Confirm.
nonisolated struct RemoveEventTool: Tool {
    let name = "removeEvent"
    let description = "Suggests removing one of today's events. The user must tap Confirm before it is removed."
    let calendar: CalendarManager

    @Generable
    struct Arguments {
        @Guide(description: "Title of the event to remove")
        let title: String
    }

    func call(arguments: Arguments) async throws -> String {
        await calendar.proposeRemove(title: arguments.title)
    }
}
