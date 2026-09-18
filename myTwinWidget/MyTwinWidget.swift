import AppIntents
import SwiftUI
import WidgetKit

/// The twin on the Home Screen: the same character, fading as the day wears on.
///
/// The widget cannot read the app's health data or the character you picked - that needs
/// a paid developer account's shared container - so it draws the day's measured drain and
/// lets you choose the character in its own settings (long-press the widget, Edit Widget).
struct MyTwinWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "MyTwinWidget",
                               intent: CharacterIntent.self,
                               provider: Provider()) { entry in
            WidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Your twin")
        .description("How much of the day you have left in you.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Which character to draw

enum WidgetCharacter: String, AppEnum, CaseIterable {
    case dash, nova, pip, kai, sol, wren

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Character" }

    /// Spelled out because the AppEnum macro needs a literal. Keep in step with AvatarStyle.all.
    static var caseDisplayRepresentations: [WidgetCharacter: DisplayRepresentation] = [
        .dash: "Dash", .nova: "Nova", .pip: "Pip", .kai: "Kai", .sol: "Sol", .wren: "Wren",
    ]

    var style: AvatarStyle { AvatarStyle.named(rawValue) }
}

struct CharacterIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Choose your twin" }

    @Parameter(title: "Character", default: .dash)
    var character: WidgetCharacter
}

// MARK: - What to show, and when

struct Entry: TimelineEntry {
    let date: Date
    let charge: Double
    let style: AvatarStyle
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> Entry {
        entry(at: .now, character: .dash)
    }

    func snapshot(for configuration: CharacterIntent, in context: Context) async -> Entry {
        entry(at: .now, character: configuration.character)
    }

    /// One entry on each of the next twelve hours, because the curve only moves hourly.
    func timeline(for configuration: CharacterIntent, in context: Context) async -> Timeline<Entry> {
        var dates = [Date.now]
        let calendar = Calendar.current
        if let nextHour = calendar.nextDate(after: .now, matching: DateComponents(minute: 0),
                                            matchingPolicy: .nextTime) {
            dates += (0..<12).compactMap { calendar.date(byAdding: .hour, value: $0, to: nextHour) }
        }
        return Timeline(entries: dates.map { entry(at: $0, character: configuration.character) },
                        policy: .atEnd)
    }

    private func entry(at date: Date, character: WidgetCharacter) -> Entry {
        Entry(date: date,
              charge: DayCharge.remaining(from: DayCharge.unknownDay, at: date),
              style: character.style)
    }
}

// MARK: - The face of it

struct WidgetView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family

    private var percent: String { "\(Int(entry.charge * 100))%" }

    var body: some View {
        switch family {
        case .systemMedium:
            HStack(spacing: 18) {
                avatar(size: 108)
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
                avatar(size: 96)
                Text("\(percent) charged")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func avatar(size: CGFloat) -> some View {
        AvatarView(charge: entry.charge, style: entry.style, size: size, animates: false)
    }

    private var advice: String {
        switch entry.charge {
        case 0.66...: "Good window for the hard thing."
        case 0.4..<0.66: "Past your peak. Save the easy jobs for later."
        default: "Running low. Wind down rather than push."
        }
    }
}

@main
struct MyTwinWidgetBundle: WidgetBundle {
    var body: some Widget { MyTwinWidget() }
}
