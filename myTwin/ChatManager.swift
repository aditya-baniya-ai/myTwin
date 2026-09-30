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
    /// Gemini is part of Pro; without it Dash answers from the model on the iPhone.
    var proEnabled = false
    var rescueDay: ((Int?) -> Void)?
    let calendar: CalendarManager
    let gemini: GeminiAccess

    private let session: LanguageModelSession
    private let geminiChat: GeminiChat
    /// The chat's tools, shared with Dash's check-in conversations.
    private let tools: [any Tool]
    /// One per conversation with Dash, so it remembers what he asked and what you said.
    private let mentorChat: GeminiChat
    /// Filled in by ContentView, which knows the day's charge, bedtime and dismissals.
    let planSource = TodayPlanSource()

    init(calendar: CalendarManager, health: HealthManager, gemini: GeminiAccess, voice: VoiceManager) {
        self.calendar = calendar
        self.gemini = gemini
        let planSource = self.planSource
        geminiChat = GeminiChat(access: gemini, voice: voice, calendar: calendar, health: health,
                                plan: planSource)
        mentorChat = GeminiChat(access: gemini, voice: voice, calendar: calendar, health: health,
                                plan: planSource, mentor: true)
        // Wording tested against Apple's safety filter: giving the assistant a name plus the date
        // got calendar questions blocked, and without the rules about saving the model claimed it
        // had changed events. The name alone is fine, and without it the model invented one
        // ("Justin AI") when asked. Tested on the Mac: naming it changed no other answer.
        tools = [
                TodayEventsTool(calendar: calendar),
                WeekEventsTool(calendar: calendar),
                AddEventTool(calendar: calendar),
                MoveEventTool(calendar: calendar),
                RemoveEventTool(calendar: calendar),
                HealthSummaryTool(health: health),
                TodayPlanTool(plan: planSource),
                WeekRecapTool(plan: planSource),
                GoalsTool(plan: planSource),
            ]
        session = LanguageModelSession(
            tools: tools,
            instructions: """
            You are the user's own assistant in the myTwin app, and your name is myTwin.
            When the user asks your name, or who or what you are, reply exactly: I'm myTwin, your energy twin.
            Never begin any other answer with your name.
            Help the user plan their day.
            Use getTodayEvents to answer questions about today's schedule, and only mention events it returns.
            Use getWeekEvents for anything beyond today: tomorrow, a named weekday, the weekend, or the week ahead. Use it too when today is empty and the user asks what is coming up. Only mention events it returns.
            Use getHealthSummary to answer questions about sleep, heart rate, HRV, steps or energy, and only use numbers it returns.
            Use getTodayPlan for anything about energy later today, the best or worst time to do something, or what you have suggested: when to train, nap, or stop drinking coffee. Its suggestions are yours, not things the user has done or agreed to.
            Use getWeekRecap when the user asks how their week went, what their best or worst day was, or what pattern their sleep has been following. Retell it in your own words; keep its reasons, and never add a cause it didn't give.
            Use getGoals for the user's own goals for today and tomorrow: which are done, which are left, when each is planned, and their streak.
            To add, move or remove an event today, use addEvent, moveEvent or removeEvent. They don't save anything: the app shows the user a Confirm button. Tell the user to tap Confirm.
            You can only change today's events.
            Keep answers short and simple. When it helps, suggest one next step.
            When you give a health number or a time, add a short clause saying how it compares with their normal, using only what the tools returned. One sentence in total, never two.
            """
        )
    }

    /// Gemini answers when you've allowed it and you're online; otherwise, or if it can't be
    /// reached, the model on the iPhone does.
    func send(_ text: String, record: Bool = true) async {
        let record = record && !calendar.isDemo   // the demo never joins your own history
        if record { AskedQuestions.record(text) }
        messages.append(ChatMessage(isUser: true, text: text))
        calendar.pendingChange = nil  // a new message replaces any unconfirmed suggestion
        isResponding = true
        defer { isResponding = false }

        if let request = RescueIntent.parse(text), let rescueDay {
            rescueDay(request.minutes)
            messages.append(ChatMessage(isUser: false, text: proEnabled
                ? "Let's find a manageable option. Review the rescue preview and confirm before anything changes."
                : "Rescue my day is included with myTwin Pro. Upgrade to preview and confirm a rescue."))
            return
        }
        if proEnabled, gemini.isActive, await answerWithGemini(text) {
            if record, calendar.pendingChange == nil, let reply = messages.last, !reply.isUser {
                AskedQuestions.remember(answer: reply.text, for: text)
            }
            return
        }
        guard case .available = SystemLanguageModel.default.availability else {
            messages.append(ChatMessage(isUser: false, text: "On-device chat isn't available here. You can still check in on the Dash screen. Rescue my day is available with Pro."))
            return
        }

        let reply: String
        do {
            reply = try await session.respond(to: text).content
            // Kept for the "You often ask" card. Errors below aren't answers.
            if record, calendar.pendingChange == nil { AskedQuestions.remember(answer: reply, for: text) }
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

    // MARK: - Dash's check-ins

    var canMentor: Bool { proEnabled && gemini.isActive }

    func startMentor() {
        geminiChat.close()
        mentorChat.close()
    }

    func endMentor() {
        mentorChat.close()
        calendar.pendingChange = nil
    }

    /// Gemini supplies both the response and its voice. Never substitute local speech.
    func mentor(_ prompt: String, onWords: @escaping (String) -> Void) async -> Bool {
        guard canMentor else { return false }
        calendar.pendingChange = nil
        return await mentorChat.answer(prompt, onWords: onWords)
    }

    static let mentorInstructions = """
    You are Dash, the user's energy coach in the myTwin app, in a short spoken check-in with them.
    Coach them: help them decide what matters today and how to fit it around their energy. Ask one short question at a time.
    Before your first line, use the tools to look at their day: getTodayEvents, getGoals and getTodayPlan. Use getHealthSummary, getWeekEvents or getWeekRecap when they come up.
    Only mention events, goals and numbers the tools return.
    Whenever you mention an energy peak or dip, call it an estimate or say it might happen; never say it will happen. Give general wellness tips only, never medical advice.
    Everything you say is spoken aloud: at most two short sentences, then exactly one short question. No lists or formatting. Omit the question only when the user ends the conversation or needs to tap Confirm.
    To add, move or remove one of today's events, use addEvent, moveEvent or removeEvent. They only suggest it: the user taps Confirm. Until the user taps Confirm, describe a proposal as: I suggest the change. Tap Confirm to save it. Never say you scheduled, moved, added, removed, saved or completed an event before confirmation.
    """

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

/// Reads the next seven days of calendar events.
nonisolated struct WeekEventsTool: Tool {
    let name = "getWeekEvents"
    let description = "Gets the user's calendar for the next seven days, a day at a time, including today. Use for tomorrow, a named weekday, the weekend, or the week ahead."
    let calendar: CalendarManager

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await calendar.weekEventsText()
    }
}

/// Reads the last seven days as a short story: best day, hardest day, and why.
nonisolated struct WeekRecapTool: Tool {
    let name = "getWeekRecap"
    let description = "Recaps the user's last seven days: their best and hardest day, what about their sleep or resting heart rate explains each, and one pattern across the week."
    let plan: TodayPlanSource

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await plan.weekRecap()
    }
}

/// Reads the goals the user wrote for today and tomorrow.
nonisolated struct GoalsTool: Tool {
    let name = "getGoals"
    let description = "Gets the goals the user wrote for today and tomorrow, which are done or left, when each is planned, and their streak of days with every goal finished."
    let plan: TodayPlanSource

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await plan.goals()
    }
}

/// Reads today's forecast and the plan built from it.
nonisolated struct TodayPlanTool: Tool {
    let name = "getTodayPlan"
    let description = "Gets today's predicted energy curve, its peak and dip, bedtime, and the activities myTwin suggests fitting into the day, such as a workout, a nap or the last coffee."
    let plan: TodayPlanSource

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await plan.summary()
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
