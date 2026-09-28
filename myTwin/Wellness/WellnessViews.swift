import SwiftUI
import EventKit

struct PlanningPreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @State var preferences: PlanningPreferences
    var save: (PlanningPreferences) -> Void
    private var bedtime: Binding<Date> {
        Binding(get: { preferences.bedtime(on: .now) }, set: {
            preferences.bedtimeHour = Calendar.current.component(.hour, from: $0)
            preferences.bedtimeMinute = Calendar.current.component(.minute, from: $0)
        })
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("What fits you") {
                    Picker("Preferred activity", selection: $preferences.movement) {
                        ForEach(Movement.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Usual time available", selection: $preferences.minutes) {
                        ForEach([10, 15, 20, 30, 45, 60], id: \.self) { Text("\($0) minutes").tag($0) }
                    }
                    Toggle("I have strength equipment", isOn: $preferences.hasEquipment)
                    DatePicker("Bedtime", selection: bedtime, displayedComponents: .hourAndMinute)
                }
                Section {
                    optionalGoal("Step goal", value: $preferences.stepGoal, initial: 6000, range: 100...100000)
                    optionalGoal("Active energy goal (kcal)", value: $preferences.activeEnergyGoal, initial: 300, range: 10...5000)
                    optionalGoal("Weight goal (lb)", value: $preferences.weightGoal, initial: 150, range: 50...700)
                    Stepper("Sleep goal: \(preferences.sleepGoal, specifier: "%.1f") hours", value: $preferences.sleepGoal, in: 4...12, step: 0.5)
                } header: { Text("Optional goals") } footer: {
                    Text("These are your choices, not targets prescribed by myTwin. Weight tracking never affects your energy forecast.")
                }
                Section {
                    Toggle("Morning check-in", isOn: $preferences.morningReminder)
                    Toggle("Before calendar events", isOn: $preferences.eventReminders)
                    Toggle("Wind down before bed", isOn: $preferences.bedtimeReminder)
                    Toggle("Bedtime in my calendar", isOn: $preferences.addsBedtimeEvent)
                    Picker("Quiet hours start", selection: $preferences.quietStart) { hours }
                    Picker("Quiet hours end", selection: $preferences.quietEnd) { hours }
                } header: { Text("Reminders") } footer: {
                    Text("Reminders are optional. Equal quiet-hour times disable quiet hours. Tomorrow's reminder always asks for a fresh check-in.")
                }
            }
            .navigationTitle("Make it yours")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(preferences); dismiss() } }
            }
        }
    }
    @ViewBuilder private var hours: some View {
        ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
    }
    private func optionalGoal(_ title: String, value: Binding<Double?>, initial: Double, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            Toggle(title, isOn: Binding(get: { value.wrappedValue != nil }, set: { value.wrappedValue = $0 ? initial : nil }))
            if value.wrappedValue != nil {
                HStack {
                    Text("Target")
                    Spacer()
                    TextField("Target", value: Binding(get: { value.wrappedValue ?? initial }, set: {
                        value.wrappedValue = min(max($0, range.lowerBound), range.upperBound)
                    }), format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    .accessibilityLabel(title)
                }
            }
        }
    }
}

struct EnergyExplanationView: View {
    @Environment(\.dismiss) private var dismiss
    let history: [DaySignals]
    let reading: EnergyReading?
    let checkIn: ReportedEnergy?
    let isSample: Bool
    let report: (ReportedEnergy) -> Void
    private var baseline: [DaySignals] { EnergyModel()?.usableNights(in: history) ?? [] }
    var body: some View {
        NavigationStack {
            List {
                if isSample { Text("Demo data · not your health records").foregroundStyle(.orange) }
                Section("What was measured") {
                    LabeledContent("Last night's sleep", value: sleepText(history.first?.asleepMinutes))
                    LabeledContent("Recent usual sleep", value: sleepText(averageSleep))
                    LabeledContent("Usable nights in the last 14 days", value: "\(baseline.count)")
                    Text("Sleep comes from Apple Health when connected. Missing data stays missing.").font(.footnote)
                }
                Section("What is estimated") {
                    Text(reading?.headline ?? "Still learning — at least seven recent nights and today's sleep are needed.")
                    if let reading { Text(reading.explanation).font(.footnote) }
                    Text("The hourly curve is a shared pattern, not a measurement of your body's battery. Its percentages are illustrative. It cannot establish how a walk, nap, or coffee will affect you.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Your experience comes first") {
                    if let checkIn { Text("Your latest check-in: \(checkIn.title). This is self-reported.") }
                    Text("How do you actually feel? Your answer adjusts today's activity suggestions without rewriting the measured sleep data.")
                    ForEach(ReportedEnergy.allCases) { value in
                        Button(value == .okay ? "Actually, I feel okay" : "I feel \(value.title.lowercased())") {
                            report(value)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Why this plan?")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
    private var averageSleep: Double? {
        let values = baseline.compactMap(\.asleepMinutes)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
    private func sleepText(_ minutes: Double?) -> String {
        guard let minutes else { return "No data" }
        return "\(Int(minutes) / 60)h \(Int(minutes) % 60)m"
    }
}

struct RescueDayView: View {
    @Environment(\.dismiss) private var dismiss
    let daily: DailySupport
    let calendar: CalendarManager
    let events: () -> [PlanItem]
    let now: () -> Date
    let allowed: () -> Bool
    var initialMinutes: Int? = nil
    let confirmed: (PlannedAction, PlannedAction?) -> Void
    @State private var minutes = 20
    @State private var movement: Movement = .walk
    @State private var selected: UUID?
    @State private var proposal: RescueProposal?
    @State private var problem: String?
    @State private var saving = false
    /// Off: the next free time. On: the user picks when, and the first free slot from then is used.
    @State private var choosingTime = false
    @State private var preferredStart = Date.now

    private var originals: [PlannedAction] {
        daily.actions.filter { $0.tracksOutcome != false && $0.start > now() && !$0.skipped && $0.completedAt == nil &&
            (daily.isSample || calendar.matches($0)) }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label(daily.isSample ? "Demo · no real calendar changes" : "A smaller plan still counts", systemImage: "leaf.fill")
                        .foregroundStyle(.green).font(.headline)
                    Text("Choose what feels manageable. Dash will find a free gap and show you the change before saving it.")
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Adapt", selection: $selected) {
                            Text("Add a new flexible activity").tag(UUID?.none)
                            ForEach(originals) { Text("\($0.title) · \(Int($0.end.timeIntervalSince($0.start) / 60)) min").tag(Optional($0.id)) }
                        }
                        Picker("Activity", selection: $movement) {
                            ForEach(Movement.allCases) { Text($0.title).tag($0) }
                        }
                        Picker("Time I have", selection: $minutes) {
                            ForEach([5, 10, 15, 20, 30, 45, 60], id: \.self) { Text("\($0) min").tag($0) }
                        }
                        Toggle("Choose the time", isOn: $choosingTime)
                        if choosingTime {
                            DatePicker("Start", selection: $preferredStart,
                                       in: now()...max(now(), daily.preferences.bedtime(on: now())),
                                       displayedComponents: .hourAndMinute)
                        }
                    }.dashboardCard()
                    if let evidence = daily.evidence(for: movement) { Text(evidence).font(.footnote).foregroundStyle(.secondary) }
                    if daily.suggestedMovement != daily.preferences.movement {
                        Text("Your repeated feedback suggests trying a different activity. You can always choose your usual one.").font(.footnote)
                    }
                    Button("Preview my rescue", systemImage: "wand.and.stars") { preview() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!allowed())
                    if let proposal {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Your proposed change").font(.headline)
                            if let original = proposal.original {
                                timeline("Before", title: original.title, start: original.start, end: original.end, tint: .secondary)
                            } else { Text("Before: no flexible activity in this gap.").font(.subheadline).foregroundStyle(.secondary) }
                            Image(systemName: "arrow.down").foregroundStyle(.secondary)
                            timeline("After", title: proposal.replacement.title, start: proposal.replacement.start,
                                     end: proposal.replacement.end, tint: .green)
                            Text(proposal.reason).font(.subheadline)
                            Text("Fixed appointments stay where they are. Only myTwin activities shown above can change.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button(saving ? "Saving…" : (daily.isSample ? "Confirm demo change" : "Confirm calendar change")) { confirm(proposal) }
                                .buttonStyle(.borderedProminent).disabled(saving || !allowed())
                        }.dashboardCard()
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    if let problem { Text(problem).foregroundStyle(.red).accessibilityIdentifier("rescueError") }
                    if !allowed() { Text("Rescue my day requires myTwin Pro.") }
                    Text("This changes a plan, not your measured energy. You can undo a saved rescue on the dashboard.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }
            .navigationTitle("Rescue my day")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear {
                minutes = initialMinutes ?? daily.preferences.minutes
                movement = daily.currentCheckIn == .low && daily.suggestedMovement == .strength ? .stretch : daily.suggestedMovement
                selected = originals.first?.id
                // Suggest the next quarter hour, a time people actually pick.
                let quarter = 15 * 60.0
                preferredStart = Date(timeIntervalSinceReferenceDate:
                    (now().timeIntervalSinceReferenceDate / quarter).rounded(.up) * quarter)
            }
            .onChange(of: minutes) { proposal = nil }
            .onChange(of: movement) { proposal = nil }
            .onChange(of: selected) { proposal = nil }
            .onChange(of: choosingTime) { proposal = nil }
            .onChange(of: preferredStart) { proposal = nil }
        }
    }
    private func timeline(_ label: String, title: String, start: Date, end: Date, tint: Color) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.caption.bold()).frame(width: 48, alignment: .leading)
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(timeRangeText(start, end)).font(.subheadline)
            }
        }.foregroundStyle(tint)
    }
    private func preview() {
        if !daily.isSample { calendar.loadTodayEvents() }
        let original = originals.first { $0.id == selected }
        guard selected == nil || original != nil else { problem = "That activity changed. Select an activity again."; proposal = nil; return }
        let busy = events().filter { $0.eventID != (original?.eventID ?? original?.id.uuidString) || original == nil }
            .map { DateInterval(start: $0.start, end: $0.end) }
        withAnimation(.snappy) {
            proposal = RescuePlanner.propose(original: original, busy: busy, movement: movement, minutes: minutes,
                                              preferences: daily.preferences, now: now(), energy: daily.currentCheckIn,
                                              preferred: choosingTime ? preferredStart : nil)
        }
        problem = proposal == nil ? "There isn't a free gap before bedtime. Try a shorter activity or keep today clear." : nil
    }
    private func confirm(_ preview: RescueProposal) {
        guard !saving, allowed() else { return }
        if !daily.isSample, preview.replacement.start < now() {
            self.preview()
            if proposal != nil { problem = "That time passed while you were deciding. Here's a fresh one; confirm again." }
            return
        }
        saving = true
        defer { saving = false }
        do {
            let saved = daily.isSample ? preview.replacement : try calendar.saveActivity(preview.replacement, replacing: preview.original, bedtime: preview.bedtime)
            daily.save(saved, replacing: preview.original)
            confirmed(saved, preview.original)
            dismiss()
        } catch { problem = error.localizedDescription; proposal = nil }
    }
}

/// "Did that help?" once an activity you took up has ended, one card for each you haven't
/// answered. An answer puts the card away; with nothing left to ask, it shows what's next.
struct ActionFeedbackView: View {
    let daily: DailySupport
    let now: Date
    /// The next thing on the calendar and a line on how to do well in it.
    var upNext: (item: PlanItem, tip: String)?

    /// Finished, unanswered, and from the last two days.
    private var waiting: [PlannedAction] {
        daily.actions.filter {
            $0.tracksOutcome != false && $0.outcome == nil && !$0.skipped
                && $0.end <= now && $0.end > now.addingTimeInterval(-2 * 86400)
        }
        .sorted { $0.end > $1.end }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !waiting.isEmpty {
                Text("Did that help?").font(.title3.bold())
                ForEach(waiting) { action in
                    VStack(alignment: .leading, spacing: 10) {
                        Label(action.title, systemImage: action.movement.symbol).font(.headline)
                        Text("Did you do this activity? If so, how do you feel now?").font(.subheadline)
                        HStack {
                            ForEach(ActionOutcome.allCases) { outcome in
                                Button(outcome.title) { answer(action, outcome) }.buttonStyle(.bordered)
                            }
                        }
                        Button("I skipped it") { answer(action, nil) }.font(.caption)
                        if let evidence = daily.evidence(for: action.movement) {
                            Text(evidence).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .dashboardCard()
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            } else if let upNext {
                Text("Up next").font(.title3.bold())
                UpNextCard(item: upNext.item, tip: upNext.tip, now: now)
                    .transition(.opacity)
            }
        }
        .animation(.snappy, value: waiting.map(\.id))
    }

    private func answer(_ action: PlannedAction, _ outcome: ActionOutcome?) {
        daily.finish(action, outcome: outcome, skipped: outcome == nil)
    }
}

struct UpNextCard: View {
    let item: PlanItem
    let tip: String
    let now: Date

    private var when: String {
        let minutes = Int(item.start.timeIntervalSince(now) / 60)
        let lead = minutes < 60 ? "In \(max(minutes, 1)) min" : "At \(item.start.formatted(date: .omitted, time: .shortened))"
        return "\(lead) · \(timeRangeText(item.start, item.end))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Capsule().fill(item.color).frame(width: 4, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.headline)
                    Text(when).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Label(tip, systemImage: "lightbulb.fill")
                .font(.subheadline)
                .symbolRenderingMode(.multicolor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCard()
        .accessibilityElement(children: .combine)
    }
}
