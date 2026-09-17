import Foundation

/// One day of the signals the model uses, as read from HealthKit.
struct DaySignals {
    let date: Date
    var asleepMinutes: Double?
    var efficiency: Double?      // percent, minutes asleep / minutes in bed
    var deepMinutes: Double?
    var remMinutes: Double?
    var restingHR: Double?
}

/// How today compares with this person's own recent normal.
struct EnergyReading {
    enum Band { case below, normal, above }

    let band: Band
    let deviation: Double        // in points of the training scale, e.g. readiness 0-10
    let daysOfHistory: Int

    var headline: String {
        switch band {
        case .below: "Today looks below your normal"
        case .normal: "Today looks about normal for you"
        case .above: "Today looks better than your normal"
        }
    }
}

/// The shipped model: a ridge regression on five sleep signals, each compared with the
/// user's own recent baseline. It predicts the *direction* of a day, never an absolute
/// score, because that is all the training data supported.
struct EnergyModel {
    private struct File: Decodable {
        let baselineWindowDays: Int
        let minHistoryDays: Int
        let targets: [String: Target]
    }

    private struct Target: Decodable {
        let intercept: Double
        let weights: [String: Double]
        let bands: Bands
    }

    private struct Bands: Decodable {
        let low: Double
        let high: Double
    }

    private let file: File
    private let target: Target

    /// Uses readiness: it had the most day-to-day variation to predict.
    init?(targetName: String = "readiness") {
        guard let url = Bundle.main.url(forResource: "energy_model", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let file = try? decoder.decode(File.self, from: data),
              let target = file.targets[targetName] else { return nil }
        self.file = file
        self.target = target
    }

    var daysNeeded: Int { file.minHistoryDays }

    /// `history` is most recent first; the first entry is today.
    func reading(from history: [DaySignals]) -> EnergyReading? {
        guard let today = history.first else { return nil }
        let baseline = Array(history.dropFirst().prefix(file.baselineWindowDays))
        guard baseline.count >= file.minHistoryDays else { return nil }

        var score = target.intercept
        for (name, weight) in target.weights {
            guard let value = featureValue(name, today: today, baseline: baseline) else { continue }
            score += weight * value
        }

        let band: EnergyReading.Band =
            score < target.bands.low ? .below : (score > target.bands.high ? .above : .normal)
        return EnergyReading(band: band, deviation: score, daysOfHistory: baseline.count)
    }

    /// Features ending in `_z` are "how far today sits from your own normal", in standard
    /// deviations. `efficiency` is used as a plain percentage, matching the training code.
    private func featureValue(_ name: String, today: DaySignals, baseline: [DaySignals]) -> Double? {
        switch name {
        case "efficiency": return today.efficiency
        case "asleep_z": return zScore(\.asleepMinutes, today, baseline)
        case "deep_z": return zScore(\.deepMinutes, today, baseline)
        case "rem_z": return zScore(\.remMinutes, today, baseline)
        case "resting_heart_rate_z": return zScore(\.restingHR, today, baseline)
        default: return nil
        }
    }

    private func zScore(_ key: KeyPath<DaySignals, Double?>,
                        _ today: DaySignals, _ baseline: [DaySignals]) -> Double? {
        guard let value = today[keyPath: key] else { return nil }
        let past = baseline.compactMap { $0[keyPath: key] }
        guard past.count >= 3 else { return nil }

        let mean = past.reduce(0, +) / Double(past.count)
        let variance = past.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(past.count - 1)
        let sd = variance.squareRoot()
        guard sd > 0.0001 else { return nil }  // no variation: nothing to compare against
        return (value - mean) / sd
    }
}
