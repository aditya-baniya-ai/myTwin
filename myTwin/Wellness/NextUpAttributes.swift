import ActivityKit
import Foundation

/// What the Lock Screen and Dynamic Island show while the day is on: the next thing on
/// your calendar or plan, when it starts, and how much energy you'll likely have for it.
/// Shared by the app, which starts and updates it, and the widget, which draws it.
struct NextUpAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let title: String
        let start: Date
        /// The forecast charge when it starts, 0-100. Nil without a forecast (Pro).
        var charge: Double?
    }
}
