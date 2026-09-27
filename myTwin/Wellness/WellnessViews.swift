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
                if isSample { Text("Sample data · not your health records").foregroundStyle(.orange) }
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
                    Label(daily.isSample ? "Sample day · no real calendar changes" : "A smaller plan still counts", systemImage: "leaf.fill")
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
                            Button(saving ? "Saving…" : (daily.isSample ? "Confirm sample change" : "Confirm calendar change")) { confirm(proposal) }
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

struct ActionFeedbackView: View {
    let daily: DailySupport
    let now: Date
    let share: (PlannedAction) -> Void
    private var recent: [PlannedAction] {
        daily.actions.filter { $0.tracksOutcome != false && $0.start <= now && $0.end > now.addingTimeInterval(-2 * 86400) }
            .sorted { $0.start > $1.start }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Did that help?").font(.title3.bold())
            if recent.isEmpty { Text("After an activity you've accepted, check in here. Your feedback stays on this device.").foregroundStyle(.secondary) }
            ForEach(recent) { action in
                VStack(alignment: .leading, spacing: 10) {
                    Label(action.title, systemImage: action.movement.symbol).font(.headline)
                    if action.skipped { Text("Skipped — no problem. Another day, another plan.").font(.subheadline) }
                    else if let outcome = action.outcome {
                        Text("You reported feeling \(outcome.title.lowercased()).").font(.subheadline)
                        Button("Share my moment", systemImage: "square.and.arrow.up") { share(action) }
                    } else {
                        Text("Did you do this activity? If so, how do you feel now?").font(.subheadline)
                        HStack {
                            ForEach(ActionOutcome.allCases) { outcome in
                                Button(outcome.title) { daily.finish(action, outcome: outcome) }.buttonStyle(.bordered)
                            }
                        }
                        Button("I skipped it") { daily.finish(action, outcome: nil, skipped: true) }.font(.caption)
                    }
                    if let evidence = daily.evidence(for: action.movement) { Text(evidence).font(.caption).foregroundStyle(.secondary) }
                }.dashboardCard()
            }
        }
    }
}

struct DashShareView: View {
    @Environment(\.dismiss) private var dismiss
    let action: PlannedAction
    let isSample: Bool
    @State private var includeDetails = false
    @State private var file: URL?
    @State private var image: UIImage?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    card.frame(maxWidth: 360)
                    Toggle("Include the activity's title and time", isOn: $includeDetails)
                    Text("Health numbers and calendar details are hidden by default. Preview before sharing.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let file, let image {
                        ShareLink(item: file, preview: SharePreview("My day with Dash", image: Image(uiImage: image))) {
                            Label("Share card", systemImage: "square.and.arrow.up")
                        }.buttonStyle(.borderedProminent)
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                }.padding()
            }
            .navigationTitle("My day with Dash")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { render() }
            .onChange(of: includeDetails) { render() }
        }
    }
    private var card: some View {
        VStack(spacing: 12) {
            Text("myTwin").font(.title.bold()).foregroundStyle(.cyan)
            if isSample { Text("SAMPLE DAY").font(.caption.bold()).foregroundStyle(.orange) }
            Image("Dash_normal").resizable().scaledToFit().frame(height: 220)
            Text(action.completedAt != nil ? "Plan changed. Still showed up." : "A smaller plan still counts.")
                .font(.title2.bold()).multilineTextAlignment(.center)
            Text(includeDetails ? action.title : action.movement.title).font(.headline)
            Text("\(Int(action.end.timeIntervalSince(action.start) / 60)) minutes for myself")
            if includeDetails { Text(timeRangeText(action.start, action.end)).font(.caption) }
            Text(action.completedAt != nil ? "Activity completed · self-reported" : "Activity planned · one step at a time")
                .font(.caption).foregroundStyle(.white.opacity(0.8))
        }
        .padding(24).frame(width: 360)
        .foregroundStyle(.white)
        .background(LinearGradient(colors: [.indigo, Color(red: 0.06, green: 0.06, blue: 0.15)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }
    @MainActor private func render() {
        file = nil
        image = nil
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let output = renderer.uiImage, let data = output.pngData() else { error = "Couldn't create the card. Please reopen this screen."; return }
        do {
            let url = FileManager.default.temporaryDirectory.appending(path: "Dash-\(UUID().uuidString).png")
            try data.write(to: url, options: .atomic)
            file = url
            image = output
            error = nil
        } catch { self.error = "Couldn't save the share card. Please try again." }
    }
}
