import XCTest
@testable import myTwin

final class DashNudgeTests: XCTestCase {
    private let days = Calendar.current

    /// The next Wednesday (weekday 4) or Sunday (1) at a given time, so nothing depends on
    /// what day the tests run.
    private func at(weekday: Int = 4, _ hour: Int, _ minute: Int = 0) -> Date {
        days.nextDate(after: Date(timeIntervalSince1970: 1_790_000_000),
                      matching: DateComponents(hour: hour, minute: minute, weekday: weekday),
                      matchingPolicy: .nextTime)!
    }

    private func situation(now: Date, dayStart: Double = 0.9, forecast: [EnergyPoint] = [],
                           events: [PlanItem] = [], suggestions: [PlanItem] = [],
                           steps: Double? = nil, recap: Bool = false) -> DashNudges.Situation {
        .init(now: now, dayStart: dayStart, forecast: forecast, events: events,
              suggestions: suggestions, stepsLastTwoHours: steps, hasWeekRecap: recap)
    }

    private func event(_ start: Date, minutes: Double = 30, _ title: String = "Team sync") -> PlanItem {
        PlanItem(kind: .event, title: title, start: start, end: start.addingTimeInterval(minutes * 60))
    }

    private func kinds(_ s: DashNudges.Situation) -> [DashNudge.Kind] { DashNudges.candidates(s).map(\.kind) }

    func testLowEnergyEventHalfAnHourAway() {
        let now = at(13)
        let nudges = DashNudges.candidates(situation(now: now, dayStart: 0.3,
                                                     events: [event(now.addingTimeInterval(30 * 60))]))
        XCTAssertEqual(nudges.first?.kind, .lowEnergyEvent)
        XCTAssertTrue(nudges.first!.line.hasPrefix("Team sync at"), nudges.first!.line)
    }

    func testEventTooFarAwayOrWithEnoughEnergyIsLeftAlone() {
        let now = at(13)
        XCTAssertFalse(kinds(situation(now: now, dayStart: 0.3,
                                       events: [event(now.addingTimeInterval(2 * 3600))])).contains(.lowEnergyEvent))
        XCTAssertFalse(kinds(situation(now: now, dayStart: 1.0,
                                       events: [event(now.addingTimeInterval(30 * 60))])).contains(.lowEnergyEvent))
    }

    func testDipSoonUnlessSomethingIsBookedBeforeIt() {
        let now = at(13)
        let dip = now.addingTimeInterval(45 * 60)
        let forecast = [EnergyPoint(date: now, charge: 0.8), EnergyPoint(date: dip, charge: 0.1)]
        XCTAssertTrue(kinds(situation(now: now, forecast: forecast)).contains(.dipSoon))
        let booked = event(dip.addingTimeInterval(-20 * 60), minutes: 30)
        XCTAssertFalse(kinds(situation(now: now, forecast: forecast, events: [booked])).contains(.dipSoon))
    }

    func testSuggestionAboutToStartCarriesItsReason() {
        let now = at(13)
        let nap = PlanItem(kind: .suggestion, title: "Power nap", start: now.addingTimeInterval(10 * 60),
                           end: now.addingTimeInterval(30 * 60), note: "You're down to 40%.")
        let nudge = DashNudges.candidates(situation(now: now, suggestions: [nap])).first
        XCTAssertEqual(nudge?.kind, .suggestionSoon)
        XCTAssertTrue(nudge!.line.contains("You're down to 40%."), nudge!.line)
    }

    /// The step check's walk comes after a suggestion about to start, and before a long sit.
    func testStepWalkSaysWhatTheStepCheckSaid() {
        let now = at(14)
        let walk = "You're at 6,420 of 8,000 steps. A 5-minute walk at 2:05 PM is on your calendar."
        var s = situation(now: now, steps: 100)
        s.stepWalk = walk
        XCTAssertEqual(kinds(s), [.stepWalk, .sitting])
        XCTAssertEqual(DashNudges.candidates(s).first?.line, walk)
        XCTAssertFalse(kinds(situation(now: now)).contains(.stepWalk), "no walk booked, nothing to say")

        let nap = PlanItem(kind: .suggestion, title: "Power nap", start: now.addingTimeInterval(600),
                           end: now.addingTimeInterval(1800))
        var both = situation(now: now, suggestions: [nap])
        both.stepWalk = walk
        XCTAssertEqual(kinds(both), [.suggestionSoon, .stepWalk])
    }

    /// No step data is not the same as no steps: the watch may simply not have synced.
    func testSittingOnlyInDaytimeAndOnlyWithStepData() {
        XCTAssertTrue(kinds(situation(now: at(11), steps: 100)).contains(.sitting))
        XCTAssertFalse(kinds(situation(now: at(22), steps: 100)).contains(.sitting))
        XCTAssertFalse(kinds(situation(now: at(11), steps: nil)).contains(.sitting))
        XCTAssertFalse(kinds(situation(now: at(11), steps: 900)).contains(.sitting))
    }

    func testWeekRecapOnlyWhenTheWeekIsOver() {
        XCTAssertTrue(kinds(situation(now: at(weekday: 1, 18), recap: true)).contains(.weekRecap))
        XCTAssertTrue(kinds(situation(now: at(weekday: 2, 9), recap: true)).contains(.weekRecap))
        XCTAssertFalse(kinds(situation(now: at(weekday: 4, 18), recap: true)).contains(.weekRecap))
        XCTAssertFalse(kinds(situation(now: at(weekday: 1, 18), recap: false)).contains(.weekRecap))
    }

    /// The part that keeps him from nagging.
    func testSpacingOncePerDayAndQuietHours() {
        let now = at(11)
        let sitting = situation(now: now, steps: 100)
        var log = DashNudges.Log()

        XCTAssertNil(DashNudges.next(sitting, quiet: true, log: &log), "never in quiet hours")
        XCTAssertEqual(DashNudges.next(sitting, quiet: false, log: &log)?.kind, .sitting)
        XCTAssertNil(DashNudges.next(sitting, quiet: false, log: &log), "not twice in a row")

        let later = now.addingTimeInterval(2 * 3600)
        XCTAssertNil(DashNudges.next(situation(now: later, steps: 100), quiet: false, log: &log),
                     "the same thing only once a day")
        let nap = PlanItem(kind: .suggestion, title: "Power nap", start: later.addingTimeInterval(600),
                           end: later.addingTimeInterval(1800))
        XCTAssertEqual(DashNudges.next(situation(now: later, suggestions: [nap], steps: 100), quiet: false,
                                       log: &log)?.kind, .suggestionSoon,
                       "something new is fine once 90 minutes have passed")
    }
}
