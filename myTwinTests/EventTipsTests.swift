import XCTest
@testable import myTwin

/// The one-line tip on the Up next card.
final class EventTipsTests: XCTestCase {
    func testKindComesFromTheTitle() {
        XCTAssertEqual(EventTips.kind(of: "Project meeting"), .meeting)
        XCTAssertEqual(EventTips.kind(of: "Team standup"), .meeting)
        XCTAssertEqual(EventTips.kind(of: "CS 3358 Data Structures class"), .learning)
        XCTAssertEqual(EventTips.kind(of: "Gym: legs"), .training)
        XCTAssertEqual(EventTips.kind(of: "Dinner with Sam"), .social)
        XCTAssertEqual(EventTips.kind(of: "Dentist"), .other)
        XCTAssertEqual(EventTips.kind(of: "Anything at all", isActivity: true), .training)
    }

    func testForecastBeatsCheckInAndIsSaid() {
        let tip = EventTips.tip(title: "Project meeting", charge: 0.39, reported: .good)
        XCTAssertTrue(tip.hasPrefix("You'll be at about 39% then."), tip)
        XCTAssertTrue(tip.contains("action items"), "low energy, not the check-in's good: \(tip)")
    }

    func testCheckInStandsInWithoutAForecast() {
        let tip = EventTips.tip(title: "Gym: legs", charge: nil, reported: .low)
        XCTAssertFalse(tip.contains("%"), "no forecast without Pro: \(tip)")
        XCTAssertTrue(tip.contains("mobility"), tip)
    }

    func testWithNeitherTheTipIsAboutTheEvent() {
        XCTAssertEqual(EventTips.tip(title: "Class", charge: nil, reported: nil),
                       "Skim your notes for five minutes beforehand.")
    }
}
