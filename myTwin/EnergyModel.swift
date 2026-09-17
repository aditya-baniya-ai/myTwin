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
    let deviation: Double        // in points of the user's own 1-5 rating scale
    let daysOfHistory: Int
    let ratingsUsed: Int         // how many of the user's own ratings shaped this

    var headline: String {
        switch band {
        case .below: "Today looks below your normal"
        case .normal: "Today looks about normal for you"
        case .above: "Today looks better than your normal"
        }
    }

    var explanation: String {
        ratingsUsed > 0
            ? "From your sleep, and learning from \(ratingsUsed) of your own ratings."
            : "From your sleep, compared with your own last \(daysOfHistory) days."
    }
}

/// The shipped model: a ridge regression on five sleep signals, each compared with the
/// user's own recent baseline. It predicts the *direction* of a day, never an absolute
/// score, because that is all the training data supported.
///
/// Once the user has rated their own energy enough times, their personal weights are
/// blended in and gradually take over.
struct EnergyModel {
    /// The shipped weights predict readiness on a 0-10 scale; users rate 1-5, so the
    /// population part is converted before the two are mixed.
    static let userScaleRange = 4.0
    static let trainedScaleRange = 10.0

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

    /// Stable order, so personal weights always line up with the same features.
    let featureOrder: [String]

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
        self.featureOrder = target.weights.keys.sorted()
    }

    var daysNeeded: Int { file.minHistoryDays }

    /// Today's features, or nil when there is not enough history to compare against.
    /// `history` is most recent first; the first entry is today.
    func features(from history: [DaySignals]) -> [String: Double]? {
        guard let today = history.first else { return nil }
        let baseline = Array(history.dropFirst().prefix(file.baselineWindowDays))
        guard baseline.count >= file.minHistoryDays else { return nil }

        var values: [String: Double] = [:]
        for name in featureOrder {
            if let value = featureValue(name, today: today, baseline: baseline) {
                values[name] = value
            }
        }
        return values.isEmpty ? nil : values
    }

    func reading(from history: [DaySignals], diary: EnergyDiary? = nil) -> EnergyReading? {
        guard let values = features(from: history) else { return nil }
        let daysOfHistory = min(history.count - 1, file.baselineWindowDays)

        // The shipped model, converted to the scale the user rates on.
        let scale = Self.userScaleRange / Self.trainedScaleRange
        var deviation = scale * score(values, intercept: target.intercept, weights: target.weights)
        var low = scale * target.bands.low
        var high = scale * target.bands.high
        var ratingsUsed = 0

        // Their own weights, once they have rated enough days.
        if let diary, let fit = diary.personalFit(featureOrder: featureOrder) {
            let personalWeights = Dictionary(uniqueKeysWithValues: zip(featureOrder, fit.weights))
            let share = diary.personalShare

            func blended(_ day: [String: Double]) -> Double {
                let population = scale * score(day, intercept: target.intercept, weights: target.weights)
                let personal = score(day, intercept: fit.intercept, weights: personalWeights)
                return share * personal + (1 - share) * population
            }
            deviation = blended(values)

            // Bands from the spread of this person's own days. Scaling the shipped bands
            // instead would collapse them to zero, leaving no "normal" days at all.
            let past = diary.entries.map { blended($0.features) }.sorted()
            if past.count >= 6 {
                low = past[past.count / 3]
                high = past[past.count * 2 / 3]
            }
            ratingsUsed = diary.ratingCount
        }

        let band: EnergyReading.Band = deviation < low ? .below : (deviation > high ? .above : .normal)
        return EnergyReading(band: band, deviation: deviation,
                             daysOfHistory: daysOfHistory, ratingsUsed: ratingsUsed)
    }

    private func score(_ values: [String: Double], intercept: Double, weights: [String: Double]) -> Double {
        var total = intercept
        for (name, weight) in weights {
            if let value = values[name] { total += weight * value }
        }
        return total
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
