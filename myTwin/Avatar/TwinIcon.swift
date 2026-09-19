import UIKit

/// Keeps the Home Screen icon in the twin's current mood.
///
/// iOS lets an app change its icon only while it is open, and shows a short notice each
/// time it does, so this changes the icon only when the mood actually changes. The blue
/// (normal) icon is the main one; the other moods are alternates in Assets.xcassets.
@MainActor
enum TwinIcon {
    private static var wanted: String?
    private static var working = false

    static func show(_ mood: AvatarEnergyState) {
        wanted = mood == .normal ? nil : "AppIcon-\(mood.rawValue.capitalized)"
        guard UIApplication.shared.supportsAlternateIcons, !working else { return }
        working = true
        Task {
            await apply()
            working = false
        }
    }

    /// Keeps asking until the icon matches the latest mood. iOS refuses ("resource
    /// temporarily unavailable") while the app is still coming to the front, so it waits a
    /// moment before each try.
    private static func apply() async {
        let app = UIApplication.shared
        for _ in 0..<5 {
            guard app.alternateIconName != wanted else { return }
            try? await Task.sleep(for: .seconds(1))
            guard app.applicationState == .active else { return }
            try? await app.setAlternateIconName(wanted)
        }
    }
}
