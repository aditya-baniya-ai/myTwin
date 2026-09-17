import SwiftUI

/// A character you pick, drawn with layered shapes and gradients so it reads as solid
/// rather than flat. Original art: no likeness of any game character.
struct AvatarStyle: Identifiable, Equatable {
    let id: String
    let name: String
    let skin: Color
    let hair: Color
    let outfit: Color
    let trousers: Color
    let accessory: Accessory

    enum Accessory: Equatable { case none, cap, headphones, beanie }

    static let all: [AvatarStyle] = [
        .init(id: "dash", name: "Dash", skin: Color(red: 0.93, green: 0.76, blue: 0.62),
              hair: Color(red: 0.25, green: 0.17, blue: 0.14), outfit: Color(red: 0.98, green: 0.85, blue: 0.30),
              trousers: Color(red: 0.32, green: 0.52, blue: 0.88), accessory: .cap),
        .init(id: "nova", name: "Nova", skin: Color(red: 0.55, green: 0.39, blue: 0.29),
              hair: Color(red: 0.12, green: 0.10, blue: 0.12), outfit: Color(red: 0.45, green: 0.40, blue: 0.95),
              trousers: Color(red: 0.20, green: 0.22, blue: 0.30), accessory: .headphones),
        .init(id: "pip", name: "Pip", skin: Color(red: 0.98, green: 0.84, blue: 0.72),
              hair: Color(red: 0.90, green: 0.55, blue: 0.22), outfit: Color(red: 0.95, green: 0.42, blue: 0.52),
              trousers: Color(red: 0.36, green: 0.36, blue: 0.42), accessory: .none),
        .init(id: "kai", name: "Kai", skin: Color(red: 0.78, green: 0.58, blue: 0.42),
              hair: Color(red: 0.16, green: 0.14, blue: 0.13), outfit: Color(red: 0.20, green: 0.78, blue: 0.62),
              trousers: Color(red: 0.24, green: 0.30, blue: 0.44), accessory: .beanie),
        .init(id: "sol", name: "Sol", skin: Color(red: 0.46, green: 0.32, blue: 0.24),
              hair: Color(red: 0.20, green: 0.15, blue: 0.12), outfit: Color(red: 1.00, green: 0.62, blue: 0.20),
              trousers: Color(red: 0.30, green: 0.34, blue: 0.40), accessory: .cap),
        .init(id: "wren", name: "Wren", skin: Color(red: 0.96, green: 0.80, blue: 0.68),
              hair: Color(red: 0.55, green: 0.32, blue: 0.62), outfit: Color(red: 0.35, green: 0.70, blue: 0.95),
              trousers: Color(red: 0.22, green: 0.24, blue: 0.32), accessory: .none),
    ]

    static func named(_ id: String?) -> AvatarStyle { all.first { $0.id == id } ?? all[0] }
}

/// The character, reacting to how much energy is left. `charge` runs 0 to 1.
struct AvatarView: View {
    let charge: Double
    var style: AvatarStyle = .all[0]
    var size: CGFloat = 150
    var showsBatteryRing = true

    @State private var appeared = false
    @State private var breathing = false

    private var level: Double { min(max(charge, 0), 1) }

    private var mood: [Color] {
        switch level {
        case 0.66...: [Color(red: 0.16, green: 0.84, blue: 0.58), Color(red: 0.42, green: 0.95, blue: 0.82)]
        case 0.33..<0.66: [Color(red: 1.00, green: 0.75, blue: 0.25), Color(red: 1.00, green: 0.58, blue: 0.35)]
        default: [Color(red: 0.95, green: 0.42, blue: 0.45), Color(red: 0.78, green: 0.40, blue: 0.62)]
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [mood[0].opacity(0.22 + 0.38 * level), .clear],
                                     center: .center, startRadius: size * 0.06, endRadius: size * 0.7))
                .blur(radius: 12)
                .scaleEffect(breathing ? 1.0 + 0.08 * level : 0.94)

            if showsBatteryRing {
                Circle().stroke(mood[0].opacity(0.14), lineWidth: size * 0.042)
                Circle()
                    .trim(from: 0, to: appeared ? level : 0)
                    .stroke(AngularGradient(colors: mood + [mood[0]], center: .center),
                            style: StrokeStyle(lineWidth: size * 0.042, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: mood[0].opacity(0.45), radius: 5)
            }

            character
                .frame(width: size * 0.66, height: size * 0.86)
                .offset(y: size * 0.035 * (1 - level))     // slumps when spent
                .rotationEffect(.degrees(5 * (1 - level)), anchor: .bottom)
                .offset(y: breathing ? -size * 0.012 : 0)
        }
        .frame(width: size, height: size)
        .scaleEffect(appeared ? 1 : 0.85)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.9, dampingFraction: 0.72), value: level)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.65)) { appeared = true }
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { breathing = true }
        }
    }

    // MARK: - The character, built from the feet up

    private var character: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                legsAndShoes(w: w, h: h)
                torso(w: w, h: h)
                head(w: w, h: h)
            }
            .shadow(color: .black.opacity(0.18), radius: w * 0.05, y: h * 0.02)
        }
    }

    private func legsAndShoes(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            ForEach([-1.0, 1.0], id: \.self) { side in
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: w * 0.09)
                        .fill(LinearGradient(colors: [style.trousers, style.trousers.opacity(0.75)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: w * 0.19, height: h * 0.26)
                    Capsule()
                        .fill(LinearGradient(colors: [.white, Color(white: 0.85)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: w * 0.24, height: h * 0.075)
                        .overlay(alignment: .bottom) {
                            Capsule().fill(mood[0]).frame(height: h * 0.022)
                        }
                }
                .offset(x: side * w * 0.13, y: h * 0.30)
            }
        }
    }

    private func torso(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            // arms behind the jacket
            ForEach([-1.0, 1.0], id: \.self) { side in
                Capsule()
                    .fill(LinearGradient(colors: [style.outfit, style.outfit.opacity(0.8)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: w * 0.13, height: h * 0.27)
                    .rotationEffect(.degrees(side * (8 + 6 * (1 - level))))
                    .offset(x: side * w * 0.27, y: h * 0.06)
            }
            RoundedRectangle(cornerRadius: w * 0.16)
                .fill(LinearGradient(colors: [style.outfit, style.outfit.opacity(0.78)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: w * 0.5, height: h * 0.3)
                .overlay {
                    RoundedRectangle(cornerRadius: w * 0.06)
                        .fill(.white.opacity(0.75))
                        .frame(width: w * 0.14, height: h * 0.26)   // shirt showing through
                }
                .offset(y: h * 0.05)
        }
    }

    private func head(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [style.skin, style.skin.opacity(0.82)],
                                     center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: w * 0.4))
                .frame(width: w * 0.58, height: w * 0.58)

            hairOrHat(w: w)

            HStack(spacing: w * 0.075) {
                eye(w: w)
                eye(w: w)
            }
            .offset(y: -w * 0.02)

            Mouth(smile: level)
                .stroke(Color(red: 0.35, green: 0.2, blue: 0.18),
                        style: StrokeStyle(lineWidth: w * 0.022, lineCap: .round))
                .frame(width: w * 0.16, height: w * 0.07)
                .offset(y: w * 0.12)
        }
        .offset(y: -h * 0.22)
    }

    @ViewBuilder private func hairOrHat(w: CGFloat) -> some View {
        switch style.accessory {
        case .cap:
            ZStack {
                Circle().trim(from: 0.5, to: 1).fill(style.outfit)
                    .frame(width: w * 0.60, height: w * 0.60)
                Capsule().fill(style.outfit.opacity(0.9))
                    .frame(width: w * 0.42, height: w * 0.07)
                    .offset(x: w * 0.2, y: -w * 0.05)
            }
            .offset(y: -w * 0.13)
        case .beanie:
            Circle().trim(from: 0.5, to: 1).fill(style.hair.opacity(0.9))
                .frame(width: w * 0.62, height: w * 0.62)
                .overlay(alignment: .bottom) { Capsule().fill(style.outfit).frame(height: w * 0.06) }
                .offset(y: -w * 0.14)
        case .headphones:
            ZStack {
                Circle().trim(from: 0.5, to: 1).fill(style.hair)
                    .frame(width: w * 0.60, height: w * 0.60)
                Circle().trim(from: 0.5, to: 1)
                    .stroke(mood[0], lineWidth: w * 0.035)
                    .frame(width: w * 0.6, height: w * 0.6)
                ForEach([-1.0, 1.0], id: \.self) { side in
                    Capsule().fill(mood[0]).frame(width: w * 0.08, height: w * 0.13)
                        .offset(x: side * w * 0.28, y: w * 0.04)
                }
            }
            .offset(y: -w * 0.13)
        case .none:
            Circle().trim(from: 0.5, to: 1).fill(style.hair)
                .frame(width: w * 0.60, height: w * 0.60)
                .offset(y: -w * 0.15)
        }
    }

    private func eye(w: CGFloat) -> some View {
        let openness = 0.3 + 0.7 * level
        return ZStack(alignment: .top) {
            Capsule().fill(.white)
                .frame(width: w * 0.085, height: w * 0.1 * openness)
                .overlay(alignment: .center) {
                    Circle().fill(Color(red: 0.2, green: 0.15, blue: 0.14))
                        .frame(width: w * 0.05 * openness, height: w * 0.05 * openness)
                        .overlay(alignment: .topTrailing) {
                            Circle().fill(.white).frame(width: w * 0.015, height: w * 0.015)
                        }
                }
            Capsule().fill(style.skin)                       // eyelid
                .frame(width: w * 0.09, height: w * 0.1 * (1 - openness))
        }
        .frame(height: w * 0.1, alignment: .center)
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
        let curve = (smile - 0.5) * 2
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY),
                          control: CGPoint(x: rect.midX, y: rect.midY + curve * rect.height * 1.6))
        return path
    }
}
