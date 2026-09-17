import SwiftUI

/// A face that shows how the day is going: bright and upright when charged, heavy-eyed
/// and slumped when drained. `charge` runs 0 (exhausted) to 1 (fresh).
struct AvatarView: View {
    let charge: Double
    var size: CGFloat = 132
    var showsBatteryRing = true

    @State private var appeared = false
    @State private var breathing = false

    private var level: Double { min(max(charge, 0), 1) }

    /// Warm greens when charged, ambers in the middle, tired reds at the bottom.
    private var colors: [Color] {
        switch level {
        case 0.66...: [Color(red: 0.16, green: 0.84, blue: 0.58), Color(red: 0.42, green: 0.95, blue: 0.82)]
        case 0.33..<0.66: [Color(red: 1.00, green: 0.75, blue: 0.25), Color(red: 1.00, green: 0.58, blue: 0.35)]
        default: [Color(red: 0.95, green: 0.42, blue: 0.45), Color(red: 0.78, green: 0.40, blue: 0.62)]
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [colors[0].opacity(0.25 + 0.4 * level), .clear],
                                     center: .center, startRadius: size * 0.08, endRadius: size * 0.72))
                .blur(radius: 14)
                .scaleEffect(breathing ? 1.0 + 0.10 * level : 0.92)

            if showsBatteryRing {
                Circle().stroke(colors[0].opacity(0.15), lineWidth: size * 0.05)
                Circle()
                    .trim(from: 0, to: appeared ? level : 0)
                    .stroke(AngularGradient(colors: colors + [colors[0]], center: .center),
                            style: StrokeStyle(lineWidth: size * 0.05, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: colors[0].opacity(0.5), radius: 6)
            }

            face
                .frame(width: size * 0.62, height: size * 0.62)
                .offset(y: size * 0.03 * (1 - level))        // a slump when drained
                .rotationEffect(.degrees(6 * (1 - level)))   // and a tilt of the head
        }
        .frame(width: size, height: size)
        .scaleEffect(appeared ? 1 : 0.85)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.9, dampingFraction: 0.7), value: level)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.65)) { appeared = true }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { breathing = true }
        }
    }

    private var face: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack {
                Circle().fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))

                // Eyes: wide open when fresh, heavy lids when drained.
                HStack(spacing: width * 0.20) {
                    eye(width: width)
                    eye(width: width)
                }
                .offset(y: -height * 0.08)

                Mouth(smile: level)
                    .stroke(.white.opacity(0.92), style: StrokeStyle(lineWidth: width * 0.055, lineCap: .round))
                    .frame(width: width * 0.42, height: height * 0.16)
                    .offset(y: height * 0.20)
            }
        }
    }

    private func eye(width: CGFloat) -> some View {
        let openness = 0.35 + 0.65 * level      // never fully shut
        return ZStack(alignment: .top) {
            Capsule()
                .fill(.white.opacity(0.95))
                .frame(width: width * 0.13, height: width * 0.15 * openness)
            // A lowered lid reads as tiredness better than a smaller eye alone.
            Capsule()
                .fill(colors[0])
                .frame(width: width * 0.13, height: width * 0.15 * (1 - openness))
        }
        .frame(height: width * 0.15, alignment: .center)
    }
}

/// A mouth that curves from a frown at 0 to a smile at 1.
private struct Mouth: Shape {
    var smile: Double

    var animatableData: Double {
        get { smile }
        set { smile = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let curve = (smile - 0.5) * 2          // -1 frown … +1 smile
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control: CGPoint(x: rect.midX, y: rect.midY + curve * rect.height * 0.9))
        return path
    }
}
