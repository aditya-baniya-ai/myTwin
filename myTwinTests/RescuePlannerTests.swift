import XCTest
@testable import myTwin

/// Choosing when a rescue activity starts.
final class RescuePlannerTests: XCTestCase {
    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: hour, minute: minute))!
    }

    private func propose(now: Date, preferred: Date?, busy: [DateInterval] = [], minutes: Int = 20) -> RescueProposal? {
        RescuePlanner.propose(original: nil, busy: busy, movement: .walk, minutes: minutes,
                              preferences: PlanningPreferences(), now: now, energy: nil, preferred: preferred)
    }

    func testChosenTimeIsUsedWhenFree() {
        let proposal = propose(now: at(9), preferred: at(15))
        XCTAssertEqual(proposal?.replacement.start, at(15))
        XCTAssertEqual(proposal?.replacement.end, at(15, 20))
        XCTAssertFalse(proposal!.reason.contains("is taken"), proposal!.reason)
    }

    func testTakenTimeMovesToTheNextFreeSlotAndSaysSo() {
        let meeting = DateInterval(start: at(15), end: at(16))
        let proposal = propose(now: at(9), preferred: at(15), busy: [meeting])
        XCTAssertEqual(proposal?.replacement.start, at(16))
        XCTAssertTrue(proposal!.reason.hasPrefix("\(at(15).formatted(date: .omitted, time: .shortened)) is taken"),
                      proposal!.reason)
    }

    func testWithoutAChoiceItTakesTheNextFreeTime() {
        XCTAssertEqual(propose(now: at(9, 2), preferred: nil)?.replacement.start, at(9, 5))
    }

    func testAChosenTimeInThePastMeansNow() {
        XCTAssertEqual(propose(now: at(9, 2), preferred: at(7))?.replacement.start, at(9, 5))
    }

    func testNothingFitsBetweenTheChosenTimeAndBedtime() {
        XCTAssertNil(propose(now: at(9), preferred: at(22, 50), minutes: 20), "default bedtime is 11 PM")
    }
}
