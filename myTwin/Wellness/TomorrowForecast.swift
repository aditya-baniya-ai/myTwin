import Foundation

/// An exploratory outlook from historical model estimates after similar-length sleep.
/// Expected sleep is a user assumption, never a future HealthKit measurement.
struct TomorrowForecast {
    let expectedSleepHours: Double
    let comparableNights: Int
    let dayStart: Double?
    let band: EnergyReading.Band?

    var headline: String {
        switch band {
        case .above: "Tomorrow may be above your usual"
        case .normal: "Tomorrow may be around your usual"
        case .below: "Tomorrow may be below your usual"
        case nil: "Still learning about nights like this"
        }
    }

    /// Replay each historical day using only its preceding history. Never recycle
    /// today's score as tomorrow's prediction or invent future sleep stages/heart rate.
    static func estimate(expectedSleepHours: Double, history: [DaySignals],
                         model: EnergyModel?, now: Date) -> Self {
        guard expectedSleepHours.isFinite, (3...12).contains(expectedSleepHours), let model else {
            return Self(expectedSleepHours: expectedSleepHours, comparableNights: 0, dayStart: nil, band: nil)
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let cutoff = calendar.date(byAdding: .day, value: -60, to: today)!
        var seen = Set<Date>()
        let past = history.filter { $0.date < calendar.date(byAdding: .day, value: 1, to: today)! }
            .sorted { $0.date > $1.date }
            .filter { seen.insert(calendar.startOfDay(for: $0.date)).inserted }
        var starts: [Double] = []
        for index in past.indices {
            let night = past[index]
            guard night.date >= cutoff, let asleep = night.asleepMinutes, asleep.isFinite,
                  abs(asleep - expectedSleepHours * 60) <= 60,
                  let reading = model.reading(from: Array(past[index...])) else { continue }
            starts.append(model.dayStart(for: reading))
        }
        guard starts.count >= 3 else {
            return Self(expectedSleepHours: expectedSleepHours, comparableNights: starts.count, dayStart: nil, band: nil)
        }
        let sorted = starts.sorted()
        let median = sorted[sorted.count / 2]
        let band: EnergyReading.Band = median < 0.8 ? .below : median > 0.95 ? .above : .normal
        return Self(expectedSleepHours: expectedSleepHours, comparableNights: starts.count, dayStart: median, band: band)
    }
}
