/// How much energy the twin acts out. Scores run 0-100, the same number the home screen
/// shows as "% charged".
enum AvatarEnergyState: String, CaseIterable {
    case energetic
    case normal
    case tired
    case exhausted

    init(score: Double) {
        switch score {
        case 80...: self = .energetic
        case 55..<80: self = .normal
        case 30..<55: self = .tired
        default: self = .exhausted
        }
    }

    /// The looping idle clip that acts out this state: idle_energetic, idle_normal, ...
    var clipName: String { "idle_\(rawValue)" }

    /// Dash's rendered still for this state, in Shared/AvatarImages.xcassets.
    var stillName: String { "Dash_\(rawValue)" }

    /// One-shot actions played now and then on top of the idle loop.
    var actions: [String] {
        switch self {
        case .energetic: ["wave", "jump"]
        case .normal: ["stretch"]
        case .tired: ["yawn"]
        case .exhausted: ["doze"]
        }
    }
}
