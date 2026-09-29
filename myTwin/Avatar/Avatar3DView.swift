import RealityKit
import SwiftUI

/// Dash, live in 3D on his stage, acting out how much energy is left.
///
/// Drag sideways to spin him; a flick coasts to a stop. The camera never moves, and
/// nothing here touches the real camera or AR.
struct Avatar3DView: View {
    /// 0-100, the score the home screen shows as "% charged".
    let energy: Double
    /// Set to a clip name to play it now. Changing it again replays; the showcase uses
    /// this, and the home screen leaves it alone so Dash acts on his own schedule.
    var gesture: AvatarGesture?

    @State private var controller = AvatarAnimationController()
    /// Where the last spin drag had got to, so each step is the movement since the last.
    @State private var spunTo: CGFloat = 0
    /// The model is on screen. Until then the stage stays empty rather than showing a
    /// stand-in: the old still was lit and framed differently, so Dash appeared to change
    /// character and jump to the middle the moment the real model arrived.
    @State private var ready = false

    private var state: AvatarEnergyState { AvatarEnergyState(score: energy) }

    var body: some View {
        TwinStage(energy: energy) { scene }
            .onChange(of: gesture) { _, now in
                if let now { controller.perform(now.clip) }
            }
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
            // The room he stands in, so his skin and jacket catch colour from something.
            let room = Entity()
            room.name = Self.roomName
            Self.furnish(room, for: state)
            content.add(room)
            AvatarLighting.light(avatar.model, from: room)
            content.add(controller.stage(avatar))
            controller.addGrabBox()          // so a drag on him spins, and a drag past him pages
            content.add(Self.camera(framing: controller.height))
            for light in Self.lights(around: controller.height) {
                content.add(light)
            }
            controller.show(state)
            if let gesture { controller.perform(gesture.clip) }   // asked for before he was ready
            controller.frameUpdates = content.subscribe(to: SceneEvents.Update.self) { [weak controller] event in
                controller?.advance(by: event.deltaTime)
            }
            ready = true
        } update: { content in
            controller.show(state)
            if let room = content.entities.first(where: { $0.name == Self.roomName }) {
                Self.furnish(room, for: state)      // the room takes the battery's colour
            }
        } placeholder: {
            Color.clear                         // his platform and glow are already there
        }
        .opacity(ready ? 1 : 0)
        .animation(.easeIn(duration: 0.45), value: ready)
        // Targeted at Dash himself: a drag on him spins him, a drag anywhere else is left
        // for the page swipe.
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { drag in
                    let step = drag.gestureValue.translation.width - spunTo
                    spunTo = drag.gestureValue.translation.width
                    controller.drag(by: step)
                }
                .onEnded { drag in
                    spunTo = 0
                    controller.release(velocity: drag.gestureValue.velocity.width)
                }
        )
    }

    private static let roomName = "Room"

    private static func furnish(_ room: Entity, for state: AvatarEnergyState) {
        guard let light = AvatarLighting.room(for: state) else { return }
        room.components.set(ImageBasedLightComponent(source: .single(light), intensityExponent: 1.3))
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
            light(1800, UIColor(red: 1, green: 0.96, blue: 0.9, alpha: 1), from: [-1.6, 2.4, 2.4]),
            light(550, UIColor(red: 0.86, green: 0.9, blue: 1, alpha: 1), from: [2.2, 1.2, 1.8]),
            light(1300, .white, from: [0.4, 2.2, -2.6]),
        ]
    }
}

/// A pan that only starts on a sideways drag, so the page around it still scrolls up and
/// down. Used to spin Dash and to swipe suggestions.
struct HorizontalPan: UIGestureRecognizerRepresentable {
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
            // Sideways and meant: a finger resting on Dash always drifts a little, and
            // that drift used to cancel holding him down to talk.
            return abs(velocity.x) > abs(velocity.y) && abs(velocity.x) > 120
        }
    }
}
