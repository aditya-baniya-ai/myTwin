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
}
