import SwiftUI

/// One row of today's plan: an event from your calendar, or a suggestion myTwin placed in
/// a free block to suit your predicted energy.
struct PlanItem: Identifiable {
    enum Kind { case event, suggestion }

    let id = UUID()
    let kind: Kind
    let title: String
    let start: Date
    let end: Date
    var note: String?
    var color: Color = .accentColor      // the calendar's colour, or the energy colour
}

/// Fills free time with suggestions that suit your predicted energy: a workout in the
/// strongest free hour, and a low-effort task once your energy drops in the evening.
enum DayPlanner {
    /// Your 4-day split, one day after the next. Edit to match yours.
    static let workoutSplit = ["Shoulders & Back", "Chest & Triceps", "Legs", "Arms & Core"]
    static let easyTask = "Meal prep: chicken & rice"
    /// Whole words that mean a workout is already booked, so none is suggested.
    private static let workoutWords: Set<String> = ["gym", "workout", "run", "training", "lift", "yoga", "swim"]

    /// `workout` picks the split day; left out, the split moves on one day at a time.
    static func plan(events: [PlanItem], dayStart: Double, now: Date, bedtime: Date,
                     workout: String? = nil) -> [PlanItem] {
        func energy(_ date: Date) -> Double { DayCharge.remaining(from: dayStart, at: date) }
        let calendar = Calendar.current
        let gaps = freeBlocks(around: events, from: now, to: bedtime)
        var suggestions: [PlanItem] = []
        let alreadyTraining = events.contains { event in
            !workoutWords.isDisjoint(with: event.title.lowercased().split { !$0.isLetter }.map(String.init))
        }

        // A workout in the free hour with the most energy, if it's a strong one.
        if !alreadyTraining,
           let gap = gaps.filter({ $0.duration >= 3600 && calendar.component(.hour, from: $0.start) < 20 })
            .max(by: { energy($0.start) < energy($1.start) }),
           energy(gap.start) >= 0.75 * dayStart {
            let day = (calendar.ordinality(of: .day, in: .era, for: now) ?? 0) % workoutSplit.count
            suggestions.append(suggestion("\(workout ?? workoutSplit[day]) workout", in: gap, minutes: 60,
                                          note: "Forecast \(percent(energy(gap.start))): one of your strongest hours left today.",
                                          charge: energy(gap.start)))
        }

        // A low-effort task in the first evening block where energy has dropped.
        let taken = suggestions.map { DateInterval(start: $0.start, end: $0.end) }
        if let gap = gaps.first(where: { gap in
            calendar.component(.hour, from: gap.start) >= 17 && gap.duration >= 45 * 60
                && energy(gap.start) <= 0.7 * dayStart && !taken.contains { $0.intersects(gap) }
        }) {
            suggestions.append(suggestion(easyTask, in: gap, minutes: 45,
                                          note: "Energy drops to \(percent(energy(gap.start))): an easy task fits.",
                                          charge: energy(gap.start)))
        }
        return (events + suggestions).sorted { $0.start < $1.start }
    }

    /// The gaps between events, from now until bedtime.
    private static func freeBlocks(around events: [PlanItem], from now: Date, to bedtime: Date) -> [DateInterval] {
        var gaps: [DateInterval] = []
        var cursor = now
        for event in events.sorted(by: { $0.start < $1.start }) where event.end > cursor {
            if event.start > cursor { gaps.append(DateInterval(start: cursor, end: event.start)) }
            cursor = max(cursor, event.end)
        }
        if bedtime > cursor { gaps.append(DateInterval(start: cursor, end: bedtime)) }
        return gaps
    }

    /// Starts on the next half hour when it still fits, so blocks read like real plans.
    private static func suggestion(_ title: String, in gap: DateInterval, minutes: Int,
                                   note: String, charge: Double) -> PlanItem {
        let length = TimeInterval(minutes * 60)
        let tidy = roundedUp(gap.start)
        let start = tidy.addingTimeInterval(length) <= gap.end ? tidy : gap.start
        return PlanItem(kind: .suggestion, title: title, start: start, end: start.addingTimeInterval(length),
                        note: note, color: AvatarEnergyState(score: charge * 100).glow[0])
    }

    /// The next :00 or :30 at or after `date`.
    private static func roundedUp(_ date: Date) -> Date {
        let hour = Calendar.current.dateInterval(of: .hour, for: date)?.start ?? date
        return [0, 30, 60].map { hour.addingTimeInterval(Double($0) * 60) }.first { $0 >= date } ?? date
    }

    private static func percent(_ charge: Double) -> String { "\(Int(charge * 100))%" }
}

/// Today's plan: your calendar events, with myTwin's suggestions slotted into the free
/// time between them. Suggestions glow with a dashed edge so they never look like
/// something already booked.
struct SmartCalendar: View {
    let allDay: [String]
    let items: [PlanItem]
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !allDay.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(allDay, id: \.self) { title in
                            Label(title, systemImage: "calendar")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(.tertiarySystemFill), in: .capsule)
                        }
                    }
                }
            }
            if items.isEmpty {
                Text("Nothing planned for the rest of today.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 12) {
                    Text(item.start, format: .dateTime.hour().minute())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 62, alignment: .trailing)
                        .padding(.top, 12)
                    if item.kind == .event { event(item) } else { suggestion(item) }
                }
                .opacity(item.kind == .event && item.end < now ? 0.45 : 1)    // already over
            }
        }
        .dashboardCard()
    }

    private func event(_ item: PlanItem) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(item.color)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline.weight(.semibold))
                Text(timeRangeText(item.start, item.end)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 14))
    }

    private func suggestion(_ item: PlanItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(item.color)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text("SUGGESTED")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(item.color)
                Text(item.title).font(.subheadline.weight(.semibold))
                Text(timeRangeText(item.start, item.end)).font(.caption).foregroundStyle(.secondary)
                if let note = item.note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(item.color.opacity(0.10), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(item.color, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        }
        .shadow(color: item.color.opacity(0.45), radius: 8)
    }
}

#Preview("Smart calendar") {
    let today = Calendar.current.startOfDay(for: .now)
    let at = { (hour: Double) in today.addingTimeInterval(hour * 3600) }
    let events = [
        PlanItem(kind: .event, title: "CS 3358 Data Structures", start: at(9.5), end: at(10.83), color: .blue),
        PlanItem(kind: .event, title: "CS 4337 Programming Languages", start: at(11), end: at(12.33), color: .blue),
        PlanItem(kind: .event, title: "Project meeting", start: at(14.5), end: at(15.25), color: .purple),
        PlanItem(kind: .event, title: "CS lab", start: at(15.5), end: at(17), color: .blue),
    ]
    ScrollView {
        SmartCalendar(allDay: ["Constitution Day"],
                      items: DayPlanner.plan(events: events, dayStart: 0.95, now: at(9), bedtime: at(23),
                                             workout: "Shoulders & Back"),
                      now: at(9))
            .padding()
    }
}
