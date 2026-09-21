import RealityKit
import SwiftUI

/// The room around Dash.
///
/// He had three lamps pointing at him and nothing else: no surroundings for his skin and
/// jacket to catch colour from, which is exactly what makes 3D look like plastic. This
/// paints a small studio — warm sky, walls in the colour of the body battery, a dark floor
/// and two softboxes — and hands it to RealityKit as the light around him. The room is
/// drawn once per mood and kept.
@MainActor
enum AvatarLighting {
    private static var rooms: [AvatarEnergyState: EnvironmentResource] = [:]

    /// The surroundings for a mood.
    static func room(for state: AvatarEnergyState) -> EnvironmentResource? {
        if let ready = rooms[state] { return ready }
        guard let picture = painted(for: state),
              let room = try? EnvironmentResource(equirectangular: picture) else { return nil }
        rooms[state] = room
        return room
    }

    /// Softens every surface of the model and points it at the room: skin that isn't
    /// glossy, wet-looking eyes, and cloth that scatters light instead of glinting.
    static func light(_ model: Entity, from room: Entity) {
        model.components.set(ImageBasedLightReceiverComponent(imageBasedLight: room))
        if var mesh = model.components[ModelComponent.self] {
            mesh.materials = mesh.materials.map { surface($0, of: model.name) }
            model.components.set(mesh)
        }
        for child in model.children { light(child, from: room) }
    }

    private static func surface(_ material: any RealityKit.Material, of part: String) -> any RealityKit.Material {
        guard var pbr = material as? PhysicallyBasedMaterial else { return material }
        let name = part.lowercased()
        if name.contains("eye") {
            pbr.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 0.08)       // wet
            pbr.clearcoat = PhysicallyBasedMaterial.Clearcoat(floatLiteral: 1)
            pbr.clearcoatRoughness = PhysicallyBasedMaterial.ClearcoatRoughness(floatLiteral: 0.03)
        } else if name.contains("body") || name.contains("head") || name.contains("skin") {
            pbr.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 0.50)       // soft, never shiny
            pbr.specular = PhysicallyBasedMaterial.Specular(floatLiteral: 0.35)
            pbr.clearcoat = PhysicallyBasedMaterial.Clearcoat(floatLiteral: 0.08)       // the faintest sheen
            pbr.clearcoatRoughness = PhysicallyBasedMaterial.ClearcoatRoughness(floatLiteral: 0.6)
        } else if name.contains("hair") {
            pbr.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 0.32)
            pbr.specular = PhysicallyBasedMaterial.Specular(floatLiteral: 0.6)
        } else if name.contains("shoe") {
            pbr.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 0.45)
            pbr.clearcoat = PhysicallyBasedMaterial.Clearcoat(floatLiteral: 0.3)
        } else {                                           // shirt, jacket, trousers
            pbr.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 0.85)
            pbr.specular = PhysicallyBasedMaterial.Specular(floatLiteral: 0.2)
        }
        return pbr
    }

    /// A 360° picture of the room, which is how RealityKit takes surroundings: sky at the
    /// top, tinted walls around the middle, dark floor at the bottom, and three soft lamps.
    private static func painted(for state: AvatarEnergyState) -> CGImage? {
        let size = CGSize(width: 1024, height: 512)
        let mood = state.glow.map { UIColor($0) }
        let picture = UIGraphicsImageRenderer(size: size).image { context in
            let canvas = context.cgContext
            let shades = [UIColor(white: 1.0, alpha: 1),                  // sky
                          blend(mood[1], with: .white, 0.55),            // upper wall
                          blend(mood[0], with: .white, 0.35),            // wall at his eye line
                          UIColor(white: 0.06, alpha: 1)]                // floor
            if let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                    colors: shades.map(\.cgColor) as CFArray,
                                    locations: [0, 0.34, 0.56, 1]) {
                canvas.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            // The softboxes, added on top of the walls the way light adds up.
            canvas.setBlendMode(.plusLighter)
            lamp(canvas, at: CGPoint(x: size.width * 0.22, y: size.height * 0.30),
                 radius: 210, colour: UIColor(red: 1, green: 0.95, blue: 0.88, alpha: 1))    // key, warm
            lamp(canvas, at: CGPoint(x: size.width * 0.72, y: size.height * 0.42),
                 radius: 170, colour: UIColor(red: 0.80, green: 0.88, blue: 1, alpha: 1))    // fill, cool
            lamp(canvas, at: CGPoint(x: size.width * 0.50, y: size.height * 0.20),
                 radius: 130, colour: .white)                                                // rim, behind him
        }
        return picture.cgImage
    }

    private static func lamp(_ canvas: CGContext, at centre: CGPoint, radius: CGFloat, colour: UIColor) {
        let stops = [colour.withAlphaComponent(0.9).cgColor, colour.withAlphaComponent(0).cgColor] as CFArray
        guard let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: stops,
                                    locations: [0, 1]) else { return }
        canvas.drawRadialGradient(glow, startCenter: centre, startRadius: 0,
                                  endCenter: centre, endRadius: radius, options: [])
    }

    private static func blend(_ colour: UIColor, with other: UIColor, _ amount: CGFloat) -> UIColor {
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        colour.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * amount, green: g1 + (g2 - g1) * amount,
                       blue: b1 + (b2 - b1) * amount, alpha: 1)
    }
}
