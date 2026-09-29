import Foundation

/// What tomorrow might look like if tonight's sleep is `expectedSleepHours`: the same model
/// as today's prediction, asked about a night that hasn't happened yet. Nothing about
/// tonight can be measured, so its other signals are assumed to be your recent normal:
/// deep sleep and REM at your usual share of the night, efficiency and resting heart rate
/// at your usual values. Only the sleep length is yours to change.
struct TomorrowForecast {
    let expectedSleepHours: Double
    /// The model's reading for that night, or nil while there isn't enough history.
    let reading: EnergyReading?
    let dayStart: Double?

    var band: EnergyReading.Band? { reading?.band }

    var headline: String {
        switch band {
        case .above: "Tomorrow may be above your usual"
        case .normal: "Tomorrow may be around your usual"
        case .below: "Tomorrow may be below your usual"
        case nil: "Still learning your normal"
        }
    }

    static func estimate(expectedSleepHours: Double, history: [DaySignals],
                         model: EnergyModel?, now: Date) -> Self {
        let none = Self(expectedSleepHours: expectedSleepHours, reading: nil, dayStart: nil)
        let calendar = Calendar.current
        guard expectedSleepHours.isFinite, (3...12).contains(expectedSleepHours), let model,
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        else { return none }

        // Nights already measured, newest first, one per day.
        var seen = Set<Date>()
        let past = history.filter { $0.date < tomorrow }
            .sorted { $0.date > $1.date }
            .filter { seen.insert(calendar.startOfDay(for: $0.date)).inserted }
        let recent = past.filter { ($0.asleepMinutes ?? 0) > 0 }.prefix(14)

        func median(_ values: [Double]) -> Double? {
            let sorted = values.sorted()
            return sorted.isEmpty ? nil : sorted[sorted.count / 2]
        }
        /// Your usual share of the night spent in a stage, so a shorter night has less of it.
        func share(_ stage: KeyPath<DaySignals, Double?>) -> Double? {
            median(recent.compactMap { night in
                night[keyPath: stage].flatMap { minutes in night.asleepMinutes.map { minutes / $0 } }
            })
        }

        let asleep = expectedSleepHours * 60
        let tonight = DaySignals(date: tomorrow, asleepMinutes: asleep,
                                 efficiency: median(recent.compactMap(\.efficiency)),
                                 deepMinutes: share(\.deepMinutes).map { $0 * asleep },
                                 remMinutes: share(\.remMinutes).map { $0 * asleep },
                                 restingHR: median(recent.compactMap(\.restingHR)))
        guard let reading = model.reading(from: [tonight] + past) else { return none }
        return Self(expectedSleepHours: expectedSleepHours, reading: reading, dayStart: model.dayStart(for: reading))
    }
}
