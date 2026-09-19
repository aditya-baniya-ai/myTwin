import Charts
import SwiftUI

/// Your daily targets. Change them here.
enum Goals {
    static let steps = 10_000.0
    static let activeEnergy = 500.0      // kcal
    static let sleep = 8.0               // hours
    static let weight = 140.0            // lb
}

/// Today at a glance, one card per measure, in two columns.
struct ActivityGrid: View {
    let steps: Double?
    let activeEnergy: Double?
    let sleepWeek: [Double?]             // hours a night, oldest first: the last is last night
    let weights: [WeightSample]          // oldest first

    @State private var shown = false

    private static let stepColors = [Color(red: 0.35, green: 0.90, blue: 0.45), Color(red: 0.55, green: 1.00, blue: 0.75)]
    private static let moveColors = [Color(red: 1.0, green: 0.25, blue: 0.40), Color(red: 1.0, green: 0.55, blue: 0.30)]
    private static let sleepColors = [Color(red: 0.35, green: 0.55, blue: 1.00), Color(red: 0.65, green: 0.45, blue: 1.00)]
    private static let weightColors = [Color(red: 0.20, green: 0.80, blue: 0.95), Color(red: 0.45, green: 0.55, blue: 1.00)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            GlanceCard(title: "Steps", symbol: "figure.walk", tint: Self.stepColors[0],
                       value: steps.map { Int($0).formatted() } ?? "—",
                       detail: "of \(Int(Goals.steps).formatted())") {
                ring((steps ?? 0) / Goals.steps, Self.stepColors)
            }
            GlanceCard(title: "Active Energy", symbol: "flame.fill", tint: Self.moveColors[0],
                       value: activeEnergy.map { "\(Int($0)) kcal" } ?? "—",
                       detail: "of \(Int(Goals.activeEnergy)) kcal") {
                ring((activeEnergy ?? 0) / Goals.activeEnergy, Self.moveColors)
            }
            GlanceCard(title: "Sleep", symbol: "bed.double.fill", tint: Self.sleepColors[0],
                       value: sleepWeek.last.flatMap { $0 }.map { String(format: "%.1f h", $0) } ?? "—",
                       detail: "last night · goal \(Int(Goals.sleep)) h") {
                sleepBars
            }
            GlanceCard(title: "Weight", symbol: "scalemass.fill", tint: Self.weightColors[0],
                       value: weights.last.map { String(format: "%.1f lb", $0.pounds) } ?? "—",
                       detail: weightDetail) {
                ring(weightProgress, Self.weightColors, label: weights.isEmpty ? "—" : nil)
            }
        }
        .onAppear { shown = true }
    }

    // MARK: - Charts

    private func ring(_ progress: Double, _ colors: [Color], label: String? = nil) -> some View {
        Ring(progress: progress, colors: colors, width: 10, shown: shown)
            .frame(width: 70, height: 70)
            .overlay {
                Text(label ?? "\(Int(min(max(progress, 0), 1) * 100))%")
                    .font(.caption.weight(.bold))
            }
            .animation(.spring(response: 1.1, dampingFraction: 0.85), value: shown)
    }

    /// The last seven nights, last night brightest, with the goal as a dashed line.
    private var sleepBars: some View {
        Chart {
            ForEach(Array(sleepWeek.enumerated()), id: \.offset) { index, hours in
                BarMark(x: .value("Night", index), y: .value("Hours", shown ? hours ?? 0 : 0))
                    .cornerRadius(3)
                    .foregroundStyle(Self.sleepColors[0].opacity(index == sleepWeek.count - 1 ? 1 : 0.45))
            }
            RuleMark(y: .value("Goal", Goals.sleep))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(.secondary)
        }
        .chartYScale(domain: 0...10)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .animation(.spring(response: 0.8, dampingFraction: 0.8), value: shown)
    }

    // MARK: - Weight

    /// How far you've come from your first weigh-in in the window towards the target,
    /// whether you're losing or gaining.
    private var weightProgress: Double {
        guard let first = weights.first?.pounds, let latest = weights.last?.pounds else { return 0 }
        let journey = abs(first - Goals.weight)
        guard journey > 0.1 else { return abs(latest - Goals.weight) < 0.5 ? 1 : 0 }
        return min(max(1 - abs(latest - Goals.weight) / journey, 0), 1)
    }

    private var weightDetail: String {
        guard let latest = weights.last?.pounds else { return "No weigh-ins yet" }
        let left = abs(latest - Goals.weight)
        return left < 0.5 ? "At your \(Int(Goals.weight)) lb target"
                          : String(format: "%.1f lb to %d lb", left, Int(Goals.weight))
    }
}

/// One card of the grid: a title, a small chart, then the number that matters.
private struct GlanceCard<Chart: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    let value: String
    let detail: String
    @ViewBuilder let chart: () -> Chart

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
            chart()
                .frame(maxWidth: .infinity)
                .frame(height: 76)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .contentTransition(.numericText())
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .dashboardCard(padding: 14)
    }
}

#Preview("Activity grid") {
    let start = Calendar.current.date(byAdding: .day, value: -60, to: .now)!
    ActivityGrid(steps: 7_420, activeEnergy: 380,
                 sleepWeek: [6.8, 7.4, 5.9, 8.1, 7.0, 6.5, 7.2],
                 weights: (0..<9).map { WeightSample(date: start.addingTimeInterval(Double($0) * 7 * 86_400),
                                                     pounds: 158 - Double($0) * 0.7) })
        .padding()
}
