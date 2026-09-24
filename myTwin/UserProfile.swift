import Foundation

/// The user's name and age, saved locally so the app only asks once.
/// Stored in UserDefaults — no server, no account needed.
struct UserProfile {
    private static let nameKey = "userProfile.name"
    private static let ageKey  = "userProfile.age"

    /// The name the user entered on the welcome screen.
    var name: String {
        get { UserDefaults.standard.string(forKey: Self.nameKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.nameKey) }
    }

    /// The age the user entered on the welcome screen.
    var age: Int {
        get { UserDefaults.standard.integer(forKey: Self.ageKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.ageKey) }
    }

    /// True once the user has filled in both fields.
    var isComplete: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && age > 0 }

    /// Just the first word of the name, for greetings.
    var firstName: String {
        let first = name.trimmingCharacters(in: .whitespaces)
                        .components(separatedBy: " ").first ?? name
        return first.isEmpty ? "there" : first
    }
}
