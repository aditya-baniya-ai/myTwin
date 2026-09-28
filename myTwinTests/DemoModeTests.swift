import XCTest
@testable import myTwin

/// The guest demo reads like a real user's day and never touches the real one.
final class DemoModeTests: XCTestCase {
    @MainActor func testDemoCalendarHasTodayAndTheWeek() async {
        let calendar = CalendarManager(demo: true)
        XCTAssertTrue(calendar.isAuthorized, "no permission needed")
        XCTAssertTrue(calendar.todayEventsText().contains("Project meeting"))
        let week = calendar.weekEventsText()
        XCTAssertTrue(week.contains("Tomorrow: Team standup"), week)
        XCTAssertTrue(week.contains("Dentist"), week)
        XCTAssertTrue(week.contains("Mom's birthday (all day)"), week)
    }

    /// The simulator has no calendar access, so this would throw if it reached EventKit.
    @MainActor func testChangesYouConfirmStayInTheDemoWeek() async {
        let calendar = CalendarManager(demo: true)
        let before = calendar.events.count
        _ = calendar.proposeAdd(title: "Stretch break", hour: 15, minute: 30, durationMinutes: 15)
        XCTAssertTrue(calendar.confirmPendingChange().hasPrefix("Done."))
        XCTAssertEqual(calendar.events.count, before + 1)
        XCTAssertTrue(calendar.todayEventsText().contains("Stretch break"))

        _ = calendar.proposeRemove(title: "Stretch break")
        XCTAssertTrue(calendar.confirmPendingChange().hasPrefix("Removed"))
        XCTAssertEqual(calendar.events.count, before)
        XCTAssertEqual(CalendarManager(demo: true).events.count, before, "a new demo starts clean")
    }

    @MainActor func testDemoHealthReadsLikeARealUser() async {
        let health = HealthManager(demo: true)
        XCTAssertTrue(health.isAuthorized)
        let summary = await health.summaryText()
        XCTAssertTrue(summary.contains("Sleep last night: 5.7 hours"), summary)
        XCTAssertTrue(summary.contains("Steps today: 6420"), summary)
        let history = await health.history()
        XCTAssertEqual(history.days.count, 15)
        let workouts = await health.workoutDetails()
        XCTAssertFalse(workouts.isEmpty)

        let weighIns = await health.weights().count
        try? await health.logWeight(pounds: 168)
        let after = await health.weights().count
        XCTAssertEqual(after, weighIns + 1, "a weigh-in is kept, in memory")
    }

    @MainActor func testDemoQuestionsHaveAnswers() {
        let questions = DemoData.questions
        XCTAssertGreaterThanOrEqual(questions.count, 2)
        XCTAssertTrue(questions.allSatisfy { $0.count > 1 && $0.answer != nil })
    }

    /// Asking in the demo leaves your own "You often ask" history alone.
    @MainActor func testDemoChatDoesNotRecordYourQuestions() async {
        let key = "asked.questions"
        let saved = UserDefaults.standard.data(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }

        let chat = ChatManager(calendar: CalendarManager(demo: true), health: HealthManager(demo: true),
                               gemini: GeminiAccess(), voice: VoiceManager())
        await chat.send("What do I have tomorrow in the demo?")
        XCTAssertEqual(UserDefaults.standard.data(forKey: key), saved)
    }
}
