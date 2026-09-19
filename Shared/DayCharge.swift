import Foundation

/// How much of a day's energy is left at each hour, measured from real check-ins and
/// stored beside the model. The app and the Home Screen widget read the same curve, so
/// the twin never shows two different numbers in two places.
enum DayCharge {
    /// Where a day starts before the clock drains it, when nothing is known about it:
    /// neither cheerful nor gloomy.
    static let unknownDay = 0.85

    /// The charge left at `date`, 0 to 1.
    static func remaining(from start: Double, at date: Date = .now) -> Double {
        let hour = Calendar.current.component(.hour, from: date)
        let left = curve.indices.contains(hour) ? curve[hour] : 0.75
        return min(max(start * left, 0), 1)
    }

    private static let curve: [Double] = {
        guard let url = Bundle.main.url(forResource: "energy_model", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        return file["hourly_charge"] as? [Double] ?? []
    }()
}

/// One point of the day's energy forecast.
struct EnergyPoint: Identifiable {
    let date: Date
    let charge: Double          // 0 to 1
    var id: Date { date }
}

extension DayCharge {
    /// The model's forecast for the rest of the day: now, then the top of each hour up to
    /// `end`, at most `hours` ahead.
    static func forecast(from start: Double, now: Date = .now, until end: Date, hours: Int = 12) -> [EnergyPoint] {
        let calendar = Calendar.current
        let limit = min(end, now.addingTimeInterval(TimeInterval(hours) * 3600))
        var points = [EnergyPoint(date: now, charge: remaining(from: start, at: now))]
        var next = calendar.nextDate(after: now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime)
        while let hour = next, hour <= limit {
            points.append(EnergyPoint(date: hour, charge: remaining(from: start, at: hour)))
            next = calendar.date(byAdding: .hour, value: 1, to: hour)
        }
        return points
    }
}
