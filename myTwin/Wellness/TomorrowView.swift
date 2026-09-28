import SwiftUI

/// Tomorrow's goals, written tonight: a box to type them, what myTwin read from it, and
/// with Pro a button that plans them into tomorrow's calendar. Above it, today's goals to
/// tick off, and anything unfinished carried over.
struct TomorrowView: View {
    let book: GoalBook
    let calendar: CalendarManager
    let preferences: PlanningPreferences
    let isPro: Bool
    let now: Date
    let upgrade: () -> Void

    @State private var text = ""
    @State private var result: String?
    @State private var askedForNotifications = false
    @FocusState private var writing: Bool

    private var tomorrow: Date { Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now }
    private var today: GoalBook.Day { book.day(now) }
    private var next: GoalBook.Day { book.day(tomorrow) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !today.goals.isEmpty { todaysGoals }
            writeBox
            if !next.goals.isEmpty { readGoals }
            planButton
        }
        .onAppear { text = next.text }
        .onChange(of: tomorrow) { text = next.text }
        .onChange(of: isPro) { result = nil }
        .onChange(of: text) { _, value in
            book.write(value, for: tomorrow)
            result = nil
            Task { await remind() }
        }
    }

    // MARK: - Today

    private var todaysGoals: some View {
        let left = today.goals.filter { !$0.done && !$0.moved }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Did you finish today's goals?").font(.title3.bold())
            VStack(spacing: 0) {
                ForEach(today.goals) { goal in
                    Button { book.toggle(goal, on: now) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: goal.done ? "checkmark.circle.fill" : goal.moved ? "arrow.turn.down.right" : "circle")
                                .font(.title3)
                                .foregroundStyle(goal.done ? .green : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(goal.title).strikethrough(goal.done).foregroundStyle(goal.done ? .secondary : .primary)
                                if goal.moved { Text("Moved to tomorrow").font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(goal.moved)
                    if goal.id != today.goals.last?.id { Divider() }
                }
                if left.isEmpty {
                    Label("All of today's goals are done or carried over.", systemImage: "sparkles")
                        .font(.subheadline).foregroundStyle(.green).padding(.top, 8)
                } else {
                    Button("Move \(left.count) unfinished to tomorrow", systemImage: "arrow.uturn.forward") {
                        book.moveUnfinished(from: now)
                        text = next.text
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .dashboardCard()
        }
    }

    // MARK: - Tomorrow

    private var writeBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Goals for \(tomorrow.formatted(.dateTime.weekday(.wide)))").font(.title3.bold())
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("One goal per line, personal or work.\nFinish lit review, 2 hrs, morning\nCall mom at 7pm\nGym 45 min")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8).padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .focused($writing)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 130)
                    .accessibilityLabel("Goals for tomorrow")
            }
            .dashboardCard(padding: 12)
            Text("Add a length (\"2 hrs\"), a time (\"at 3pm\") or a part of the day (\"morning\") if you like. It can differ from your calendar.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { writing = false }
            }
        }
    }

    /// What myTwin read from the box: each goal, how long, and where Plan my day put it.
    private var readGoals: some View {
        VStack(spacing: 0) {
            ForEach(next.goals) { goal in
                HStack(spacing: 12) {
                    Image(systemName: goal.kind == .professional ? "briefcase.fill" : "person.fill")
                        .foregroundStyle(goal.kind == .professional ? .blue : .pink)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.title)
                        Text(detail(goal)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if let at = goal.scheduled {
                        Text(at.formatted(date: .omitted, time: .shortened))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                    }
                }
                .padding(.vertical, 8)
                if goal.id != next.goals.last?.id { Divider() }
            }
        }
        .dashboardCard()
    }

    private func detail(_ goal: Goal) -> String {
        let length = goal.minutes >= 60 && goal.minutes % 30 == 0
            ? (goal.minutes % 60 == 0 ? "\(goal.minutes / 60) hr" : String(format: "%.1f hr", Double(goal.minutes) / 60))
            : "\(goal.minutes) min"
        let when = goal.hour.map { hour in
            Calendar.current.date(bySettingHour: hour, minute: goal.minute ?? 0, second: 0, of: tomorrow)?
                .formatted(date: .omitted, time: .shortened) ?? ""
        } ?? goal.window?.rawValue
        return [length, goal.kind == .professional ? "work" : "personal", when].compactMap { $0 }.joined(separator: " · ")
    }

    private var planButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isPro ? plan() : upgrade()
            } label: {
                Label("Plan my day tomorrow", systemImage: isPro ? "wand.and.stars" : "lock.fill")
                    .font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(next.goals.isEmpty)
            Text(result ?? (isPro
                 ? "Puts each goal into tomorrow's free time, work in your strongest hours, with a reminder before each."
                 : "With Pro, myTwin plans these into tomorrow's calendar and reminds you."))
                .font(.caption).foregroundStyle(result == nil ? .secondary : .primary)
        }
    }

    // MARK: - Doing it

    private func plan() {
        writing = false
        let goals = next.goals.filter { !$0.done }
        let times = GoalPlanner.plan(goals, on: tomorrow, busy: calendar.busy(on: tomorrow),
                                     wake: preferences.quietEnd, bedtime: preferences.bedtime(on: tomorrow))
        let placed = goals.compactMap { goal in times[goal.id].map { (goal: goal, start: $0) } }
        let saved = calendar.placeGoals(placed, on: tomorrow)
        book.schedule(times, on: tomorrow)
        let missed = goals.count - placed.count
        result = saved == 0 ? "Couldn't add them to your calendar. Check calendar access on the You page."
            : "Planned \(saved) goal\(saved == 1 ? "" : "s") into tomorrow, with reminders."
              + (missed > 0 ? " \(missed) didn't fit around your calendar." : "")
        Task {
            if !book.isDemo {
                await NotificationManager().requestPermission()
                await GoalNotifications.morning(for: tomorrow, goals: placed, wake: preferences.quietEnd)
            }
        }
    }

    /// The evening "did you finish?" for tomorrow's goals, for everyone.
    private func remind() async {
        guard !book.isDemo, !next.goals.isEmpty else { return }
        if !askedForNotifications {            // once: iOS only shows the question the first time
            askedForNotifications = true
            await NotificationManager().requestPermission()
        }
        await GoalNotifications.nightly(for: tomorrow, count: next.goals.count, preferences: preferences)
    }
}
