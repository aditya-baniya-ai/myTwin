import Foundation

/// Answers with Gemini while you're online. It sends what you typed or said, plays
/// Gemini's voice as it streams in, shows its words, and runs the same calendar and health
/// tools the on-device model uses. Nothing is saved to the calendar until you tap Confirm.
@MainActor
final class GeminiChat {
    /// No news from Gemini for this long means the connection is stuck: give up, so the
    /// iPhone can answer instead.
    private let stallLimit: TimeInterval = 12

    private let access: GeminiAccess
    private let voice: VoiceManager
    private let calendar: CalendarManager
    private let health: HealthManager

    private var live: GeminiLive?
    private var onWords: ((String) -> Void)?
    private var finished: CheckedContinuation<Bool, Never>?
    private var outcome: Bool?           // how the current answer ended, once it has
    private var heardSomething = false
    private var lastEvent = Date.now
    private var attempt = 0

    private let plan: TodayPlanSource

    init(access: GeminiAccess, voice: VoiceManager, calendar: CalendarManager,
         health: HealthManager, plan: TodayPlanSource) {
        self.access = access
        self.voice = voice
        self.calendar = calendar
        self.health = health
        self.plan = plan
    }

    /// Answers `text`, handing each piece of Gemini's words to `onWords` as it arrives.
    /// Returns false if Gemini couldn't be reached, so the iPhone can answer instead.
    func answer(_ text: String, onWords: @escaping (String) -> Void) async -> Bool {
        guard let key = access.apiKey else { return false }
        attempt += 1
        outcome = nil
        heardSomething = false
        lastEvent = .now
        self.onWords = onWords
        voice.startGeminiAnswer()

        do {
            let live = try await connection(key: key)
            try await live.ask(text)
        } catch {
            close()
            return false
        }
        watch(attempt)
        if let outcome { return outcome }
        return await withCheckedContinuation { finished = $0 }
    }

    func close() {
        live?.close()
        live = nil
    }

    // MARK: - Connection

    /// The open conversation, or a new one. One conversation carries on across messages.
    private func connection(key: String) async throws -> GeminiLive {
        if let live { return live }
        let live = GeminiLive(apiKey: key)
        try await live.open(instructions: Self.instructions(), tools: Self.tools)
        self.live = live
        Task { for await event in live.events { await handle(event, from: live) } }
        return live
    }

    private func handle(_ event: GeminiLive.Event, from source: GeminiLive) async {
        lastEvent = .now
        switch event {
        case .speech(let pcm):
            voice.play(geminiSpeech: pcm)
        case .words(let words):
            heardSomething = true
            voice.addGeminiWords(words)
            onWords?(words)
        case .toolCall(let id, let name, let arguments):
            heardSomething = true
            let result = await run(name, arguments)
            try? await source.reply(to: id, name: name, result: result)
        case .interrupted:
            // Gemini has stopped talking, so drop whatever is still queued rather than
            // letting the tail play over what the user is now saying.
            voice.stopSpeaking()
            finish(heardSomething)
        case .answerComplete:
            finish(true)
        case .closed:
            if live === source { live = nil }
            finish(heardSomething)               // a partial answer still counts
        }
    }

    private func finish(_ answered: Bool) {
        voice.endGeminiAnswer()
        outcome = answered
        finished?.resume(returning: answered)
        finished = nil
    }

    /// Closes the connection if Gemini goes quiet mid-answer, which ends the wait above.
    private func watch(_ mine: Int) {
        Task { [weak self] in
            while let self, attempt == mine, outcome == nil {
                if Date.now.timeIntervalSince(lastEvent) > stallLimit {
                    close()
                    finish(heardSomething)
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: - What Gemini knows and can do

    private static func instructions() -> String {
        """
        You are myTwin, a warm, upbeat assistant inside an app that tracks the user's energy. You help them plan their day around it.
        It is now \(Date.now.formatted(date: .complete, time: .shortened)) in \(TimeZone.current.identifier), the user's own time zone. Always answer in that time, never UTC.
        Use getTodayEvents for questions about today's schedule, and only mention events it returns.
        Use getWeekEvents for anything beyond today: tomorrow, a named weekday, the weekend, or the week ahead. Use it too when today is empty and the user asks what is coming up. Only mention events it returns.
        Use getHealthSummary for questions about sleep, heart rate, HRV, steps or energy, and only use numbers it returns.
        Use getTodayPlan for anything about energy later today, the best or worst time to do something, or what you have suggested: when to train, nap, or stop drinking coffee. Its suggestions are yours, not things the user has done or agreed to.
        To add, move or remove one of today's events, use addEvent, moveEvent or removeEvent. They don't save anything: the app shows the user a Confirm button. Tell the user to tap Confirm, and never say the change is done.
        You can only change today's events.
        Your answers are spoken aloud, so keep them to one to three short sentences, without lists or formatting.
        Give general wellness tips only, never medical advice.
        """
    }

    /// The same five tools as the on-device model, described the way Gemini expects.
    private static let tools: [[String: Any]] = [["functionDeclarations": [
        function("getTodayEvents", "Gets the user's calendar events for today, with start and end times."),
        function("getWeekEvents", "Gets the user's calendar for the next seven days, a day at a time, including today. Use for tomorrow, a named weekday, the weekend, or the week ahead."),
        function("getHealthSummary", "Gets the user's latest health numbers: sleep, HRV, resting heart rate, respiratory rate, steps and active energy."),
        function("getTodayPlan", "Gets today's predicted energy curve, its peak and dip, bedtime, and the activities myTwin suggests fitting into the day, such as a workout, a nap or the last coffee."),
        function("addEvent", "Suggests adding an event today. The user must tap Confirm before it is saved.", [
            "title": ("STRING", "Short event title, for example Gym"),
            "hour": ("INTEGER", "Start hour in 24-hour time, 0 to 23"),
            "minute": ("INTEGER", "Start minute, 0 to 59"),
            "durationMinutes": ("INTEGER", "Length in minutes. Use 60 if the user didn't say."),
        ]),
        function("moveEvent", "Suggests moving one of today's events to a new start time. The user must tap Confirm before it is saved.", [
            "title": ("STRING", "Title of the event to move"),
            "hour": ("INTEGER", "New start hour in 24-hour time, 0 to 23"),
            "minute": ("INTEGER", "New start minute, 0 to 59"),
        ]),
        function("removeEvent", "Suggests removing one of today's events. The user must tap Confirm before it is removed.", [
            "title": ("STRING", "Title of the event to remove"),
        ]),
    ]]]

    /// BLOCKING: Gemini waits for the result before it speaks. These tools answer in well under a second.
    private static func function(_ name: String, _ description: String,
                                 _ parameters: [String: (type: String, description: String)] = [:]) -> [String: Any] {
        var declaration: [String: Any] = ["name": name, "description": description, "behavior": "BLOCKING"]
        if !parameters.isEmpty {
            declaration["parameters"] = [
                "type": "OBJECT",
                "properties": parameters.mapValues { ["type": $0.type, "description": $0.description] },
                "required": Array(parameters.keys),
            ]
        }
        return declaration
    }

    private func run(_ name: String, _ arguments: [String: Any]) async -> String {
        let title = arguments["title"] as? String ?? ""
        func number(_ key: String, default fallback: Int = 0) -> Int {
            (arguments[key] as? NSNumber)?.intValue ?? fallback
        }
        switch name {
        case "getTodayEvents":
            return calendar.todayEventsText()
        case "getWeekEvents":
            return calendar.weekEventsText()
        case "getHealthSummary":
            return await health.summaryText()
        case "getTodayPlan":
            return plan.summary()
        case "addEvent":
            return calendar.proposeAdd(title: title, hour: number("hour"), minute: number("minute"),
                                       durationMinutes: number("durationMinutes", default: 60))
        case "moveEvent":
            return calendar.proposeMove(title: title, hour: number("hour"), minute: number("minute"))
        case "removeEvent":
            return calendar.proposeRemove(title: title)
        default:
            return "That tool doesn't exist."
        }
    }
}
