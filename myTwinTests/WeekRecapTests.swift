import XCTest
@testable import myTwin

final class WeekRecapTests: XCTestCase {
    private let model = EnergyModel()!

    /// Fifteen nights, newest first, all the same unless `change` says otherwise.
    private func nights(_ change: (Int, inout DaySignals) -> Void = { _, _ in }) -> [DaySignals] {
        (0..<15).map { day in
            var night = DaySignals(date: Calendar.current.date(byAdding: .day, value: -day, to: .now)!,
                                   asleepMinutes: 450, efficiency: 94, deepMinutes: 60,
                                   remMinutes: 85, restingHR: 58)
            change(day, &night)
            return night
        }
    }

    func testShortNightIsTheHardestDayAndSaysWhy() {
        let lines = WeekRecap.lines(history: SampleDay.history, model: model)
        XCTAssertEqual(lines.count >= 2, true, "\(lines)")
        XCTAssertTrue(lines[1].hasPrefix("The hardest was today."), lines[1])
        XCTAssertTrue(lines[1].contains("less than usual"), lines[1])
        XCTAssertFalse(lines[0].contains("today"), "the best day can't also be today: \(lines[0])")
    }

    func testSaysNothingWithTooLittleHistory() {
        XCTAssertEqual(WeekRecap.lines(history: Array(SampleDay.history.prefix(3)), model: model), [])
    }

    func testSaysNothingWhenEveryDayWasTheSame() {
        XCTAssertEqual(WeekRecap.lines(history: nights(), model: model), [])
    }

    /// A worse day with no standout signal must not be given an invented cause.
    func testAdmitsWhenNothingExplainsADip() {
        let lines = WeekRecap.lines(history: nights { day, night in if day == 2 { night.efficiency = 80 } },
                                    model: model)
        XCTAssertEqual(lines.count >= 2, true, "\(lines)")
        XCTAssertTrue(lines[1].contains("some dips have no single cause"), lines[1])
    }

    func testCountsShortNightsAcrossTheWeek() {
        let lines = WeekRecap.lines(history: nights { day, night in
            if [0, 2, 4, 5].contains(day) { night.asleepMinutes = 360 }
        }, model: model)
        XCTAssertTrue(lines.contains("4 of the last 7 nights were under 7 hours."), "\(lines)")
    }

    func testChatTextExplainsWhenThereIsNoRecap() {
        XCTAssertTrue(WeekRecap.text(history: [], model: model).hasPrefix("Not enough nights"))
    }
}
