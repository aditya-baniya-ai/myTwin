import Charts
import SwiftUI

/// The model's forecast for the rest of your day: when you'll be sharpest, and when the
/// dip is likely to hit. It is today's predicted starting energy, drained hour by hour by
/// the curve measured from thousands of real check-ins.
struct PredictionsCard: View {
    let points: [EnergyPoint]

    private var peak: EnergyPoint? { points.max { $0.charge < $1.charge } }

    /// The low point before energy picks up again: lower than the hours either side of it.
    private var dip: EnergyPoint? {
        guard points.count >= 3 else { return nil }
        return points.indices.dropFirst().dropLast()
            .first { points[$0].charge < points[$0 - 1].charge && points[$0].charge < points[$0 + 1].charge }
            .map { points[$0] }
    }

    private var colors: [Color] {
        AvatarEnergyState(score: (points.first?.charge ?? 0.85) * 100).glow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if points.count < 3 {
                Label("It's nearly bedtime. Tomorrow's forecast appears in the morning.", systemImage: "moon.stars")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                chart.frame(height: 150)
                HStack(spacing: 10) {
                    if let peak { moment("Peak focus", peak, symbol: "bolt.fill", tint: .green) }
                    if let dip { moment("Likely dip", dip, symbol: "arrow.down.right", tint: .orange) }
                }
            }
        }
        .dashboardCard()
    }

    private var chart: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(x: .value("Time", point.date), y: .value("Energy", point.charge * 100))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(colors: [colors[0].opacity(0.45), colors[0].opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", point.date), y: .value("Energy", point.charge * 100))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    .foregroundStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
            }
            // The value sits next to each dot, so nobody has to judge it against the axis.
            if let peak {
                PointMark(x: .value("Time", peak.date), y: .value("Energy", peak.charge * 100))
                    .symbolSize(110)
                    .foregroundStyle(.green)
                    .annotation(position: .trailing, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        valueLabel(peak, .green)
                    }
            }
            if let dip {
                PointMark(x: .value("Time", dip.date), y: .value("Energy", dip.charge * 100))
                    .symbolSize(110)
                    .foregroundStyle(.orange)
                    .annotation(position: .top, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        valueLabel(dip, .orange)
                    }
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                let percent = value.as(Int.self) ?? 0
                AxisGridLine().foregroundStyle(.secondary.opacity(percent % 50 == 0 ? 0.5 : 0.2))
                if percent % 50 == 0 {
                    AxisValueLabel { Text("\(percent)%") }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
    }

    private func valueLabel(_ point: EnergyPoint, _ tint: Color) -> some View {
        Text("\(Int(point.charge * 100))%")
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
    }

    private func moment(_ label: String, _ point: EnergyPoint, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(label, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(point.date == points.first?.date ? "Now" : point.date.formatted(date: .omitted, time: .shortened))
                .font(.headline)
            Text("\(Int(point.charge * 100))% charged")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 14))
    }
}

#Preview("Predictions") {
    let nine = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!
    let bedtime = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: .now)!
    PredictionsCard(points: DayCharge.forecast(from: 0.95, now: nine, until: bedtime))
        .padding()
}
