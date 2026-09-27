import XCTest
@testable import myTwin

final class PlanningTests: XCTestCase {
    func date(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: hour, minute: minute))!
    }
    @MainActor func testPlannerNeverCrossesBedtimeOrOverlaps() {
        // Exercise rounded start times, overlapping meetings, and events after bedtime.
        for hour in 6...23 {
            for minute in [0, 10, 29, 45, 59] {
                let events = [(10, 12), (11, 13), (16, 17), (23, 24)].map {
                    PlanItem(kind: .event, title: "Meeting", start: date($0.0), end: date($0.1))
                }
                let now = date(hour, minute)
                let suggestions = DayPlanner.plan(events: events, dayStart: 0.88, now: now, bedtime: date(22), preferences: PlanningPreferences()).filter { $0.kind == .suggestion }
                for (index, item) in suggestions.enumerated() {
                    XCTAssertGreaterThanOrEqual(item.start, now)
                    XCTAssertLessThanOrEqual(item.end, date(22))
                    XCTAssertGreaterThan(item.end, item.start)
                    for other in events + Array(suggestions.dropFirst(index + 1)) {
                        XCTAssertFalse(item.start < other.end && item.end > other.start, "Overlap at \(hour):\(minute): \(item.title)")
                    }
                }
            }
        }
    }
    @MainActor func testCompletedWorkoutAndDismissalsSuppressSuggestions() {
        let plan = DayPlanner.plan(events: [], dayStart: 1, now: date(8), bedtime: date(23),
            excluding: [DayPlanner.easyTask, DayPlanner.napTitle, DayPlanner.coffeeTitle], trained: true)
        XCTAssertTrue(plan.isEmpty)
    }
    @MainActor func testLowEnergyStrengthBecomesShortGentleActivity() {
        var prefs = PlanningPreferences(); prefs.movement = .strength; prefs.minutes = 60
        let plan = DayPlanner.plan(events: [], dayStart: 1, now: date(8), bedtime: date(23), easyDay: true, preferences: prefs)
        let movement = plan.first { $0.movement != nil }
        XCTAssertEqual(movement?.movement, .stretch)
        XCTAssertEqual(movement?.end.timeIntervalSince(movement!.start), 1200)
    }
    @MainActor func testRescueFindsGapAndRefusesFullDay() {
        let prefs = PlanningPreferences()
        let busy = [DateInterval(start: date(14), end: date(15))]
        let result = RescuePlanner.propose(original: nil, busy: busy, movement: .walk, minutes: 20, preferences: prefs, now: date(14, 2), energy: .low)
        XCTAssertEqual(result?.replacement.start, date(15))
        XCTAssertEqual(result?.replacement.end, date(15, 20))
        XCTAssertTrue(result?.reason.contains("You said") == true)
        XCTAssertNil(RescuePlanner.propose(original: nil, busy: [DateInterval(start: date(14), end: date(23))], movement: .walk, minutes: 5, preferences: prefs, now: date(14), energy: nil))
        XCTAssertNil(RescuePlanner.propose(original: nil, busy: [], movement: .walk, minutes: 20, preferences: prefs, now: date(22, 50), energy: nil))
    }
    @MainActor func testRescueDoesNotMutateOriginalAndSupportsAfterMidnightBedtime() {
        var prefs = PlanningPreferences(); prefs.bedtimeHour = 1
        let original = PlannedAction(eventID: "owned", movement: .strength, title: "Strength", start: date(23), end: date(24))
        let result = RescuePlanner.propose(original: original, busy: [], movement: .stretch, minutes: 10, preferences: prefs, now: date(23), energy: .low)
        XCTAssertEqual(result?.original, original)
        XCTAssertEqual(result?.replacement.eventID, "owned")
        XCTAssertNotEqual(result?.replacement.id, original.id)
        XCTAssertEqual(result?.replacement.end, date(23, 10))
    }
    @MainActor func testSevenRecentNightsRequiredAndMissingTodayRejected() {
        let model = EnergyModel()!
        func history(_ count: Int) -> [DaySignals] {
            (0...count).map { DaySignals(date: Calendar.current.date(byAdding: .day, value: -$0, to: date(0))!, asleepMinutes: Double(400 + $0), efficiency: 95, deepMinutes: 60, remMinutes: 80, restingHR: 60) }
        }
        XCTAssertNil(model.reading(from: history(6)))
        XCTAssertNotNil(model.reading(from: history(7)))
        XCTAssertEqual(model.usableNights(in: history(40)).count, 14)
        var missing = history(14); missing[0].asleepMinutes = nil
        XCTAssertNil(model.reading(from: missing))
        let sparse = [history(40)[0]] + Array(history(40).dropFirst(20))
        XCTAssertNil(model.reading(from: sparse))
    }
    @MainActor func testForecastEndsAtBedtimeAndHandlesPastBedtime() {
        XCTAssertTrue(DayCharge.forecast(from: 1, now: date(23), until: date(22)).isEmpty)
        XCTAssertTrue(DayCharge.forecast(from: 1, now: date(9), until: date(23)).allSatisfy { $0.date <= date(23) })
    }
    @MainActor func testQuietHoursWrapMidnight() {
        let prefs = PlanningPreferences()
        XCTAssertTrue(prefs.isQuiet(date(23)))
        XCTAssertTrue(prefs.isQuiet(date(7)))
        XCTAssertFalse(prefs.isQuiet(date(12)))
    }
    @MainActor func testRescueVoiceIntent() {
        XCTAssertEqual(RescueIntent.parse("I'm exhausted and have 15 minutes")?.minutes, 15)
        XCTAssertNotNil(RescueIntent.parse("Rescue my day"))
        XCTAssertNil(RescueIntent.parse("What is on my calendar?"))
    }
}
