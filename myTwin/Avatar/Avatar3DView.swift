import RealityKit
import SwiftUI

/// Dash, live in 3D on his stage, acting out how much energy is left.
///
/// Drag sideways to spin him; a flick coasts to a stop. The camera never moves, and
/// nothing here touches the real camera or AR.
struct Avatar3DView: View {
    /// 0-100, the score the home screen shows as "% charged".
    let energy: Double

    @State private var controller = AvatarAnimationController()

    private var state: AvatarEnergyState { AvatarEnergyState(score: energy) }

    var body: some View {
        TwinStage(energy: energy) { scene }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Dash, \(state.rawValue)")
    }

    private var scene: some View {
        RealityView { content in
            let controller = self.controller
            content.camera = .virtual
            content.renderingEffects.motionBlur = .disabled
            content.renderingEffects.depthOfField = .disabled
            content.renderingEffects.cameraGrain = .disabled

            guard let avatar = try? await LoadedAvatar.load() else { return }
            content.add(controller.stage(avatar))
            content.add(Self.camera(framing: controller.height))
            for light in Self.lights(around: controller.height) {
                content.add(light)
            }
            controller.show(state)
            controller.frameUpdates = content.subscribe(to: SceneEvents.Update.self) { [weak controller] event in
                controller?.advance(by: event.deltaTime)
            }
        } update: { _ in
            controller.show(state)
        } placeholder: {
            Image(state.stillName)              // while the model loads
                .resizable()
                .scaledToFit()
        }
        .gesture(HorizontalPan(changed: controller.drag, ended: controller.release))
    }

    /// Head to toe with room to jump, looking straight ahead.
    private static func camera(framing height: Float) -> Entity {
        let camera = PerspectiveCamera()
        let lens = TwinFraming.fieldOfView
        camera.camera.fieldOfViewInDegrees = lens
        let distance = (height * TwinFraming.margin / 2) / tan(lens / 2 * .pi / 180)
        camera.position = [0, height * (1 + TwinFraming.headroom - TwinFraming.footroom) / 2, distance]
        return camera
    }

    /// Soft studio light: a warm key, a cool fill, and a rim from behind so the
    /// character reads as solid against the glow.
    private static func lights(around height: Float) -> [Entity] {
        let chest: SIMD3<Float> = [0, height * 0.55, 0]
        func light(_ intensity: Float, _ color: UIColor, from position: SIMD3<Float>) -> Entity {
            let light = DirectionalLight()
            light.light.intensity = intensity
            light.light.color = color
            light.look(at: chest, from: position, relativeTo: nil)
            return light
        }
        return [
            light(2400, UIColor(red: 1, green: 0.96, blue: 0.9, alpha: 1), from: [-1.6, 2.4, 2.4]),
            light(900, UIColor(red: 0.86, green: 0.9, blue: 1, alpha: 1), from: [2.2, 1.2, 1.8]),
            light(1800, .white, from: [0.4, 2.2, -2.6]),
        ]
    }
}

/// A pan that only starts on a sideways drag, so the list around the character still
/// scrolls up and down.
private struct HorizontalPan: UIGestureRecognizerRepresentable {
    let changed: (CGFloat) -> Void
    let ended: (CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        switch pan.state {
        case .changed:
            changed(pan.translation(in: nil).x)
            pan.setTranslation(.zero, in: nil)
        case .ended:
            ended(pan.velocity(in: nil).x)
        case .cancelled, .failed:
            ended(0)
        default:
            break
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: nil)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}
