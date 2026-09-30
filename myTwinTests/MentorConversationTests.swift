import XCTest
@testable import myTwin

final class MentorConversationTests: XCTestCase {
    func testGoodbyesEndTheCheckIn() {
        for said in ["Bye", "thanks", "Thank you, Dash.", "That's all", "that’s it!", "I'm done",
                     "okay bye", "Thanks, that's all", "cool, I'm done for now", "no thanks"] {
            XCTAssertTrue(MentorConversation.isGoodbye(said), said)
        }
    }

    /// Answers that happen to contain a goodbye word are still answers.
    func testAnswersAreNotGoodbyes() {
        for said in ["Stop drinking coffee when?", "just the email, that's all", "thanks to the gym I'm tired",
                     "The end of the report", "Finishing the lit review", "I'm done with the email, what next?"] {
            XCTAssertFalse(MentorConversation.isGoodbye(said), said)
        }
    }
}

@MainActor
private final class MentorChatStub: MentorChatService {
    var canMentor = true
    var prompts: [String] = []
    var stopped = 0
    var pending: CheckedContinuation<Bool, Never>?
    var words: ((String) -> Void)?
    func startMentor() {}
    func endMentor() { stopped += 1 }
    func mentor(_ prompt: String, onWords: @escaping (String) -> Void) async -> Bool {
        prompts.append(prompt)
        words = onWords
        return await withCheckedContinuation { pending = $0 }
    }
    func complete(_ success: Bool = true) {
        pending?.resume(returning: success)
        pending = nil
    }
}

@MainActor
private final class MentorVoiceStub: MentorVoiceService {
    var isDictating = false
    var microphoneAvailable = true
    var opens = 0
    var stops = 0
    var pause: TimeInterval = 0
    var giveUp: TimeInterval = 0
    var target: ((String) -> Void)?
    var silence: (() -> Void)?
    func cancelDictation() { isDictating = false }
    func finishDictation() { isDictating = false; target?("The literature review") }
    func stopSpeaking() { stops += 1 }
    func waitUntilQuiet() async {}
    func listenForReply(pause: TimeInterval, giveUp: TimeInterval,
                        target: @escaping (String) -> Void, onSilence: @escaping () -> Void) -> Bool {
        opens += 1
        self.pause = pause; self.giveUp = giveUp
        self.target = target; silence = onSilence
        isDictating = microphoneAvailable
        return microphoneAvailable
    }
}

extension MentorConversationTests {
    @MainActor private func settle() async {
        for _ in 0..<30 { await Task.yield() }
    }

    @MainActor func testStreamingThenSpokenAndTypedTurns() async {
        let chat = MentorChatStub(), voice = MentorVoiceStub()
        let mentor = MentorConversation(chat: chat, voice: voice)
        mentor.start(topic: "Busy day")
        await settle()
        XCTAssertEqual(mentor.state, .thinking)
        chat.words?("What matters most?")
        XCTAssertEqual(mentor.line, "What matters most?")
        XCTAssertEqual(mentor.state, .speaking)
        XCTAssertEqual(voice.opens, 0, "never listen while Gemini is generating")
        chat.complete()
        await settle()
        XCTAssertEqual(mentor.state, .listening)
        XCTAssertEqual(voice.pause, 3)
        XCTAssertEqual(voice.giveUp, 30)
        mentor.listenNow()  // send the spoken reply
        await settle()
        XCTAssertEqual(chat.prompts.last, "The literature review")
        chat.words?("When could you start?")
        chat.complete()
        await settle()
        mentor.beginTyping()
        XCTAssertFalse(voice.isDictating)
        XCTAssertEqual(mentor.state, .typing)
        mentor.answer("At two")
        await settle()
        XCTAssertEqual(chat.prompts.last, "At two")
        chat.complete()
        await settle()
        voice.silence?()
        XCTAssertFalse(mentor.isActive)
    }

    @MainActor func testEndDiscardsLateWordsAndDoesNotReopenMicrophone() async {
        let chat = MentorChatStub(), voice = MentorVoiceStub()
        let mentor = MentorConversation(chat: chat, voice: voice)
        mentor.start(topic: "Today")
        await settle()
        mentor.end()
        chat.words?("Too late")
        chat.complete()
        await settle()
        XCTAssertFalse(mentor.isActive)
        XCTAssertEqual(mentor.line, "")
        XCTAssertEqual(voice.opens, 0)
        XCTAssertEqual(chat.stopped, 1)
        XCTAssertGreaterThan(voice.stops, 0)
    }

    @MainActor func testGateFailureAndMissingMicrophone() async {
        let chat = MentorChatStub(), voice = MentorVoiceStub()
        let mentor = MentorConversation(chat: chat, voice: voice)
        chat.canMentor = false
        mentor.start(topic: "Today")
        XCTAssertFalse(mentor.isActive)
        chat.canMentor = true
        mentor.start(topic: "Today")
        await settle()
        chat.complete(false)
        await settle()
        XCTAssertEqual(mentor.state, .typing)
        XCTAssertTrue(mentor.line.contains("Gemini is unavailable"))
        XCTAssertEqual(voice.opens, 0)
        voice.microphoneAvailable = false
        mentor.answer("Try again")
        await settle()
        chat.complete()
        await settle()
        XCTAssertEqual(mentor.state, .typing)
        mentor.end()
    }

    @MainActor func testGoodbyeUsesGeminiAndEndsWithoutListeningAgain() async {
        let chat = MentorChatStub(), voice = MentorVoiceStub()
        let mentor = MentorConversation(chat: chat, voice: voice)
        mentor.start(topic: "Today")
        await settle()
        chat.complete()
        await settle()
        mentor.answer("Thanks, that's all")
        await settle()
        XCTAssertTrue(chat.prompts.last!.contains("without a question"))
        chat.words?("Good luck today.")
        chat.complete()
        await settle()
        XCTAssertFalse(mentor.isActive)
        XCTAssertEqual(voice.opens, 1)
    }

    @MainActor func testFreeChatCannotStartGeminiMentor() async {
        let chat = ChatManager(calendar: CalendarManager(demo: true), health: HealthManager(demo: true),
                               gemini: GeminiAccess(), voice: VoiceManager())
        XCTAssertFalse(chat.canMentor)
    }
}
