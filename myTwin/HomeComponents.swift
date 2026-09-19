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

/// One progress ring, drawn from zero when `shown` turns on.
struct Ring: View {
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

/// The last seven days at a glance: one bar per day, coloured by how that day compared
/// with your own normal. Grey means there was not enough data to judge.
struct WeekStrip: View {
    let days: [(date: Date, band: EnergyReading.Band?)]
    @State private var shown = false

    private func colors(_ band: EnergyReading.Band?) -> [Color] {
        switch band {
        case .above: [Color(red: 0.16, green: 0.84, blue: 0.58), Color(red: 0.42, green: 0.95, blue: 0.82)]
        case .normal: [Color(red: 0.32, green: 0.66, blue: 1.00), Color(red: 0.55, green: 0.52, blue: 0.98)]
        case .below: [Color(red: 1.00, green: 0.62, blue: 0.28), Color(red: 0.96, green: 0.42, blue: 0.45)]
        case nil: [Color.gray.opacity(0.35), Color.gray.opacity(0.25)]
        }
    }

    private func height(_ band: EnergyReading.Band?) -> Double {
        switch band {
        case .above: 1.0
        case .normal: 0.66
        case .below: 0.38
        case nil: 0.2
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(days.enumerated().reversed()), id: \.offset) { index, day in
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(colors: colors(day.band), startPoint: .top, endPoint: .bottom))
                        .frame(height: shown ? 54 * height(day.band) : 4)
                        .frame(maxHeight: 54, alignment: .bottom)
                    Text(day.date.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(index == 0 ? .primary : .secondary)
                }
                .animation(.spring(response: 0.6, dampingFraction: 0.75).delay(Double(index) * 0.05), value: shown)
            }
        }
        .frame(height: 78, alignment: .bottom)
        .padding(.vertical, 4)
        .onAppear { shown = true }
        .onDisappear { shown = false }
    }
}
