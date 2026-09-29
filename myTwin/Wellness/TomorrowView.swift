import SwiftUI

/// Tomorrow's goals, written tonight: a box to type them, what myTwin read from it, and
/// with Pro a button that plans them into tomorrow's calendar. Above it, today's goals to
/// tick off, and anything unfinished carried over.
struct TomorrowView: View {
    let book: GoalBook
    let calendar: CalendarManager
    let voice: VoiceManager
    let preferences: PlanningPreferences
    let isPro: Bool
    let now: Date
    let upgrade: () -> Void

    @State private var text = ""
    @State private var result: String?
    @State private var askedForNotifications = false
    /// Turning what you said into goal lines.
    @State private var hearing = false
    /// The planned goal whose time you're changing, and the time on the wheel.
    @State private var moving: Goal?
    @State private var newTime = Date.now
    /// Goals you moved on top of something else on your calendar.
    @State private var clashes: Set<UUID> = []
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
            speakButton
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

    /// Say your goals instead of typing them: the same recording bar as talking to Dash,
    /// and what you said lands in the box, one goal per line.
    @ViewBuilder private var speakButton: some View {
        if hearing {
            Label("Writing down your goals…", systemImage: "ellipsis").font(.subheadline).foregroundStyle(.secondary)
        } else if voice.isDictating {
            Label("Listening. Tap send in the bar below when you're done.", systemImage: "mic.fill")
                .font(.subheadline).foregroundStyle(.red)
        } else {
            Button("Say your goals", systemImage: "mic.fill") {
                writing = false
                voice.startDictation { said in
                    hearing = true
                    Task {
                        let lines = await GoalSpeech.lines(from: said)
                        let kept = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        text = ([kept] + lines).filter { !$0.isEmpty }.joined(separator: "\n")
                        hearing = false
                    }
                }
            }
            .buttonStyle(.bordered)
            .disabled(voice.status != .listening)
            if voice.status != .listening {
                Text("The microphone isn't ready. You can type instead.").font(.caption).foregroundStyle(.secondary)
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
                        if clashes.contains(goal.id) {
                            Text("Overlaps another event").font(.caption).foregroundStyle(.orange)
                        }
                    }
                    Spacer(minLength: 0)
                    if let at = goal.scheduled {
                        Button(at.formatted(date: .omitted, time: .shortened)) {
                            newTime = at
                            moving = goal
                        }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.bordered)
                        .tint(.green)
                        .accessibilityHint("Change the time")
                    }
                }
                .padding(.vertical, 8)
                if goal.id != next.goals.last?.id { Divider() }
            }
        }
        .dashboardCard()
        .sheet(item: $moving) { goal in
            NavigationStack {
                DatePicker("Start", selection: $newTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .navigationTitle(goal.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { moving = nil } }
                        ToolbarItem(placement: .confirmationAction) { Button("Save") { move(goal, to: newTime) } }
                    }
            }
            .presentationDetents([.height(300)])
        }
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

    /// One planned goal to the time you picked: its calendar event, its reminder and the
    /// morning list all move with it. Only this goal moves; the rest of the plan stays.
    private func move(_ goal: Goal, to start: Date) {
        moving = nil
        let end = start.addingTimeInterval(Double(goal.minutes) * 60)
        let others = next.goals.filter { $0.id != goal.id }.compactMap { other in
            other.scheduled.map { DateInterval(start: $0, duration: Double(other.minutes) * 60) }
        }
        let overlaps = (calendar.busy(on: tomorrow) + others).contains { $0.start < end && $0.end > start }
        if overlaps { clashes.insert(goal.id) } else { clashes.remove(goal.id) }

        calendar.moveGoal(goal, to: start)
        book.reschedule(goal, to: start, on: tomorrow)
        result = "Moved \(goal.title) to \(start.formatted(date: .omitted, time: .shortened))."
        guard !book.isDemo else { return }
        let planned = next.goals.compactMap { goal in goal.scheduled.map { (goal: goal, start: $0) } }
        Task { await GoalNotifications.morning(for: tomorrow, goals: planned, wake: preferences.quietEnd) }
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
