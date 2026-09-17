import SwiftUI

/// The signals myTwin looks for, in the order they matter for predicting energy.
enum HealthSignal {
    static let all: [(name: String, symbol: String, essential: Bool)] = [
        ("Sleep", "bed.double.fill", true),
        ("Resting heart rate", "heart.fill", true),
        ("Heart rate variability", "waveform.path.ecg", false),
        ("Steps", "figure.walk", false),
        ("Active energy", "flame.fill", false),
    ]
}

/// One signal, drawn as a bar that fills when the screen appears.
struct CoverageBar: View {
    let name: String
    let symbol: String
    let days: Int
    let total: Int
    let essential: Bool
    let shown: Bool
    let delay: Double

    private var fraction: Double { total > 0 ? min(Double(days) / Double(total), 1) : 0 }

    private var colors: [Color] {
        switch days {
        case 0: [.gray.opacity(0.5), .gray]
        case ..<14: [.orange.opacity(0.6), .orange]
        case ..<60: [.yellow.opacity(0.6), .green]
        default: [.green.opacity(0.6), .mint]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(colors.last ?? .green)
                    .frame(width: 20)
                    .symbolEffect(.bounce, value: shown)
                Text(name)
                    .font(.subheadline)
                if essential && days == 0 {
                    Text("needed")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red.opacity(0.15), in: Capsule())
                        .foregroundStyle(.red)
                }
                Spacer()
                Text(days == 0 ? "none" : "\(days) days")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.tertiarySystemFill))
                    Capsule()
                        .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                        .frame(width: geometry.size.width * (shown ? fraction : 0))
                }
            }
            .frame(height: 10)
        }
        .padding(.vertical, 2)
        .animation(.spring(response: 0.75, dampingFraction: 0.8).delay(delay), value: shown)
    }
}

/// The whole section: one bar per signal, plus a plain-language verdict.
struct CoverageSection: View {
    let coverage: [String: Int]
    let windowDays: Int
    @State private var shown = false

    private var canPredict: Bool {
        (coverage["Sleep"] ?? 0) > 0 && (coverage["Resting heart rate"] ?? 0) > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(HealthSignal.all.enumerated()), id: \.element.name) { index, signal in
                CoverageBar(name: signal.name, symbol: signal.symbol,
                            days: coverage[signal.name] ?? 0, total: windowDays,
                            essential: signal.essential, shown: shown,
                            delay: Double(index) * 0.08)
            }

            if !coverage.isEmpty {
                Text(verdict)
                    .font(.footnote)
                    .foregroundStyle(canPredict ? Color.secondary : Color.red)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 4)
        .onAppear { shown = true }
        .onDisappear { shown = false }
    }

    private var verdict: String {
        let sleep = coverage["Sleep"] ?? 0
        if sleep == 0 {
            return "No sleep data in the last \(windowDays) days. myTwin needs sleep from a watch or a sleep app before it can judge your energy."
        }
        if (coverage["Resting heart rate"] ?? 0) == 0 {
            return "Sleep is there, but no resting heart rate. Predictions will be weaker without it."
        }
        return sleep >= 14
            ? "Enough sleep history to compare today with your normal."
            : "Sleep data is thin: \(sleep) days so far, about 14 makes the comparison reliable."
    }
}
