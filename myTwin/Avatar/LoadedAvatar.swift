import Foundation
import RealityKit

/// Dash's model, the entity inside it that plays the animation, and his clips: one
/// looping idle per energy state plus the one-shot actions (wave, yawn, ...).
struct LoadedAvatar {
    let model: Entity
    let animated: Entity
    let clips: [String: Clip]

    struct Clip {
        let animation: AnimationResource
        let duration: TimeInterval
    }

    enum LoadError: Error { case noAnimation, noClipTable }

    /// Reads Dash.usdz and cuts its single animation timeline into the clips named in
    /// Dash.clips.json. Both come from assets/Dash/scripts/export_usdz.py.
    static func load() async throws -> LoadedAvatar {
        let model = try await Entity(named: "Dash")
        guard let animated = firstAnimated(in: model),
              let timeline = animated.availableAnimations.first else { throw LoadError.noAnimation }

        guard let url = Bundle.main.url(forResource: "Dash.clips", withExtension: "json")
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
