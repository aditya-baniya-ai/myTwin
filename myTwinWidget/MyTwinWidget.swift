import SwiftUI
import WidgetKit

/// The twin on the Home Screen, fading as the day wears on.
///
/// A widget cannot run a live 3D scene, so it shows the character's rendered still for
/// the energy state the clock implies. It cannot see your health data either - sharing
/// the app's data needs a paid developer account - so it draws the day's measured drain
/// from an average start.
struct MyTwinWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MyTwinWidget", provider: Provider()) { entry in
            WidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Your twin")
        .description("How much of the day you have left in you.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let energy: Double          // 0-100
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        entry(at: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(entry(at: .now))
    }

    /// One entry on each of the next twelve hours, because the curve only moves hourly.
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
        Entry(date: date, energy: DayCharge.remaining(from: DayCharge.unknownDay, at: date) * 100)
    }
}

struct WidgetView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family

    private var state: AvatarEnergyState { AvatarEnergyState(score: entry.energy) }
    private var percent: String { "\(Int(entry.energy))%" }

    var body: some View {
        switch family {
        case .systemMedium:
            HStack(spacing: 16) {
                twin
                VStack(alignment: .leading, spacing: 4) {
                    Text(percent)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("charged")
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
            VStack(spacing: 2) {
                twin
                Text("\(percent) charged")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var twin: some View {
        Image(AvatarCharacter.dash.stillName(for: state))
            .resizable()
            .scaledToFit()
    }

    private var advice: String {
        switch state {
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
