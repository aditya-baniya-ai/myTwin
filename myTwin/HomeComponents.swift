import SwiftUI

/// The wordmark: bold, gradient, with a glow that breathes.
struct BrandTitle: View {
    @State private var glowing = false

    static let brand = [Color(red: 0.30, green: 0.78, blue: 1.00),
                        Color(red: 0.52, green: 0.44, blue: 0.99),
                        Color(red: 0.99, green: 0.42, blue: 0.72)]

    var body: some View {
        Text("myTwin")
            .font(.system(size: 42, weight: .heavy, design: .rounded))
            .kerning(-1)
            .foregroundStyle(LinearGradient(colors: Self.brand, startPoint: .leading, endPoint: .trailing))
            .shadow(color: Self.brand[1].opacity(glowing ? 0.55 : 0.15), radius: glowing ? 20 : 8)
            .shadow(color: Self.brand[0].opacity(glowing ? 0.35 : 0.10), radius: glowing ? 30 : 10)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { glowing = true }
            }
    }
}

/// One ring of the activity dial.
private struct Ring: View {
    let progress: Double
    let colors: [Color]
    let width: CGFloat
    let shown: Bool

    var body: some View {
        ZStack {
            Circle().stroke(colors[0].opacity(0.16), lineWidth: width)
            Circle()
                .trim(from: 0, to: shown ? min(max(progress, 0), 1) : 0)
                .stroke(AngularGradient(colors: colors + [colors[0]], center: .center),
                        style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: colors[1].opacity(0.35), radius: 3)
        }
    }
}

/// Today, at a glance: move, steps and sleep as three rings.
struct ActivityRings: View {
    let energyKcal: Double?
    let steps: Double?
    let sleepHours: Double?
    @State private var shown = false

    private static let moveGoal = 500.0
    private static let stepGoal = 10_000.0
    private static let sleepGoal = 8.0

    private static let move = [Color(red: 1.0, green: 0.25, blue: 0.40), Color(red: 1.0, green: 0.55, blue: 0.30)]
    private static let step = [Color(red: 0.35, green: 0.90, blue: 0.45), Color(red: 0.55, green: 1.00, blue: 0.75)]
    private static let sleep = [Color(red: 0.35, green: 0.55, blue: 1.00), Color(red: 0.65, green: 0.45, blue: 1.00)]

    var body: some View {
        HStack(spacing: 22) {
            ZStack {
                Ring(progress: (energyKcal ?? 0) / Self.moveGoal, colors: Self.move, width: 12, shown: shown)
                    .frame(width: 124, height: 124)
                Ring(progress: (steps ?? 0) / Self.stepGoal, colors: Self.step, width: 12, shown: shown)
                    .frame(width: 90, height: 90)
                Ring(progress: (sleepHours ?? 0) / Self.sleepGoal, colors: Self.sleep, width: 12, shown: shown)
                    .frame(width: 56, height: 56)
            }
            .animation(.spring(response: 1.1, dampingFraction: 0.85), value: shown)

            VStack(alignment: .leading, spacing: 10) {
                legend("Move", value: energyKcal, goal: Self.moveGoal, unit: "kcal", colors: Self.move)
                legend("Steps", value: steps, goal: Self.stepGoal, unit: "", colors: Self.step)
                legend("Sleep", value: sleepHours, goal: Self.sleepGoal, unit: "h", colors: Self.sleep)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .onAppear { shown = true }
        .onDisappear { shown = false }
    }

    private func legend(_ name: String, value: Double?, goal: Double, unit: String, colors: [Color]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Circle()
                    .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                    .frame(width: 8, height: 8)
                Text(name).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(value.map { display($0, unit: unit) } ?? "—")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .contentTransition(.numericText())
        }
    }

    private func display(_ value: Double, unit: String) -> String {
        let number = unit == "h" ? String(format: "%.1f", value)
            : value >= 1000 ? value.formatted(.number.precision(.fractionLength(0)))
            : String(format: "%.0f", value)
        return unit.isEmpty ? number : "\(number) \(unit)"
    }
}
