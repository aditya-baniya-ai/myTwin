import EventKit
import SwiftUI

/// One row of today's plan: an event from your calendar, or a suggestion myTwin placed in
/// a free block to suit your predicted energy.
struct PlanItem: Identifiable {
    enum Kind { case event, suggestion }

    let kind: Kind
    let title: String
    let start: Date
    let end: Date
    var note: String?
    var color: Color = .accentColor      // the calendar's colour, or the energy colour
    var symbol: String = "sparkles"

    /// The same row keeps the same identity when the plan is rebuilt, so a half-finished
    /// swipe isn't lost.
    var id: String { "\(title)|\(start.timeIntervalSinceReferenceDate)" }
}

/// Suggestions you swiped away. Gone for the rest of today, and if you keep swiping the
/// same one away, myTwin takes the hint and stops offering it for a while.
enum DismissedSuggestions {
    private static let key = "dismissedSuggestions"
    /// Swipe the same suggestion away this many times and it goes quiet.
    private static let enough = 3
    private static let remembers: TimeInterval = 14 * 86_400
    private static let quietFor: TimeInterval = 7 * 86_400

    /// Everything that should not be suggested right now.
    static func today() -> Set<String> {
        let history = stored()
        let recent = history.filter { !$0.value.isEmpty }
        var hidden: Set<String> = []
        for (title, times) in recent {
            if times.contains(where: { Calendar.current.isDateInToday($0) }) { hidden.insert(title) }
            let lately = times.filter { $0.timeIntervalSinceNow > -remembers }
            if lately.count >= enough, let last = lately.max(), last.timeIntervalSinceNow > -quietFor {
                hidden.insert(title)      // you have said no often enough
            }
        }
        return hidden
    }

    static func add(_ title: String) {
        var history = stored()
        history[title, default: []].append(.now)
        history[title] = history[title]?.filter { $0.timeIntervalSinceNow > -remembers }
        UserDefaults.standard.set(history, forKey: key)
    }

    private static func stored() -> [String: [Date]] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: [Date]] ?? [:]
    }
}

/// Fills free time with suggestions that suit your predicted energy: a workout in the
/// strongest free hour, and a low-effort task once your energy drops in the evening.
enum DayPlanner {
    /// Your 4-day split, one day after the next. Edit to match yours.
    static let workoutSplit = ["Shoulders & Back", "Chest & Triceps", "Legs", "Arms & Core"]
    static let easyTask = "Meal prep: chicken & rice"
    static let napTitle = "Nap"
    static let coffeeTitle = "Last coffee"
    /// Whole words that mean a workout is already booked, so none is suggested.
    private static let workoutWords: Set<String> = ["gym", "workout", "run", "training", "lift", "yoga", "swim"]

    /// Today's timed events as plan rows. All-day events are shown separately.
    static func items(from events: [EKEvent]) -> [PlanItem] {
        events.filter { !$0.isAllDay }.map { event in
            PlanItem(kind: .event, title: event.title ?? "Untitled", start: event.startDate,
                     end: event.endDate,
                     color: event.calendar.map { Color(cgColor: $0.cgColor) } ?? .accentColor)
        }
    }

    /// The gentler thing to suggest on a day that started below your normal.
    static let easyMove = "Easy walk"

    /// `workout` picks the split day; left out, the split moves on one day at a time.
    /// Titles in `excluding` (dismissed) are never suggested, nor is anything already on
    /// the calendar. `trained` is true when Apple Health has a workout recorded today, and
    /// `easyDay` when today came in below your normal, which buys a walk instead of a
    /// session.
    static func plan(events: [PlanItem], dayStart: Double, now: Date, bedtime: Date,
                     workout: String? = nil, excluding dismissed: Set<String> = [],
                     trained: Bool = false, easyDay: Bool = false) -> [PlanItem] {
        func energy(_ date: Date) -> Double { DayCharge.remaining(from: dayStart, at: date) }
        let calendar = Calendar.current
        let gaps = freeBlocks(around: events, from: now, to: bedtime)
        var suggestions: [PlanItem] = []
        let alreadyTraining = events.contains { event in
            !workoutWords.isDisjoint(with: event.title.lowercased().split { !$0.isLetter }.map(String.init))
        }
        let skip = dismissed.union(events.map(\.title))

        // A workout in the free hour with the most energy, if it's a strong one.
        let day = (calendar.ordinality(of: .day, in: .era, for: now) ?? 0) % workoutSplit.count
        let workoutTitle = easyDay ? easyMove : "\(workout ?? workoutSplit[day]) workout"
        let length = easyDay ? 30 : 60
        // A workout already recorded in Health beats anything the calendar says.
        if !alreadyTraining, !trained, !skip.contains(workoutTitle),
           let gap = gaps.filter({ $0.duration >= Double(length) * 60 && calendar.component(.hour, from: $0.start) < 20 })
            .max(by: { energy($0.start) < energy($1.start) }),
           energy(gap.start) >= (easyDay ? 0.55 : 0.75) * dayStart {
            suggestions.append(suggestion(workoutTitle, in: gap, minutes: length,
                                          note: easyDay
                                            ? "Today came in under your normal, so something gentle at \(percent(energy(gap.start)))."
                                            : "Forecast \(percent(energy(gap.start))): one of your strongest hours left today.",
                                          charge: energy(gap.start)))
        }

        // A low-effort task in the first free stretch of the evening where energy has
        // dropped: the evening part of any free block, after anything already placed there.
        let taken = suggestions.map { DateInterval(start: $0.start, end: $0.end) }
        let evening = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: now) ?? now
        let slots = gaps.compactMap { gap -> DateInterval? in
            var start = max(gap.start, evening)
            for block in taken where block.start <= start && block.end > start { start = block.end }
            return start < gap.end ? DateInterval(start: start, end: gap.end) : nil
        }
        if !skip.contains(easyTask),
           let slot = slots.first(where: { $0.duration >= 45 * 60 && energy($0.start) <= 0.7 * dayStart }) {
            suggestions.append(suggestion(easyTask, in: slot, minutes: 45,
                                          note: "Energy drops to \(percent(energy(slot.start))): an easy task fits.",
                                          charge: energy(slot.start)))
        }
        // A nap when energy bottoms out, if you're free and it's early enough not to
        // cost you the night.
        let cutoff = bedtime.addingTimeInterval(-8 * 3600)      // caffeine's long tail
        let tooLateToNap = bedtime.addingTimeInterval(-7 * 3600)
        if !skip.contains(napTitle),
           let slot = free(gaps, after: suggestions, minutes: 25,
                           where: { energy($0) <= 0.65 * dayStart && $0 < tooLateToNap }) {
            suggestions.append(suggestion(napTitle, in: slot, minutes: 25,
                                          note: "You're down to \(percent(energy(slot.start))). Twenty minutes beats another coffee.",
                                          charge: energy(slot.start), symbol: "moon.zzz.fill"))
        }

        // The last coffee that still clears before bed.
        if !skip.contains(coffeeTitle), now < cutoff,
           let slot = free(gaps, after: suggestions, minutes: 15,
                           where: { $0 < cutoff && energy($0) <= 0.8 * dayStart }) {
            suggestions.append(suggestion(coffeeTitle, in: slot, minutes: 15,
                                          note: "After \(clock(cutoff)) caffeine is still in you at bedtime.",
                                          charge: energy(slot.start), symbol: "cup.and.saucer.fill"))
        }

        return (events + suggestions).sorted { $0.start < $1.start }
    }

    /// The first free stretch long enough, clear of what has already been suggested, and
    /// happening at a time that suits.
    private static func free(_ gaps: [DateInterval], after taken: [PlanItem], minutes: Int,
                             where suits: (Date) -> Bool) -> DateInterval? {
        let length = Double(minutes) * 60
        let busy = taken.map { DateInterval(start: $0.start, end: $0.end) }
        for gap in gaps {
            // Walk through the block a quarter-hour at a time: a rule like "once energy has
            // dropped" is usually true later in a block, not at the very start of it.
            var start = roundedUp(gap.start)      // land on the clock, not on 2:04
            while start.addingTimeInterval(length) <= gap.end {
                let slot = DateInterval(start: start, duration: length)
                if suits(start), !busy.contains(where: { $0.intersects(slot) }) { return slot }
                start.addTimeInterval(15 * 60)
            }
        }
        return nil
    }

    private static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
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
                                   note: String, charge: Double,
                                   symbol: String = "sparkles") -> PlanItem {
        let length = TimeInterval(minutes * 60)
        let tidy = roundedUp(gap.start)
        let start = tidy.addingTimeInterval(length) <= gap.end ? tidy : gap.start
        return PlanItem(kind: .suggestion, title: title, start: start, end: start.addingTimeInterval(length),
                        note: note, color: AvatarEnergyState(score: charge * 100).glow[0], symbol: symbol)
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
    /// Swipe right, then Add: the suggestion goes on the calendar.
    var accept: ((PlanItem) -> Void)?
    /// Swipe left, then Remove: the suggestion goes away for today.
    var dismiss: ((PlanItem) -> Void)?

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
                Group {
                    if item.kind == .suggestion, let accept, let dismiss {
                        // The whole row slides, so nothing overlaps the time down the side.
                        SwipeToDecide(add: { accept(item) }, remove: { dismiss(item) }) { row(item) }
                    } else {
                        row(item)
                    }
                }
                .opacity(item.kind == .event && item.end < now ? 0.45 : 1)    // already over
            }
            if accept != nil, items.contains(where: { $0.kind == .suggestion }) {
                Label("Swipe a suggestion right to add it, left to dismiss it.", systemImage: "hand.draw")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .dashboardCard()
    }

    private func row(_ item: PlanItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(item.start, format: .dateTime.hour().minute())
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .trailing)
                .padding(.top, 12)
            if item.kind == .event { event(item) } else { suggestion(item) }
        }
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
            Image(systemName: item.symbol)
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

/// Swipe right to reveal Add, left to reveal Remove, like Mail. Only sideways drags count,
/// so the page still scrolls.
private struct SwipeToDecide<Content: View>: View {
    let add: () -> Void
    let remove: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    private let reveal: CGFloat = 92

    var body: some View {
        content()
            .offset(x: offset)
            .gesture(HorizontalPan(changed: { dx in offset = min(max(offset + dx, -reveal * 1.4), reveal * 1.4) },
                                   ended: { _ in settle() }))
            .onTapGesture { withAnimation(.snappy) { offset = 0 } }    // tap to close
            .background {
                HStack(spacing: 0) {
                    action("Add", symbol: "calendar.badge.plus", tint: .green, shown: offset > 0, perform: add)
                    Spacer(minLength: 0)
                    action("Remove", symbol: "xmark", tint: .red, shown: offset < 0, perform: remove)
                }
            }
    }

    /// Past halfway it stays open on that side; otherwise it springs back.
    private func settle() {
        withAnimation(.snappy) {
            offset = offset > reveal / 2 ? reveal : offset < -reveal / 2 ? -reveal : 0
        }
    }

    private func action(_ title: String, symbol: String, tint: Color, shown: Bool,
                        perform: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.snappy) { offset = 0 }
            perform()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.title3.weight(.semibold))
                Text(title).font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(width: reveal - 10)
            .frame(maxHeight: .infinity)
            .background(tint, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .opacity(shown ? 1 : 0)
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

/// The week ahead: one row per day with what's on it, so you can see where the free space
/// is without opening anything.
struct WeekPlan: View {
    let days: [(date: Date, allDay: [String], events: [PlanItem])]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                HStack(alignment: .top, spacing: 14) {
                    date(day.date)
                    if day.events.isEmpty, day.allDay.isEmpty {
                        Text("Free")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 6)
                        Spacer(minLength: 0)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(day.allDay, id: \.self) { title in
                                Text(title)                       // holidays and birthdays
                                    .font(.subheadline)
                                    .lineLimit(1)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(day.events.prefix(3)) { event in
                                HStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(event.color)
                                        .frame(width: 3, height: 15)
                                    Text(event.title).font(.subheadline).lineLimit(1)
                                    Spacer(minLength: 0)
                                    Text(event.start, format: .dateTime.hour().minute())
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if day.events.count > 3 {
                                Text("+\(day.events.count - 3) more")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.vertical, 9)
                if index < days.count - 1 { Divider() }
            }
        }
        .dashboardCard()
    }

    private func date(_ day: Date) -> some View {
        let today = Calendar.current.isDateInToday(day)
        return VStack(spacing: 1) {
            Text(day, format: .dateTime.weekday(.abbreviated))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(day, format: .dateTime.day())
                .font(.headline)
                .foregroundStyle(today ? Color.white : .primary)
                .frame(width: 28, height: 28)
                .background { if today { Circle().fill(BrandTitle.brand[1]) } }
        }
        .frame(width: 38)
    }
}
