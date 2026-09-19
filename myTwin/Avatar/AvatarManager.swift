import Foundation
import RealityKit

/// Which character you picked, and a cache so each model is read from disk only once.
///
/// Every view gets its own copy of the loaded model. Copies share meshes, textures and
/// animations, so a second view costs almost nothing.
@MainActor
@Observable
final class AvatarManager {
    static let shared = AvatarManager()
    private static let key = "avatarCharacterID"

    var selected: AvatarCharacter {
        didSet { UserDefaults.standard.set(selected.id, forKey: Self.key) }
    }

    @ObservationIgnored private var loads: [String: Task<LoadedAvatar, any Error>] = [:]

    private init() {
        selected = AvatarCharacter.named(UserDefaults.standard.string(forKey: Self.key))
    }

    /// A copy of the character, ready to add to a scene. Two views asking at once share
    /// one load.
    func avatar(for character: AvatarCharacter) async throws -> LoadedAvatar {
        let load = loads[character.id] ?? Task { try await LoadedAvatar.load(character) }
        loads[character.id] = load
        return try await load.value.copy()
    }
}

/// A character's model, the entity inside it that plays the animation, and its clips:
/// one looping idle per energy state plus the one-shot actions (wave, yawn, ...).
struct LoadedAvatar {
    let model: Entity
    let animated: Entity
    let clips: [String: Clip]

    struct Clip {
        let animation: AnimationResource
        let duration: TimeInterval
    }

    enum LoadError: Error { case noAnimation, noClipTable }

    /// Reads the model and cuts its single animation timeline into the named clips.
    static func load(_ character: AvatarCharacter) async throws -> LoadedAvatar {
        let model = try await Entity(named: character.id)
        guard let animated = firstAnimated(in: model),
              let timeline = animated.availableAnimations.first else { throw LoadError.noAnimation }

        guard let url = Bundle.main.url(forResource: "\(character.id).clips", withExtension: "json")
        else { throw LoadError.noClipTable }
        let table = try JSONDecoder().decode(ClipTable.self, from: Data(contentsOf: url))

        var clips: [String: Clip] = [:]
        for (name, range) in table.clips {
            let view = AnimationView(source: timeline.definition, name: name,
                                     repeatMode: range.loops ? .repeat : .none,
                                     trimStart: range.start, trimEnd: range.end)
            clips[name] = Clip(animation: try AnimationResource.generate(with: view),
                               duration: range.end - range.start)
        }
        return LoadedAvatar(model: model, animated: animated, clips: clips)
    }

    func copy() -> LoadedAvatar {
        let model = model.clone(recursive: true)
        let animated = self.animated === self.model
            ? model : model.findEntity(named: self.animated.name) ?? model
        return LoadedAvatar(model: model, animated: animated, clips: clips)
    }

    private static func firstAnimated(in entity: Entity) -> Entity? {
        if !entity.availableAnimations.isEmpty { return entity }
        for child in entity.children {
            if let found = firstAnimated(in: child) { return found }
        }
        return nil
    }

    /// Seconds from the start of the model's timeline, written by the export script.
    private struct ClipTable: Decodable {
        struct Range: Decodable { let start: TimeInterval; let end: TimeInterval; let loops: Bool }
        let clips: [String: Range]
    }
}
