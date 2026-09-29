import XCTest
@testable import myTwin

final class TomorrowForecastTests: XCTestCase {
    @MainActor func testInsufficientAndUnmatchedHistoryDoesNotInventPrediction() throws {
        let model = try XCTUnwrap(EnergyModel())
        let now = SampleDay.now
        XCTAssertNil(TomorrowForecast.estimate(expectedSleepHours: 8, history: [], model: model, now: now).dayStart)
        XCTAssertNil(TomorrowForecast.estimate(expectedSleepHours: 3, history: SampleDay.history, model: model, now: now).dayStart)
        XCTAssertNil(TomorrowForecast.estimate(expectedSleepHours: .nan, history: SampleDay.history, model: model, now: now).dayStart)
    }

    @MainActor func testComparableNightsProduceOutlookWithoutChangingHistory() throws {
        let model = try XCTUnwrap(EnergyModel())
        let history = SampleDay.history
        let result = TomorrowForecast.estimate(expectedSleepHours: 7.5, history: history, model: model, now: SampleDay.now)
        XCTAssertGreaterThanOrEqual(result.comparableNights, 3)
        XCTAssertNotNil(result.dayStart)
        XCTAssertNotNil(result.band)
        XCTAssertEqual(history.first?.asleepMinutes, 340)
    }

    @MainActor func testFutureAndDuplicateDaysDoNotIncreaseEvidence() throws {
        let model = try XCTUnwrap(EnergyModel())
        let history = SampleDay.history
        let baseline = TomorrowForecast.estimate(expectedSleepHours: 7.5, history: history, model: model, now: SampleDay.now)
        var future = history[1]
        future = DaySignals(date: Calendar.current.date(byAdding: .day, value: 1, to: SampleDay.now)!, asleepMinutes: future.asleepMinutes)
        let polluted = TomorrowForecast.estimate(expectedSleepHours: 7.5, history: [future] + history + history, model: model, now: SampleDay.now)
        XCTAssertEqual(polluted.comparableNights, baseline.comparableNights)
        XCTAssertEqual(polluted.dayStart, baseline.dayStart)
    }
}
