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
