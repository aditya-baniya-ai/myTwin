/// A character you can pick.
///
/// Each one ships as `<id>.usdz` (the rigged model with its four idle clips on one
/// timeline), `<id>.clips.json` (where each clip starts and ends), and one rendered still
/// per energy state for places where a live 3D scene would waste battery: picker cells,
/// the Home Screen widget, and the moment before the model has loaded.
/// `assets/<id>/scripts/export_usdz.py` produces all three from the Blender file.
struct AvatarCharacter: Identifiable, Hashable {
    let id: String
    let name: String

    static let dash = AvatarCharacter(id: "Dash", name: "Dash")
    static let all: [AvatarCharacter] = [.dash]

    /// Falls back to Dash, so a saved choice that no longer exists still shows someone.
    static func named(_ id: String?) -> AvatarCharacter {
        all.first { $0.id == id } ?? .dash
    }

    func stillName(for state: AvatarEnergyState) -> String { "\(id)_\(state.rawValue)" }
}
