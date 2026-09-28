import XCTest
@testable import myTwin

/// Goals said out loud, as dictation writes them.
final class GoalSpeechTests: XCTestCase {
    func testSpokenFormsAreRead() {
        let lit = GoalParser.line("finish the lit review, that'll take about two hours in the morning")
        XCTAssertEqual(lit?.title, "Finish the lit review")
        XCTAssertEqual(lit?.minutes, 120)
        XCTAssertEqual(lit?.window, .morning)

        XCTAssertEqual(GoalParser.line("call mom at 7 p.m.")?.hour, 19)
        XCTAssertEqual(GoalParser.line("Meeting with Sam at 10:30 a.m.")?.minute, 30)
        XCTAssertEqual(GoalParser.line("grocery run for half an hour in the evening")?.minutes, 30)
        XCTAssertEqual(GoalParser.line("write the report for an hour and a half")?.minutes, 90)
        XCTAssertEqual(GoalParser.line("study for my exam three hours")?.minutes, 180)
        XCTAssertEqual(GoalParser.line("submit the grant application by noon")?.hour, 12)
        XCTAssertEqual(GoalParser.line("maybe read a chapter before bed")?.window, .evening)
        XCTAssertEqual(GoalParser.line("I need to work on the research poster")?.title, "Work on the research poster")
        XCTAssertEqual(GoalParser.line("10 minute walk")?.title, "Walk", "a leading number is a length, not a list number")
    }

    func testJoinedGoalsAreSplit() {
        XCTAssertEqual(GoalSpeech.split("call mom at 7pm and go to the gym for 45 minutes"),
                       ["call mom at 7pm", "go to the gym for 45 minutes"])
        XCTAssertEqual(GoalSpeech.split("Go for a run. Finish my assignment. Pick up laundry."),
                       ["Go for a run", "Finish my assignment", "Pick up laundry."])
        XCTAssertEqual(GoalSpeech.split("buy salt and pepper"), ["buy salt and pepper"], "not every 'and' is a new goal")
    }

    func testLinesForTheBox() async {
        let lines = await GoalSpeech.lines(from: "Tomorrow I want to finish the lit review, that'll take about two hours in the morning, then call mom at 7 p.m. and go to the gym for 45 minutes.")
        XCTAssertEqual(lines, ["Finish the lit review, 2 hr, morning", "Call mom, at 7pm", "Go to the gym, 45 min"])
        let parsed = GoalParser.parse(lines.joined(separator: "\n"))
        XCTAssertEqual(parsed.map(\.minutes), [120, 30, 45], "the box reads its own lines back the same way")
        XCTAssertEqual(parsed[1].hour, 19)
    }

    func testInventedLinesAreDropped() {
        let said = "work on the research poster and then maybe read a chapter before bed"
        XCTAssertTrue(GoalSpeech.copied("maybe read a chapter before bed", from: said))
        XCTAssertFalse(GoalSpeech.copied("two hours at 10 a.m.", from: said))
    }
}
