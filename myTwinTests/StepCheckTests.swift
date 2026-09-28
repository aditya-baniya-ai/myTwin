import XCTest
@testable import myTwin

/// The step check, run against the demo's steps and calendar, which live in memory.
final class StepCheckTests: XCTestCase {
    private func goal(_ steps: Double?) -> PlanningPreferences {
        var value = PlanningPreferences()
        value.stepGoal = steps
        return value
    }

    @MainActor func testBehindAddsAWalkInTheNextFreeSlot() async throws {
        let calendar = CalendarManager(demo: true)
        var log = StepCheck.Log()
        let outcome = await StepCheck.run(health: HealthManager(demo: true), calendar: calendar,
                                          preferences: goal(8_000), now: SampleDay.at(14), log: &log, notify: false)
        guard case .walk(let pace, let start)? = outcome else { return XCTFail("\(String(describing: outcome))") }
        XCTAssertEqual(pace.walkMinutes, 5, "Alex is a few hundred steps short")
        XCTAssertEqual(start, SampleDay.at(14, minute: 5), "free before the 2:30 meeting")
        XCTAssertNotNil(calendar.upcomingWalk(after: SampleDay.at(14)))
        XCTAssertEqual(log.walks(on: SampleDay.at(14)), 1)
    }

    @MainActor func testNotAgainWithinTwoHours() async {
        let calendar = CalendarManager(demo: true)
        var log = StepCheck.Log()
        _ = await StepCheck.run(health: HealthManager(demo: true), calendar: calendar,
                                preferences: goal(8_000), now: SampleDay.at(14), log: &log, notify: false)
        let soon = await StepCheck.run(health: HealthManager(demo: true), calendar: calendar,
                                       preferences: goal(8_000), now: SampleDay.at(15, minute: 30), log: &log, notify: false)
        XCTAssertNil(soon)
    }

    @MainActor func testOnTrackAddsNothing() async {
        let calendar = CalendarManager(demo: true)
        let before = calendar.events.count
        var log = StepCheck.Log()
        let outcome = await StepCheck.run(health: HealthManager(demo: true), calendar: calendar,
                                          preferences: goal(7_000), now: SampleDay.at(14), log: &log, notify: false)
        guard case .onTrack? = outcome else { return XCTFail("\(String(describing: outcome))") }
        XCTAssertEqual(calendar.events.count, before)
    }

    @MainActor func testQuietWithoutAGoalOrAtNight() async {
        var log = StepCheck.Log()
        let noGoal = await StepCheck.run(health: HealthManager(demo: true), calendar: CalendarManager(demo: true),
                                         preferences: goal(nil), now: SampleDay.at(14), log: &log, notify: false)
        XCTAssertNil(noGoal)
        let night = await StepCheck.run(health: HealthManager(demo: true), calendar: CalendarManager(demo: true),
                                        preferences: goal(8_000), now: SampleDay.at(22, minute: 30), log: &log, notify: false)
        XCTAssertNil(night)
        var off = goal(8_000); off.addsStepWalks = false
        let turnedOff = await StepCheck.run(health: HealthManager(demo: true), calendar: CalendarManager(demo: true),
                                            preferences: off, now: SampleDay.at(14), log: &log, notify: false)
        XCTAssertNil(turnedOff)
    }
}
