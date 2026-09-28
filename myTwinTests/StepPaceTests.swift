import XCTest
@testable import myTwin

final class StepPaceTests: XCTestCase {
    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: hour, minute: minute))!
    }
    /// A day with 300 steps an hour from 8 AM to 9 PM.
    private let usualDay: [Double] = (0..<24).map { (8...21).contains($0) ? 300 : 0 }

    func testProjectionAddsWhatYouUsuallyDoFromNowOn() {
        // At 2 PM a usual day still has 2 PM to 9 PM ahead: 8 hours of 300.
        let pace = StepPace.estimate(steps: 3_000, goal: 8_000, now: at(14), history: [usualDay, usualDay, usualDay])
        XCTAssertEqual(pace.projected, 3_000 + 8 * 300)
        XCTAssertFalse(pace.onTrack)
        XCTAssertEqual(pace.shortfall, 2_600)
        XCTAssertEqual(pace.walkMinutes, 10)
    }

    func testHalfAnHourGoneCountsHalfTheHour() {
        let pace = StepPace.estimate(steps: 0, goal: 1, now: at(20, 30), history: [usualDay])
        XCTAssertEqual(pace.projected, 150 + 300, "half of 8 PM, and all of 9 PM")
    }

    func testTheMedianDayNotTheAverage() {
        let big: [Double] = (0..<24).map { $0 == 20 ? 20_000 : 0 }       // one marathon evening
        let pace = StepPace.estimate(steps: 7_000, goal: 8_000, now: at(14), history: [usualDay, usualDay, big])
        XCTAssertEqual(pace.projected, 7_000 + 2_400, "the marathon doesn't count as usual")
    }

    func testChargerDaysAreIgnored() {
        let blank = [Double](repeating: 0, count: 24)
        let pace = StepPace.estimate(steps: 7_800, goal: 8_000, now: at(14), history: [blank, blank, usualDay])
        XCTAssertTrue(pace.onTrack)
        XCTAssertEqual(StepPace(steps: 7_700, goal: 8_000, projected: 7_700).walkMinutes, 5, "a small gap is 5 minutes")
    }

    func testSlotSkipsWhateverIsBooked() {
        let meeting = DateInterval(start: at(14, 10), end: at(15))
        XCTAssertEqual(StepPace.slot(minutes: 10, after: at(14, 2), busy: [meeting], latest: at(23)), at(15))
        XCTAssertEqual(StepPace.slot(minutes: 10, after: at(14, 2), busy: [], latest: at(23)), at(14, 10))
    }

    func testNoSlotWhenTheNextHourAndAHalfIsFull() {
        let block = DateInterval(start: at(14), end: at(18))
        XCTAssertNil(StepPace.slot(minutes: 10, after: at(14, 2), busy: [block], latest: at(23)))
        XCTAssertNil(StepPace.slot(minutes: 10, after: at(22, 55), busy: [], latest: at(23)), "not past bedtime")
    }

    func testMessage() {
        let pace = StepPace(steps: 3_200, goal: 8_000, projected: 6_430)
        XCTAssertEqual(pace.message(walkAt: at(14, 35)),
                       "You're at 3,200 of 8,000 steps. At your usual pace you'll end near 6,400. A 10-minute walk at \(at(14, 35).formatted(date: .omitted, time: .shortened)) is on your calendar.")
    }
}
