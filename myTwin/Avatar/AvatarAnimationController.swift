import Foundation
import RealityKit

/// Drives one on-screen character: which idle clip loops, the actions played now and
/// then, and how the character turns when you drag it. Nothing here is SwiftUI state, so
/// none of it makes SwiftUI redraw the screen; RealityKit moves the model on its own
/// frame loop.
@MainActor
final class AvatarAnimationController {
    /// How far a finger drag turns the character.
    private let radiansPerPoint: Float = 0.012
    /// How fast a flick slows down. Higher stops sooner.
    private let friction: Float = 3.5
    /// How long one expression blends into the next.
    private let crossfade: TimeInterval = 0.6
    /// The first action comes soon after the twin appears or changes mood; later ones
    /// every so often, so it feels alive without being busy.
    private let firstAction: TimeInterval = 2.5
    private let actionGap: ClosedRange<TimeInterval> = 10...18

    private(set) var height: Float = 1
    var frameUpdates: EventSubscription?

    private var avatar: LoadedAvatar?
    private var turntable = Entity()
    private var state: AvatarEnergyState?
    private var yaw: Float = 0
    private var spin: Float = 0                  // radians per second, after a flick
    private var untilAction: TimeInterval = 0
    private var actionLeft: TimeInterval?        // counting down while an action plays

    /// Stands the character on a fresh turntable, feet at its centre, and returns the
    /// turntable for the scene. It spins around its own vertical axis.
    func stage(_ avatar: LoadedAvatar) -> Entity {
        self.avatar = avatar
        turntable = Entity()
        state = nil
        yaw = 0
        spin = 0
        let bounds = avatar.model.visualBounds(relativeTo: nil)
        avatar.model.position -= [bounds.center.x, bounds.min.y, bounds.center.z]
        height = bounds.extents.y
        turntable.addChild(avatar.model)
        return turntable
    }

    /// Blends into the idle loop for `newState`. Does nothing if it is already playing.
    func show(_ newState: AvatarEnergyState) {
        guard newState != state, let avatar, let idle = avatar.clips[newState.clipName] else { return }
        avatar.animated.playAnimation(idle.animation, transitionDuration: state == nil ? 0 : crossfade)
        state = newState
        actionLeft = nil
        untilAction = firstAction
    }

    func drag(by points: CGFloat) {
        spin = 0
        turn(by: Float(points) * radiansPerPoint)
    }

    func release(velocity pointsPerSecond: CGFloat) {
        spin = Float(pointsPerSecond) * radiansPerPoint
    }

    /// Called every frame: a flick coasts to a stop, and actions come and go.
    func advance(by seconds: TimeInterval) {
        coast(seconds)
        act(seconds)
    }

    private func coast(_ seconds: TimeInterval) {
        guard spin != 0 else { return }
        turn(by: spin * Float(seconds))
        spin *= exp(-friction * Float(seconds))
        if abs(spin) < 0.02 { spin = 0 }
    }

    /// Every so often plays one of the mood's actions, then blends back into its idle loop.
    private func act(_ seconds: TimeInterval) {
        guard let avatar, let state else { return }
        if let left = actionLeft {
            actionLeft = left - seconds
            if left - seconds <= 0, let idle = avatar.clips[state.clipName] {
                avatar.animated.playAnimation(idle.animation, transitionDuration: crossfade)
                actionLeft = nil
            }
            return
        }
        untilAction -= seconds
        guard untilAction <= 0 else { return }
        untilAction = .random(in: actionGap)
        guard let name = state.actions.randomElement(), let action = avatar.clips[name] else { return }
        avatar.animated.playAnimation(action.animation, transitionDuration: 0.35)
        actionLeft = action.duration - crossfade
    }

    private func turn(by radians: Float) {
        yaw += radians
        turntable.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
    }
}
