import XCTest
@testable import myTwin

final class TomorrowForecastTests: XCTestCase {
    @MainActor func testNoPredictionWithoutHistoryOrASensibleNight() throws {
        let model = try XCTUnwrap(EnergyModel())
        let now = SampleDay.now
        XCTAssertNil(TomorrowForecast.estimate(expectedSleepHours: 8, history: [], model: model, now: now).dayStart)
        XCTAssertNil(TomorrowForecast.estimate(expectedSleepHours: 2, history: SampleDay.history, model: model, now: now).dayStart)
        XCTAssertNil(TomorrowForecast.estimate(expectedSleepHours: .nan, history: SampleDay.history, model: model, now: now).dayStart)
    }

    /// The point of the card: the number you set changes the answer, in the right direction.
    @MainActor func testMoreSleepNeverLooksWorse() throws {
        let model = try XCTUnwrap(EnergyModel())
        let starts = stride(from: 4.0, through: 11.0, by: 0.5).map {
            TomorrowForecast.estimate(expectedSleepHours: $0, history: SampleDay.history, model: model, now: SampleDay.now).dayStart
        }
        XCTAssertFalse(starts.contains(nil))
        let values = starts.compactMap { $0 }
        XCTAssertEqual(values, values.sorted(), "more sleep never gives a lower outlook")
        XCTAssertGreaterThan(Set(values).count, 1, "and it does change")
    }

    @MainActor func testFutureAndDuplicateDaysAreIgnored() throws {
        let model = try XCTUnwrap(EnergyModel())
        let history = SampleDay.history
        let baseline = TomorrowForecast.estimate(expectedSleepHours: 6, history: history, model: model, now: SampleDay.now)
        let future = DaySignals(date: Calendar.current.date(byAdding: .day, value: 2, to: SampleDay.now)!,
                                asleepMinutes: 600, restingHR: 40)
        let polluted = TomorrowForecast.estimate(expectedSleepHours: 6, history: [future] + history + history,
                                                 model: model, now: SampleDay.now)
        XCTAssertEqual(polluted.reading?.deviation, baseline.reading?.deviation)
        XCTAssertEqual(history.first?.asleepMinutes, 340, "your real history is left alone")
    }
}
