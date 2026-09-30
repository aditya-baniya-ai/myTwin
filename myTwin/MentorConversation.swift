import Foundation

@MainActor
protocol MentorChatService: AnyObject {
    var canMentor: Bool { get }
    func startMentor()
    func endMentor()
    func mentor(_ prompt: String, onWords: @escaping (String) -> Void) async -> Bool
}
extension ChatManager: MentorChatService {}

@MainActor
protocol MentorVoiceService: AnyObject {
    var isDictating: Bool { get }
    func cancelDictation()
    func finishDictation()
    func stopSpeaking()
    func waitUntilQuiet() async
    func listenForReply(pause: TimeInterval, giveUp: TimeInterval,
                        target: @escaping (String) -> Void, onSilence: @escaping () -> Void) -> Bool
}
extension VoiceManager: MentorVoiceService {}

/// A spoken check-in that Dash starts himself (Pro). He opens with a line about your day and
/// a question; when he stops talking the microphone opens by itself; you answer, by voice or
/// by typing; he replies with a follow-up question, and so on until you end it, say you're
/// done, or stay quiet for half a minute.
@MainActor @Observable
final class MentorConversation {
    enum State: Equatable {
        case thinking       // waiting for his next line
        case speaking
        case listening      // the microphone is open for your answer
        case typing         // no microphone: answer in the box
    }

    private(set) var isActive = false
    private(set) var state: State = .thinking
    /// What Dash said last.
    private(set) var line = ""

    private let chat: any MentorChatService
    private let voice: any MentorVoiceService
    /// Bumped by every new turn and by the end, so an answer that arrives late is dropped.
    private var turn = 0
    private(set) var isRequesting = false
    private var task: Task<Void, Never>?

    init(chat: any MentorChatService, voice: any MentorVoiceService) {
        self.chat = chat
        self.voice = voice
    }

    func start(topic: String) {
        guard !isActive, chat.canMentor else { return }
        isActive = true
        chat.startMentor()
        request("Start a short check-in about their day. What prompted it: \(topic)")
    }

    func answer(_ text: String) {
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isActive, !isRequesting, !said.isEmpty else { return }
        voice.cancelDictation()
        voice.stopSpeaking()
        request(Self.isGoodbye(said)
                ? "The user ended the check-in: \(said). Say a brief goodbye without a question."
                : said, ending: Self.isGoodbye(said))
    }

    func listenNow() {
        guard isActive, !isRequesting else { return }
        if voice.isDictating { voice.finishDictation(); return }
        task?.cancel()
        turn += 1
        voice.stopSpeaking()
        listen()
    }

    /// Typing must not race the microphone's automatic send or silence timeout.
    func beginTyping() {
        guard isActive, !isRequesting else { return }
        task?.cancel()
        turn += 1
        voice.cancelDictation()
        voice.stopSpeaking()
        state = .typing
    }

    func end() {
        guard isActive else { return }
        turn += 1
        task?.cancel()
        task = nil
        isActive = false
        isRequesting = false
        voice.cancelDictation()
        chat.endMentor()
        voice.stopSpeaking()
    }

    private func request(_ prompt: String, ending: Bool = false) {
        task?.cancel()
        turn += 1
        let mine = turn
        isRequesting = true
        state = .thinking
        line = ""
        task = Task { [self] in
            let success = await chat.mentor(prompt) { [weak self] words in
                guard let self, isActive, mine == turn else { return }
                line += words
                state = .speaking
            }
            guard !Task.isCancelled, isActive, mine == turn else { return }
            isRequesting = false
            guard success else {
                voice.stopSpeaking()
                line = "Gemini is unavailable right now. Check your connection and try again, or tap End."
                state = .typing
                return
            }
            await voice.waitUntilQuiet()
            guard !Task.isCancelled, isActive, mine == turn else { return }
            if ending { end() } else { listen() }
        }
    }

    private func listen() {
        let open = voice.listenForReply(pause: 3, giveUp: 30,
                                        target: { [weak self] said in self?.answer(said) },
                                        onSilence: { [weak self] in self?.end() })
        state = open ? .listening : .typing
    }

    /// "Thanks, that's all", "bye", "I'm done": the end of the conversation, not an answer.
    /// Kept narrow, so "stop drinking coffee when?" or "just the email, that's all" still
    /// count as answers.
    nonisolated static func isGoodbye(_ text: String) -> Bool {
        let said = text.lowercased().replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
            .replacing(/[,.!]/, with: "")
        let exact: Set = ["stop", "end", "bye", "goodbye", "good bye", "that's all", "thats all", "that's it",
                          "i'm done", "im done", "nothing else", "no thanks", "no thank you", "we're done",
                          "all done", "thanks", "thank you", "thanks dash", "thank you dash", "bye dash"]
        if exact.contains(said) { return true }
        if said.hasSuffix(" bye") || said.hasSuffix(" goodbye") { return true }
        let polite = ["thanks", "thank you", "okay", "ok", "cool", "great", "perfect", "got it"]
        let done = ["that's all", "thats all", "that's it", "i'm done", "im done", "nothing else", "we're done"]
        return polite.contains { said.hasPrefix($0) } && done.contains { said.contains($0) }
    }
}
