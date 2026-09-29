import SwiftUI

/// Tomorrow's goals, written tonight: a box to type them, what myTwin read from it, and
/// with Pro a button that plans them into tomorrow's calendar. Above it, today's goals to
/// tick off, add to, and with Pro plan into the rest of today; anything unfinished carries over.
struct TomorrowView: View {
    let book: GoalBook
    let calendar: CalendarManager
    let voice: VoiceManager
    let preferences: PlanningPreferences
    let isPro: Bool
    let now: Date
    let upgrade: () -> Void

    @State private var text = ""
    /// What the last plan or move did, for each day.
    @State private var results: [String: String] = [:]
    @State private var askedForNotifications = false
    /// The day you're saying goals for, today or tomorrow, and whether what you said is
    /// still being turned into goal lines.
    @State private var speakingFor: String?
    @State private var hearing = false
    /// A goal being typed for today.
    @State private var todayLine = ""
    /// One of today's goals you're editing.
    @State private var editing: Goal?
    /// The planned goal whose time you're changing, and the time on the wheel.
    @State private var moving: Goal?
    @State private var newTime = Date.now
    /// Goals you moved on top of something else on your calendar.
    @State private var clashes: Set<UUID> = []
    @FocusState private var writing: Bool
    @FocusState private var addingToday: Bool

    private var tomorrow: Date { Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now }
    private var today: GoalBook.Day { book.day(now) }
    private var next: GoalBook.Day { book.day(tomorrow) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            todaysGoals
            writeBox
            if !next.goals.isEmpty { readGoals }
            planButton(for: tomorrow, title: "Plan my day tomorrow", open: next.goals.count,
                       pro: "Puts each goal into tomorrow's free time, work in your strongest hours, with a reminder before each.",
                       free: "With Pro, myTwin plans these into tomorrow's calendar and reminds you.")
        }
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
        .sheet(item: $editing) { goal in
            GoalEditor(goal: goal, day: now, save: saveEdit, delete: { deleteGoal(goal) })
        }
        .onAppear { text = next.text }
        .onChange(of: tomorrow) { text = next.text }
        .onChange(of: isPro) { results = [:] }
        .onChange(of: text) { _, value in
            book.write(value, for: tomorrow)
            results[GoalBook.name(tomorrow)] = nil
            Task { await remind() }
        }
    }

    // MARK: - Today

    private var todaysGoals: some View {
        let left = today.goals.filter { !$0.done && !$0.moved }
        return VStack(alignment: .leading, spacing: 10) {
            Text(today.goals.isEmpty ? "Today's goals" : "Did you finish today's goals?").font(.title3.bold())
            VStack(spacing: 0) {
                ForEach(today.goals) { goal in
                    HStack(spacing: 12) {
                        // The circle ticks it off; the name opens it for editing.
                        Button { book.toggle(goal, on: now) } label: {
                            Image(systemName: goal.done ? "checkmark.circle.fill" : goal.moved ? "arrow.turn.down.right" : "circle")
                                .font(.title3)
                                .foregroundStyle(goal.done ? .green : .secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Tick off \(goal.title)")
                        .accessibilityAddTraits(goal.done ? [.isSelected] : [])
                        Button { editing = goal } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(goal.title).strikethrough(goal.done).foregroundStyle(goal.done ? .secondary : .primary)
                                    if goal.moved { Text("Moved to tomorrow").font(.caption).foregroundStyle(.secondary) }
                                    clashNote(goal)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 8)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Edit this goal")
                        if !goal.done && !goal.moved {
                            if goal.scheduled != nil {
                                timeButton(goal)
                            } else if let hour = goal.hour,
                                      let at = Calendar.current.date(bySettingHour: hour, minute: goal.minute ?? 0, second: 0, of: now) {
                                // A time you gave it, not on the calendar yet.
                                Button(at.formatted(date: .omitted, time: .shortened)) { editing = goal }
                                    .font(.subheadline.weight(.semibold))
                                    .buttonStyle(.bordered)
                                    .tint(.secondary)
                                    .accessibilityHint("Edit this goal")
                            }
                        }
                    }
                    .disabled(goal.moved)
                    if goal.id != today.goals.last?.id { Divider() }
                }
                if today.goals.isEmpty {
                    EmptyView()
                } else if left.isEmpty {
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
                addToToday
            }
            .dashboardCard()
            if !left.isEmpty {
                planButton(for: now, title: "Plan the rest of today", open: left.count,
                           pro: "Puts today's unfinished goals into your free time before bedtime, with a reminder before each.",
                           free: "With Pro, myTwin puts these into today's calendar and reminds you.")
            }
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
            speakButton(for: tomorrow, title: "Say your goals")
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { writing = false; addingToday = false }
            }
        }
    }

    /// Something you remembered after the day began: typed, or said out loud.
    private var addToToday: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Add a goal for today", text: $todayLine)
                    .focused($addingToday)
                    .onSubmit(addTypedGoal)
                Button("Add", systemImage: "plus.circle.fill", action: addTypedGoal)
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .disabled(todayLine.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 12)
            speakButton(for: now, title: "Say today's goals")
        }
    }

    private func addTypedGoal() {
        add([todayLine], to: now)
        todayLine = ""
    }

    /// Lines added to the end of a day's goals, keeping what's already there.
    private func add(_ lines: [String], to day: Date) {
        let isTomorrow = Calendar.current.isDate(day, inSameDayAs: tomorrow)
        let kept = (isTomorrow ? text : book.day(day).text).trimmingCharacters(in: .whitespacesAndNewlines)
        let joined = ([kept] + lines.map { $0.trimmingCharacters(in: .whitespaces) })
            .filter { !$0.isEmpty }.joined(separator: "\n")
        if isTomorrow { text = joined } else { book.write(joined, for: day) }
    }

    /// Say your goals instead of typing them: the same recording bar as talking to Dash,
    /// and what you said joins that day's goals, one per line.
    @ViewBuilder private func speakButton(for day: Date, title: String) -> some View {
        if speakingFor == GoalBook.name(day) && hearing {
            Label("Writing down your goals…", systemImage: "ellipsis").font(.subheadline).foregroundStyle(.secondary)
        } else if speakingFor == GoalBook.name(day) && voice.isDictating {
            Label("Listening. Tap send in the bar below when you're done.", systemImage: "mic.fill")
                .font(.subheadline).foregroundStyle(.red)
        } else {
            Button(title, systemImage: "mic.fill") {
                writing = false
                addingToday = false
                speakingFor = GoalBook.name(day)
                voice.startDictation { said in
                    hearing = true
                    Task {
                        add(await GoalSpeech.lines(from: said), to: day)
                        hearing = false
                    }
                }
            }
            .buttonStyle(.bordered)
            .disabled(voice.status != .listening || voice.isDictating || hearing)
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
                        clashNote(goal)
                    }
                    Spacer(minLength: 0)
                    timeButton(goal)
                }
                .padding(.vertical, 8)
                if goal.id != next.goals.last?.id { Divider() }
            }
        }
        .dashboardCard()
    }

    /// Where Plan my day put a goal. Tap it to pick another time.
    @ViewBuilder private func timeButton(_ goal: Goal) -> some View {
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

    @ViewBuilder private func clashNote(_ goal: Goal) -> some View {
        if clashes.contains(goal.id) {
            Text("Overlaps another event").font(.caption).foregroundStyle(.orange)
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

    /// Plans a day's goals into its calendar with Pro, or offers Pro.
    private func planButton(for day: Date, title: String, open: Int, pro: String, free: String) -> some View {
        let result = results[GoalBook.name(day)]
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                isPro ? plan(day) : upgrade()
            } label: {
                Label(title, systemImage: isPro ? "wand.and.stars" : "lock.fill")
                    .font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(open == 0)
            Text(result ?? (isPro ? pro : free))
                .font(.caption).foregroundStyle(result == nil ? .secondary : .primary)
        }
    }

    // MARK: - Doing it

    /// Puts a day's goals on its calendar. Times already set stay; for today, nothing new
    /// goes before now. Goals carried over to tomorrow are left out.
    private func plan(_ day: Date) {
        writing = false
        addingToday = false
        let isTomorrow = Calendar.current.isDate(day, inSameDayAs: tomorrow)
        let goals = book.day(day).goals.filter { !$0.moved }
        let open = goals.filter { !$0.done }
        let kept = open.filter { $0.scheduled != nil }.count
        let times = GoalPlanner.plan(goals, on: day, busy: calendar.busy(on: day), wake: preferences.quietEnd,
                                     bedtime: preferences.bedtime(on: day), notBefore: now)
        let placed = goals.compactMap { goal in times[goal.id].map { (goal: goal, start: $0) } }
        let saved = calendar.placeGoals(placed, on: day)
        book.schedule(times, on: day)
        let missed = open.filter { times[$0.id] == nil }.count
        let fresh = open.count - kept - missed
        let plural = { (count: Int) in count == 1 ? "" : "s" }
        results[GoalBook.name(day)] = saved == 0 ? "Couldn't add them to your calendar. Check calendar access on the You page."
            : (kept == 0 ? "Planned \(fresh) goal\(plural(fresh)) into \(isTomorrow ? "tomorrow" : "today"), with reminders."
               : "Kept your \(kept) time\(plural(kept))." + (fresh == 0 ? " Nothing new to plan." : " Planned \(fresh) new goal\(plural(fresh))."))
              + (missed > 0 ? " \(missed) didn't fit around your calendar." : "")
        Task {
            if isTomorrow && !book.isDemo {
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
        let others = book.day(start).goals.filter { $0.id != goal.id }.compactMap { other in
            other.scheduled.map { DateInterval(start: $0, duration: Double(other.minutes) * 60) }
        }
        let overlaps = (calendar.busy(on: start) + others).contains { $0.start < end && $0.end > start }
        if overlaps { clashes.insert(goal.id) } else { clashes.remove(goal.id) }

        var moved = goal
        moved.scheduled = start
        calendar.updateGoal(moved)
        book.reschedule(goal, to: start, on: start)
        results[GoalBook.name(start)] = "Moved \(goal.title) to \(start.formatted(date: .omitted, time: .shortened))."
        guard !book.isDemo, Calendar.current.isDate(start, inSameDayAs: tomorrow) else { return }
        let planned = next.goals.compactMap { goal in goal.scheduled.map { (goal: goal, start: $0) } }
        Task { await GoalNotifications.morning(for: tomorrow, goals: planned, wake: preferences.quietEnd) }
    }

    /// Saves an edited goal of today's, and changes its calendar event to match if it has one.
    private func saveEdit(_ goal: Goal) {
        calendar.updateGoal(goal)
        book.edit(goal, on: now)
        clashes.remove(goal.id)
    }

    private func deleteGoal(_ goal: Goal) {
        var gone = goal
        gone.scheduled = nil
        calendar.updateGoal(gone)                          // takes its event off the calendar
        book.delete(goal, on: now)
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

/// One of today's goals, changed by hand: its name, how long it takes, and when, or deleted.
/// A goal already on the calendar moves there too.
private struct GoalEditor: View {
    let goal: Goal
    let day: Date
    let save: (Goal) -> Void
    let delete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var minutes: Int
    @State private var timed: Bool
    @State private var time: Date

    init(goal: Goal, day: Date, save: @escaping (Goal) -> Void, delete: @escaping () -> Void) {
        self.goal = goal
        self.day = day
        self.save = save
        self.delete = delete
        let named = goal.hour.flatMap { Calendar.current.date(bySettingHour: $0, minute: goal.minute ?? 0, second: 0, of: day) }
        let nextHour = Calendar.current.nextDate(after: .now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? day
        _title = State(initialValue: goal.title)
        _minutes = State(initialValue: goal.minutes)
        _timed = State(initialValue: goal.scheduled != nil || named != nil)
        _time = State(initialValue: goal.scheduled ?? named ?? nextHour)
    }

    private var lengths: [Int] { Array(Set([5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240, goal.minutes])).sorted() }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Goal", text: $title)
                Picker("Length", selection: $minutes) {
                    ForEach(lengths, id: \.self) { value in
                        Text(value < 60 ? "\(value) min" : value % 60 == 0 ? "\(value / 60) hr" : String(format: "%.1f hr", Double(value) / 60))
                            .tag(value)
                    }
                }
                Toggle("Time", isOn: $timed)
                if timed {
                    DatePicker("Starts", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                }
                if goal.scheduled != nil {
                    Text(timed ? "It's on your calendar, and moves there too." : "Turning the time off takes it off your calendar.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button("Delete goal", role: .destructive) {
                        delete()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(edited)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    /// The goal as you left it. The time is kept on the day being edited.
    private var edited: Goal {
        var goal = goal
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        let start = Calendar.current.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: day)
        goal.title = title.trimmingCharacters(in: .whitespaces)
        goal.minutes = minutes
        goal.hour = timed ? parts.hour : nil
        goal.minute = timed ? parts.minute : nil
        if goal.scheduled != nil { goal.scheduled = timed ? start : nil }
        return goal
    }
}
