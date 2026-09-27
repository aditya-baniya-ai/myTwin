import Charts
import SwiftUI

/// Today at a glance, one card per measure, in two columns.
struct ActivityGrid: View {
    let steps: Double?
    let activeEnergy: Double?
    let sleepWeek: [Double?]             // hours a night, oldest first: the last is last night
    let weights: [WeightSample]          // oldest first
    /// Shows a + on the Weight card that calls this.
    var preferences: PlanningPreferences = .load()
    var addWeight: (() -> Void)?

    @State private var shown = false

    private static let stepColors = [Color(red: 0.35, green: 0.90, blue: 0.45), Color(red: 0.55, green: 1.00, blue: 0.75)]
    private static let moveColors = [Color(red: 1.0, green: 0.25, blue: 0.40), Color(red: 1.0, green: 0.55, blue: 0.30)]
    private static let sleepColors = [Color(red: 0.35, green: 0.55, blue: 1.00), Color(red: 0.65, green: 0.45, blue: 1.00)]
    private static let weightColors = [Color(red: 0.20, green: 0.80, blue: 0.95), Color(red: 0.45, green: 0.55, blue: 1.00)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            GlanceCard(title: "Steps", symbol: "figure.walk", tint: Self.stepColors[0],
                       value: steps.map { Int($0).formatted() } ?? "—",
                       detail: preferences.stepGoal.map { "of \(Int($0).formatted())" } ?? "No target set") {
                ring(preferences.stepGoal.map { (steps ?? 0) / max($0, 1) } ?? 0, Self.stepColors, label: preferences.stepGoal == nil ? "—" : nil)
            }
            GlanceCard(title: "Active Energy", symbol: "flame.fill", tint: Self.moveColors[0],
                       value: activeEnergy.map { "\(Int($0)) kcal" } ?? "—",
                       detail: preferences.activeEnergyGoal.map { "of \(Int($0)) kcal" } ?? "No target set") {
                ring(preferences.activeEnergyGoal.map { (activeEnergy ?? 0) / max($0, 1) } ?? 0, Self.moveColors, label: preferences.activeEnergyGoal == nil ? "—" : nil)
            }
            GlanceCard(title: "Sleep", symbol: "bed.double.fill", tint: Self.sleepColors[0],
                       value: sleepWeek.last.flatMap { $0 }.map { String(format: "%.1f h", $0) } ?? "—",
                       detail: "last night · goal \(Int(preferences.sleepGoal)) h") {
                sleepBars
            }
            GlanceCard(title: "Weight", symbol: "scalemass.fill", tint: Self.weightColors[0],
                       value: weights.last.map { String(format: "%.1f lb", $0.pounds) } ?? "—",
                       detail: weightDetail, action: addWeight) {
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
            RuleMark(y: .value("Goal", preferences.sleepGoal))
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
        guard let goal = preferences.weightGoal, let first = weights.first?.pounds, let latest = weights.last?.pounds else { return 0 }
        let journey = abs(first - goal)
        guard journey > 0.1 else { return abs(latest - goal) < 0.5 ? 1 : 0 }
        return min(max(1 - abs(latest - goal) / journey, 0), 1)
    }

    private var weightDetail: String {
        guard let latest = weights.last?.pounds else { return "No weigh-ins yet" }
        guard let goal = preferences.weightGoal else { return "No weight target set" }
        let left = abs(latest - goal)
        return left < 0.5 ? "At your \(Int(goal)) lb target"
                          : String(format: "%.1f lb to %d lb", left, Int(goal))
    }
}

/// One card of the grid: a title, a small chart, then the number that matters.
private struct GlanceCard<Chart: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    let value: String
    let detail: String
    /// When set, a + in the corner calls it.
    var action: (() -> Void)? = nil
    @ViewBuilder let chart: () -> Chart

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let action {
                    Button("Log \(title.lowercased())", systemImage: "plus.circle.fill", action: action)
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(tint)
                }
            }
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

/// Log this morning's weigh-in. It's saved to Apple Health, so the card and any other app
/// that reads weight see it.
struct LogWeightSheet: View {
    let last: Double?
    var goal: Double? = nil
    let save: (Double) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var problem: String?
    @State private var saving = false
    @FocusState private var focused: Bool

    /// Accepts "152.4" and "152,4".
    private var pounds: Double? {
        Double(text.replacingOccurrences(of: ",", with: ".")).flatMap { (50...700).contains($0) ? $0 : nil }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    TextField("0.0", text: $text)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.trailing)
                        .fixedSize()
                        .focused($focused)
                    Text("lb").font(.title2.weight(.semibold)).foregroundStyle(.secondary)
                }
                if let goal {
                    Text("Your target: \(Int(goal)) lb").font(.subheadline).foregroundStyle(.secondary)
                }
                if let problem {
                    Text(problem).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Log weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store() }.disabled(pounds == nil || saving)
                }
            }
            .onAppear {
                text = last.map { String(format: "%.1f", $0) } ?? ""
                focused = true
            }
        }
        .presentationDetents([.height(260)])
    }

    private func store() {
        guard let pounds else { return }
        saving = true
        Task {
            do {
                try await save(pounds)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } catch {
                problem = error.localizedDescription
            }
            saving = false
        }
    }
}

#Preview("Log weight") {
    LogWeightSheet(last: 152.4) { _ in }
}

#Preview("Activity grid") {
    let start = Calendar.current.date(byAdding: .day, value: -60, to: .now)!
    ActivityGrid(steps: 7_420, activeEnergy: 380,
                 sleepWeek: [6.8, 7.4, 5.9, 8.1, 7.0, 6.5, 7.2],
                 weights: (0..<9).map { WeightSample(date: start.addingTimeInterval(Double($0) * 7 * 86_400),
                                                     pounds: 158 - Double($0) * 0.7) })
        .padding()
}
