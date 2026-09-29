import XCTest
@testable import myTwin

final class GoalsTests: XCTestCase {
    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 29) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    // MARK: Reading what you wrote

    func testLengthsTimesAndPartsOfTheDay() {
        let goals = GoalParser.parse("""
        - Finish lit review, 2 hrs, morning
        2. Call mom at 7pm
        • Gym 45 min
        Read a chapter
        """)
        XCTAssertEqual(goals.map(\.title), ["Finish lit review", "Call mom", "Gym", "Read a chapter"])
        XCTAssertEqual(goals[0].minutes, 120)
        XCTAssertEqual(goals[0].window, .morning)
        XCTAssertEqual(goals[0].kind, .professional)
        XCTAssertEqual(goals[1].hour, 19)
        XCTAssertEqual(goals[1].minute, 0)
        XCTAssertEqual(goals[1].kind, .personal)
        XCTAssertEqual(goals[2].minutes, 45)
        XCTAssertEqual(goals[3].minutes, 30, "a personal goal with no length is half an hour")
    }

    func testBlankLinesAndHalfHours() {
        let goals = GoalParser.parse("\n\n  \nWrite the report 1.5 hours\nStandup at 9:30am")
        XCTAssertEqual(goals.count, 2)
        XCTAssertEqual(goals[0].minutes, 90)
        XCTAssertEqual(goals[1].hour, 9)
        XCTAssertEqual(goals[1].minute, 30)
    }

    // MARK: Planning the day

    func testNamedTimesStayAndWorkGetsTheBestHours() {
        let goals = GoalParser.parse("Call mom at 7pm\nFinish lit review, 2 hrs\nGrocery run, 30 min")
        let class1 = DateInterval(start: at(8), end: at(10))
        let times = GoalPlanner.plan(goals, on: at(0), busy: [class1], wake: 8, bedtime: at(23))
        XCTAssertEqual(times[goals[0].id], at(19))
        XCTAssertEqual(times[goals[1].id], at(10), "the first free peak hour, after the 8-10 class")
        let grocery = try! XCTUnwrap(times[goals[2].id])
        XCTAssertGreaterThanOrEqual(Calendar.current.component(.hour, from: grocery), 16, "personal goals go later")
    }

    func testNothingOverlapsAndNothingAfterBedtime() {
        let goals = GoalParser.parse("Deep work 3 hrs\nProject report 3 hrs\nEssay 3 hrs\nThesis 3 hrs\nStudy 3 hrs")
        let times = GoalPlanner.plan(goals, on: at(0), busy: [], wake: 8, bedtime: at(23))
        let blocks = goals.compactMap { goal in times[goal.id].map { DateInterval(start: $0, duration: Double(goal.minutes) * 60) } }
        for (i, a) in blocks.enumerated() {
            for b in blocks[(i + 1)...] { XCTAssertFalse(a.start < b.end && b.start < a.end) }
            XCTAssertLessThanOrEqual(a.end, at(22), "an hour before bedtime")
        }
        XCTAssertLessThan(blocks.count, 5, "15 hours don't fit between 8 AM and 10 PM")
    }

    func testPlanningAgainKeepsTimesAndFillsInNewGoals() {
        var goals = GoalParser.parse("Finish lit review, 2 hrs\nGym 45 min")
        let first = GoalPlanner.plan(goals, on: at(0), busy: [], wake: 8, bedtime: at(23))
        goals[0].scheduled = at(15)                       // you moved it
        goals[1].scheduled = first[goals[1].id]           // the planner's pick, untouched
        goals += GoalParser.parse("Call the bank 30 min")  // written after planning

        let again = GoalPlanner.plan(goals, on: at(0), busy: [], wake: 8, bedtime: at(23))
        XCTAssertEqual(again[goals[0].id], at(15), "your time stays")
        XCTAssertEqual(again[goals[1].id], first[goals[1].id], "so does the planner's")
        let bank = try! XCTUnwrap(again[goals[2].id], "the new goal is planned")
        XCTAssertFalse(bank < at(17) && bank.addingTimeInterval(1800) > at(15), "around the kept ones")
    }

    // MARK: Keeping them

    @MainActor func testTicksSurviveEditsAndUnfinishedMoveOn() async {
        let name = "myTwinTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let book = GoalBook(defaults: defaults)
        let today = at(9, day: 28), tomorrow = at(9)

        book.write("Email Prof Lee\nGym 45 min\nFinish report 2 hrs", for: today)
        book.toggle(book.day(today).goals[0], on: today)
        book.write("Email Prof Lee\nGym 45 min\nFinish report 2 hrs\nCall mom", for: today)
        XCTAssertTrue(book.day(today).goals[0].done, "adding a line keeps the tick")

        XCTAssertEqual(book.moveUnfinished(from: today), 3)
        XCTAssertEqual(book.day(tomorrow).goals.map(\.title), ["Gym", "Finish report", "Call mom"])
        XCTAssertEqual(book.day(tomorrow).goals[1].minutes, 120, "the length comes along")
        XCTAssertEqual(book.moveUnfinished(from: today), 0, "not twice")

        let reopened = GoalBook(defaults: defaults)
        XCTAssertEqual(reopened.day(tomorrow).goals.count, 3, "saved on the phone")
    }

    /// Changing a planned time moves that goal's event, keeps its length, and leaves the
    /// other goals where they were.
    @MainActor func testMovingOnePlannedGoal() async {
        let calendar = CalendarManager(demo: true)
        let book = GoalBook(demo: true)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: SampleDay.at(10))!
        book.write("Finish report 2 hrs\nGym 45 min", for: tomorrow)
        let goals = book.day(tomorrow).goals
        let first = tomorrow, second = tomorrow.addingTimeInterval(3 * 3600)
        XCTAssertEqual(calendar.placeGoals([(goals[0], first), (goals[1], second)], on: tomorrow), 2)
        book.schedule([goals[0].id: first, goals[1].id: second], on: tomorrow)

        let later = tomorrow.addingTimeInterval(5 * 3600)
        XCTAssertTrue(calendar.moveGoal(goals[0], to: later))
        book.reschedule(goals[0], to: later, on: tomorrow)

        let report = calendar.week.first { $0.title == "Finish report" }
        XCTAssertEqual(report?.startDate, later)
        XCTAssertEqual(report?.endDate, later.addingTimeInterval(2 * 3600), "same length")
        XCTAssertEqual(calendar.week.first { $0.title == "Gym" }?.startDate, second, "the other goal stays")
        XCTAssertEqual(book.day(tomorrow).goals.map(\.scheduled), [later, second])
    }

    @MainActor func testDemoKeepsItsGoalsInMemory() async {
        let book = GoalBook(demo: true)
        XCTAssertFalse(book.day(SampleDay.now).goals.isEmpty)
        book.write("Anything", for: SampleDay.now)
        XCTAssertNil(UserDefaults.standard.data(forKey: "goals.days.v1").flatMap { String(data: $0, encoding: .utf8) }?.range(of: "Anything"))
    }
}
