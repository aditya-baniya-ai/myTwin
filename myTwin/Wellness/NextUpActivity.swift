import ActivityKit
import Foundation

/// Starts, updates and ends the "up next" Live Activity; the widget only draws it. There's
/// no server to push changes, so it moves on whenever the app is open and the next thing
/// changes. One at a time: the demo and your own screen take turns with it.
@MainActor
enum NextUpActivity {
    /// Shows `state`, or ends the Live Activity when there's nothing left today.
    static func show(_ state: NextUpAttributes.ContentState?) {
        let running = Activity<NextUpAttributes>.activities
        guard let state else {
            Task { for activity in running { await activity.end(nil, dismissalPolicy: .immediate) } }
            return
        }
        let content = ActivityContent(state: state, staleDate: nil)
        if let activity = running.first {
            guard activity.content.state != state else { return }
            Task { await activity.update(content) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            _ = try? Activity.request(attributes: NextUpAttributes(), content: content)
        }
    }
}
