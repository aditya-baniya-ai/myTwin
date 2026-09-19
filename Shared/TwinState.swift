import Foundation

/// Today's energy, shared by the app and its Home Screen widget through an App Group, so
/// both show the same twin in the same colour at the same moment.
///
/// Only one number is shared: where today's charge started, set by the morning
/// prediction. Both sides then work out the charge at any hour with the same drain curve.
enum TwinState {
    static let appGroup = "group.com.aadityabaniyapersonalteam.myTwin"
    private static let store = UserDefaults(suiteName: appGroup)
    private static let startKey = "dayStart"
    private static let dayKey = "dayStartDate"

    /// Where the charge started on `date`'s day. An average day when the app has not made
    /// a prediction for that day yet (say, just after midnight).
    static func dayStart(on date: Date = .now) -> Double {
        guard let store, let saved = store.object(forKey: dayKey) as? Date,
              Calendar.current.isDate(saved, inSameDayAs: date) else { return DayCharge.unknownDay }
        return store.double(forKey: startKey)
    }

    static func save(dayStart: Double, on date: Date = .now) {
        store?.set(dayStart, forKey: startKey)
        store?.set(date, forKey: dayKey)
    }

    /// The energy score, 0-100, at `date`.
    static func energy(at date: Date = .now) -> Double {
        DayCharge.remaining(from: dayStart(on: date), at: date) * 100
    }
}
