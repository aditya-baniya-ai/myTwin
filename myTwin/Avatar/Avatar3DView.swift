import RealityKit
import SwiftUI

/// The character, live in 3D. The home screen and the picker both use this view, so
/// framing, lighting and animation are decided in one place.
///
/// Drag sideways to spin the character; a flick coasts to a stop. The camera never
/// moves, and nothing here touches the real camera or AR.
struct Avatar3DView: View {
    let character: AvatarCharacter
    /// 0-100, the score the home screen shows as "% charged".
    let energy: Double
    /// Off while another 3D preview is on screen: shows the rendered still instead, so
    /// only one scene is ever drawing.
    var isLive = true

    @State private var controller = AvatarAnimationController()

    /// The iOS Simulator only ever draws the first 3D scene an app creates; phones draw
    /// every one (developer.apple.com/forums/thread/786509). On the Simulator the home
    /// twin therefore stays live and the picker shows stills, rather than a blank space.
    #if targetEnvironment(simulator)
    static let drawsOnlyFirstScene = true
    #else
    static let drawsOnlyFirstScene = false
    #endif

    /// The lens the stills were rendered with, so the placeholder and the live view match.
    private static let fieldOfView: Float = 30
    /// Air above the head and below the feet.
    private static let margin: Float = 1.12
    /// Extra room under the character for the platform, as a share of the 3D view's height.
    private static let platformRoom: CGFloat = 0.12

    private var state: AvatarEnergyState { AvatarEnergyState(score: energy) }

    /// The light, the platform and the character share one layout: the 3D view (or its
    /// still) fills the top, and the platform sits where the framing puts the feet.
    var body: some View {
        GeometryReader { geo in
            let stage = geo.size.height / (1 + Self.platformRoom)
            let figure = stage / CGFloat(Self.margin)          // the character's height on screen
            let feet = stage * (0.5 + 0.5 / CGFloat(Self.margin))
            ZStack(alignment: .top) {
                // No wider than the view: the light fades out exactly at its edges, because a
                // list clips each row to its bounds.
                BatteryHalo(energy: energy, size: min(figure * 1.05, geo.size.width))
                    .position(x: geo.size.width / 2, y: feet - figure * 0.6)
                BatteryPlatform(energy: energy, width: figure * 0.74)
                    .position(x: geo.size.width / 2, y: feet)
                Group { if isLive { scene } else { still } }
                    .frame(width: geo.size.width, height: stage)
            }
        }
        // Only when the scene is swapped for a still. A list scrolling the view off screen
        // keeps the scene and never rebuilds it, so letting go there would lose the twin.
        .onChange(of: isLive) { _, live in
            if !live { controller.stop() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(character.name), \(state.rawValue)")
    }

    private var still: some View {
        Image(character.stillName(for: state))
            .resizable()
            .scaledToFit()
    }

    private var scene: some View {
        RealityView { content in
            let controller = self.controller
            content.camera = .virtual
            content.renderingEffects.motionBlur = .disabled
            content.renderingEffects.depthOfField = .disabled
            content.renderingEffects.cameraGrain = .disabled

            guard let avatar = try? await AvatarManager.shared.avatar(for: character) else { return }
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
            still
        }
        .gesture(HorizontalPan(changed: controller.drag, ended: controller.release))
        .id(character)
    }

    /// Head to toe, looking straight at the character's middle.
    private static func camera(framing height: Float) -> Entity {
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = fieldOfView
        let distance = (height * margin / 2) / tan(fieldOfView / 2 * .pi / 180)
        camera.position = [0, height / 2, distance]
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
