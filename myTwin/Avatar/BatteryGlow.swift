import SwiftUI

/// The body-battery light around the twin: the whole screen's glow, the light behind the
/// character, and the platform under their feet. Colour follows the energy state; the
/// more charge is left, the brighter it glows.
extension AvatarEnergyState {
    /// Green when energetic, blue when normal, amber when tired, red when exhausted.
    var glow: [Color] {
        switch self {
        case .energetic: [Color(red: 0.16, green: 0.84, blue: 0.58), Color(red: 0.42, green: 0.95, blue: 0.82)]
        case .normal: [Color(red: 0.30, green: 0.62, blue: 1.00), Color(red: 0.45, green: 0.85, blue: 0.95)]
        case .tired: [Color(red: 1.00, green: 0.75, blue: 0.25), Color(red: 1.00, green: 0.58, blue: 0.35)]
        case .exhausted: [Color(red: 0.95, green: 0.42, blue: 0.45), Color(red: 0.78, green: 0.40, blue: 0.62)]
        }
    }
}

/// How full the body battery is, 0 to 1, from a 0-100 score.
func batteryLevel(_ energy: Double) -> Double { min(max(energy / 100, 0), 1) }

/// A dim glow when the battery is low, full brightness when it is full.
private func glowStrength(_ energy: Double) -> Double { 0.45 + 0.55 * batteryLevel(energy) }

/// The whole screen's light. It sits behind the scrolling content, so the glow stays
/// however far you scroll.
struct BatteryBackdrop: View {
    let energy: Double

    var body: some View {
        let colors = AvatarEnergyState(score: energy).glow
        let strength = glowStrength(energy)
        GeometryReader { geo in
            let reach = max(geo.size.width, geo.size.height)
            ZStack {
                Color(.systemGroupedBackground)
                LinearGradient(colors: [colors[0].opacity(0.2 * strength), colors[1].opacity(0.1 * strength),
                                        colors[0].opacity(0.16 * strength)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [colors[0].opacity(0.38 * strength), colors[1].opacity(0.12 * strength), .clear],
                               center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: reach * 0.65)
                RadialGradient(colors: [colors[1].opacity(0.26 * strength), .clear],
                               center: .bottom, startRadius: 0, endRadius: reach * 0.55)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: energy)
    }
}

/// Light coming from behind the character: a bright core at chest height, a soft aura,
/// and rays that turn slowly, so the twin looks lit rather than pasted on.
struct BatteryHalo: View {
    let energy: Double
    let size: CGFloat

    @State private var turning = false

    var body: some View {
        let colors = AvatarEnergyState(score: energy).glow
        let strength = glowStrength(energy)
        ZStack {
            AngularGradient(stops: Self.rays(colors[1].opacity(0.55 * strength),
                                             colors[0].opacity(0.28 * strength)),
                            center: .center)
                .mask(RadialGradient(colors: [.white, .white.opacity(0.45), .clear], center: .center,
                                     startRadius: size * 0.06, endRadius: size * 0.5))
                .rotationEffect(.degrees(turning ? 360 : 0))
            RadialGradient(colors: [colors[0].opacity(0.5 * strength), colors[1].opacity(0.16 * strength), .clear],
                           center: .center, startRadius: 0, endRadius: size * 0.5)
            RadialGradient(colors: [.white.opacity(0.75 * strength), colors[1].opacity(0.45 * strength), .clear],
                           center: .center, startRadius: 0, endRadius: size * 0.22)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.linear(duration: 90).repeatForever(autoreverses: false)) { turning = true }
        }
        .animation(.easeOut(duration: 0.5), value: energy)
        .allowsHitTesting(false)
    }

    /// Eighteen soft-edged rays, alternating strong and faint.
    private static func rays(_ strong: Color, _ faint: Color) -> [Gradient.Stop] {
        let count = 18
        let width = 1.0 / Double(count)
        return (0..<count).flatMap { ray -> [Gradient.Stop] in
            let start = Double(ray) * width
            return [.init(color: .clear, location: start + width * 0.2),
                    .init(color: ray.isMultiple(of: 2) ? strong : faint, location: start + width * 0.5),
                    .init(color: .clear, location: start + width * 0.8)]
        }
    }
}

/// The glowing pad the character stands on. Its rim fills with the charge, starting at
/// the front edge, and light from it spills onto the floor.
struct BatteryPlatform: View {
    let energy: Double
    let width: CGFloat

    var body: some View {
        let colors = AvatarEnergyState(score: energy).glow
        let ring = AngularGradient(colors: colors + [colors[0]], center: .center)
        let rim = Circle().trim(from: 0, to: batteryLevel(energy)).rotation(.degrees(90))
        let inset = width * 0.08
        ZStack {
            // The pad's edge: the same disc, a little lower and darker, gives it thickness.
            tilted(Circle()
                .fill(LinearGradient(colors: [colors[0].opacity(0.45), colors[1].opacity(0.2)],
                                     startPoint: .top, endPoint: .bottom))
                .padding(inset))
                .offset(y: width * 0.035)
            tilted(ZStack {
                Circle()                                // light spilling onto the floor
                    .fill(RadialGradient(colors: [colors[0].opacity(0.65), .clear], center: .center,
                                         startRadius: 0, endRadius: width * 0.62))
                    .blur(radius: width * 0.06)
                Circle()                                // the glassy top
                    .fill(LinearGradient(colors: [.white.opacity(0.35), colors[0].opacity(0.18)],
                                         startPoint: .top, endPoint: .bottom))
                    .padding(inset)
                Circle().stroke(.white.opacity(0.45), lineWidth: 1.5).padding(inset)
                Circle().stroke(colors[0].opacity(0.25), lineWidth: width * 0.03).padding(inset)
                rim.stroke(ring, style: StrokeStyle(lineWidth: width * 0.1, lineCap: .round))
                    .padding(inset)
                    .blur(radius: width * 0.06)
                rim.stroke(ring, style: StrokeStyle(lineWidth: width * 0.035, lineCap: .round))
                    .padding(inset)
                    .blur(radius: 1)
                Circle()                                // contact shadow under the feet
                    .fill(.black.opacity(0.35))
                    .frame(width: width * 0.34, height: width * 0.34)
                    .blur(radius: width * 0.04)
            })
        }
        .animation(.easeOut(duration: 0.4), value: energy)
        .allowsHitTesting(false)
    }

    /// Lays a flat drawing down on the floor, seen from just above.
    private func tilted(_ face: some View) -> some View {
        face
            .frame(width: width, height: width)
            .rotation3DEffect(.degrees(74), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
    }
}
