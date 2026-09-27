import SwiftUI
import WidgetKit

/// The twin on the Home Screen, fading as the day wears on.
///
/// It shows exactly what the app shows: the app shares where today's charge started (see
/// TwinState), and both work out each hour's charge with the same curve. A widget cannot
/// run a live 3D scene, so it draws the character's rendered still for that mood.
struct MyTwinWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MyTwinWidget", provider: Provider()) { entry in
            WidgetView(entry: entry)
                .containerBackground(for: .widget) { BatteryBackdrop(energy: entry.energy) }
        }
        .configurationDisplayName("Your twin")
        .description("How much of the day you have left in you.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let energy: Double          // illustrative, 0-100
    var hasPrediction = false
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        entry(at: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(entry(at: .now))
    }

    /// One entry on each of the next twelve hours, because the curve only moves hourly.
    /// The app asks for a fresh timeline whenever today's prediction changes.
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        var dates = [Date.now]
        let calendar = Calendar.current
        if let nextHour = calendar.nextDate(after: .now, matching: DateComponents(minute: 0),
                                            matchingPolicy: .nextTime) {
            dates += (0..<12).compactMap { calendar.date(byAdding: .hour, value: $0, to: nextHour) }
        }
        completion(Timeline(entries: dates.map(entry), policy: .atEnd))
    }

    private func entry(at date: Date) -> Entry {
        Entry(date: date, energy: TwinState.energy(at: date), hasPrediction: TwinState.hasPrediction(on: date))
    }
}

struct WidgetView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family

    private var mood: AvatarEnergyState { AvatarEnergyState(score: entry.energy) }
    private var percent: String { "\(Int(entry.energy))%" }

    var body: some View {
        switch family {
        case .systemMedium:
            HStack(spacing: 12) {
                twin.frame(width: 120)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.hasPrediction ? percent : "—")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text(entry.hasPrediction ? "estimated" : "Still learning")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(advice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
        default:
            VStack(spacing: 0) {
                twin
                Text(entry.hasPrediction ? "\(percent) estimated" : "Check in with Dash")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The same stage the app draws: light behind, glowing platform, the character's still.
    private var twin: some View {
        TwinStage(energy: entry.energy) {
            Image(mood.stillName)
                .resizable()
                .scaledToFit()
        }
    }

    private var advice: String {
        guard entry.hasPrediction else { return "Open myTwin to tell Dash how you feel." }
        return switch mood {
        case .energetic: "Good window for the hard thing."
        case .normal: "Steady. Keep the big tasks moving."
        case .tired: "Past your peak. Save the easy jobs for later."
        case .exhausted: "Running low. Wind down rather than push."
        }
    }
}

@main
struct MyTwinWidgetBundle: WidgetBundle {
    var body: some Widget { MyTwinWidget() }
}
