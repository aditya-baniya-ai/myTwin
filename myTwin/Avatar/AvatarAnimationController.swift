import Foundation
import RealityKit

/// Drives one on-screen character: which idle clip loops, and how the character turns
/// when you drag it. Nothing here is SwiftUI state, so dragging and coasting never make
/// SwiftUI redraw the screen; RealityKit moves the model on its own frame loop.
@MainActor
final class AvatarAnimationController {
    /// How far a finger drag turns the character.
    private let radiansPerPoint: Float = 0.012
    /// How fast a flick slows down. Higher stops sooner.
    private let friction: Float = 3.5
    /// How long one expression blends into the next.
    private let crossfade: TimeInterval = 0.6

    private(set) var height: Float = 1
    var frameUpdates: EventSubscription?

    private var avatar: LoadedAvatar?
    private var turntable = Entity()
    private var state: AvatarEnergyState?
    private var yaw: Float = 0
    private var spin: Float = 0                  // radians per second, after a flick

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

    /// Lets go of the scene when its view leaves the screen, so RealityKit can free it
    /// and the per-frame callback stops costing battery.
    func stop() {
        frameUpdates?.cancel()
        frameUpdates = nil
        turntable.removeFromParent()
        avatar = nil
        state = nil
    }

    /// Blends into the clip for `newState`. Does nothing if that clip is already playing.
    func show(_ newState: AvatarEnergyState) {
        guard newState != state, let avatar, let clip = avatar.clips[newState] else { return }
        avatar.animated.playAnimation(clip, transitionDuration: state == nil ? 0 : crossfade)
        state = newState
    }

    func drag(by points: CGFloat) {
        spin = 0
        turn(by: Float(points) * radiansPerPoint)
    }

    func release(velocity pointsPerSecond: CGFloat) {
        spin = Float(pointsPerSecond) * radiansPerPoint
    }

    /// Called every frame, so a flick coasts to a stop instead of halting dead.
    func advance(by seconds: TimeInterval) {
        guard spin != 0 else { return }
        turn(by: spin * Float(seconds))
        spin *= exp(-friction * Float(seconds))
        if abs(spin) < 0.02 { spin = 0 }
    }

    private func turn(by radians: Float) {
        yaw += radians
        turntable.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
    }
}
