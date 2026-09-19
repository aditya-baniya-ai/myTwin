import SwiftUI
import EventKit
import WidgetKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var health: HealthManager
    @State private var calendar: CalendarManager
    @State private var chat: ChatManager
    @State private var voice = VoiceManager()
    @State private var diary = EnergyDiary()
    @State private var avatars = AvatarManager.shared
    @State private var notifications = NotificationManager()

    @State private var showChat = false
    @State private var showPicker = false
    /// The visible height of the screen, so the twin can take up most of it.
    @State private var screenHeight: CGFloat = 0
    /// Moved on at the top of each hour, when the drain curve and the widget move on.
    @State private var now = Date.now
    @State private var energy: EnergyReading?
    @State private var todayFeatures: [String: Double]?
    @State private var coverage: [String: Int] = [:]
    @State private var nightsFound = 0
    @State private var week: [(date: Date, band: EnergyReading.Band?)] = []
    @State private var searchedDays = 0

    private let energyModel = EnergyModel()

    init() {
        // The chat uses the same health and calendar data the home screen shows.
        let health = HealthManager()
        let calendar = CalendarManager()
        _health = State(initialValue: health)
        _calendar = State(initialValue: calendar)
        _chat = State(initialValue: ChatManager(calendar: calendar, health: health))
    }

    var body: some View {
        NavigationStack {
            List {
                header

                // See-through cards, so the body-battery glow shows behind them too.
                Group {
                if health.isAuthorized, !week.isEmpty {
                    Section("Your last 7 days") { WeekStrip(days: week) }
                }
                if health.isAuthorized {
                    Section("Today's activity") {
                        ActivityRings(energyKcal: health.snapshot.activeEnergyKcal,
                                      steps: health.snapshot.steps,
                                      sleepHours: health.snapshot.sleepHours)
                    }
                    if todayFeatures != nil, !diary.ratedToday() {
                        Section { ratingRow }
                    }
                } else {
                    Section {
                        Button("Connect Apple Health") {
                            Task { await health.requestAuthorization(); await updateEnergy() }
                        }
                    } footer: {
                        Text("myTwin reads your sleep, heart rate and activity to work out how today compares with your normal.")
                    }
                }

                Section("Today's calendar") {
                    if !calendar.isAuthorized {
                        Button("Connect Calendar") {
                            Task { await calendar.requestAccess() }
                        }
                        if let error = calendar.errorMessage {
                            Text(error).foregroundStyle(.red)
                        }
                    } else if calendar.events.isEmpty {
                        Text("No events today").foregroundStyle(.secondary)
                    } else {
                        ForEach(calendar.events, id: \.self) { event in
                            LabeledContent(event.title ?? "Untitled", value: event.timeText)
                        }
                    }
                }

                Section("Reminders") { remindersRows }

                if health.isAuthorized {
                    Section("What myTwin can read") {
                        CoverageSection(coverage: coverage, windowDays: 90)
                    }
                }
                if let error = health.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
                }
                .listRowBackground(Color(.secondarySystemGroupedBackground).opacity(0.72))
            }
            .scrollContentBackground(.hidden)
            .background { BatteryBackdrop(energy: charge * 100) }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { screenHeight = $0 }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Ask myTwin", systemImage: "bubble.left.and.text.bubble.right") {
                    showChat = true
                }
            }
            .navigationDestination(isPresented: $showChat) {
                ChatView(chat: chat, voice: voice)
            }
            .sheet(isPresented: $showPicker) {
                AvatarPicker(avatars: avatars, energy: charge * 100)
            }
            .safeAreaInset(edge: .bottom) { voiceBar }
            .task {
                await health.refreshAuthorizationState()
                calendar.loadTodayEvents()
                await updateEnergy()
                await listen()
            }
            .task { await followTheHours() }
            .refreshable {
                await health.refresh()
                calendar.loadTodayEvents()
                await updateEnergy()
            }
            // Don't hold the microphone while the app is in the background.
            .onChange(of: scenePhase) { _, phase in
                Task {
                    switch phase {
                    case .active:
                        now = .now
                        TwinIcon.show(mood)
                        await listen()
                    case .background: await voice.stopLiveVoice()
                    default: break
                    }
                }
            }
            // Read each new answer aloud, whichever screen you're on.
            .onChange(of: chat.messages.count) { _, _ in
                guard let last = chat.messages.last, !last.isUser else { return }
                voice.speak(last.text)
            }
        }
    }

    // MARK: - Pieces of the screen

    private var header: some View {
        Section {
            VStack(spacing: 10) {
                BrandTitle()
                // A still while the picker is open: its preview is then the one live scene.
                Avatar3DView(character: avatars.selected, energy: charge * 100,
                             isLive: !showPicker || Avatar3DView.drawsOnlyFirstScene)
                    .frame(height: max(screenHeight * 0.7, 320))
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        showChat = true
                    }
                    .onLongPressGesture { showPicker = true }
                    .accessibilityLabel("Your twin, \(Int(charge * 100)) percent charged. Tap to chat.")
                chargeLabel
                Button("Change character") { showPicker = true }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(BrandTitle.brand[1])
                verdict
                    .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 44)      // room for the title's glow inside the row
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets())      // full width, so the glow isn't cut off at the sides
    }

    /// Each reminder says why it is worth following, not just what to do.
    @ViewBuilder private var remindersRows: some View {
        ForEach(NotificationManager.Kind.allCases) { kind in
            Toggle(isOn: Binding(get: { notifications.isOn(kind) },
                                 set: { _ in Task { await notifications.toggle(kind) } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                    Text(kind.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(BrandTitle.brand[1])
        }
        if notifications.permissionDenied {
            Text("Notifications are turned off for myTwin. Turn them on in Settings.")
                .font(.caption)
                .foregroundStyle(.red)
        } else if notifications.isOn(.bedtime) || notifications.isOn(.caffeine) {
            Text("Timed against your usual bedtime of \(notifications.bedtimeText).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Where today's charge started, from the morning prediction. The widget reads the same
    /// number (see TwinState), so the app and the widget always agree.
    private var dayStart: Double { energyModel?.dayStart(for: energy) ?? DayCharge.unknownDay }

    /// Right now, as a fraction: the prediction sets the start, the clock drains it.
    private var charge: Double { DayCharge.remaining(from: dayStart, at: now) }

    private var mood: AvatarEnergyState { AvatarEnergyState(score: charge * 100) }

    private var chargeLabel: some View {
        Text("\(Int(charge * 100))% charged")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .contentTransition(.numericText())
    }

    @ViewBuilder private var verdict: some View {
        if let energy {
            VStack(spacing: 4) {
                Text(energy.headline)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(energy.explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else if !health.isAuthorized {
            Text("Connect Apple Health to see how today compares with your normal.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } else {
            VStack(spacing: 4) {
                Text(nightsFound == 0
                     ? "No nights with sleep or heart data found\(searchedDays > 0 ? " in the last \(searchedDays) days" : "")."
                     : "Found \(nightsFound) night\(nightsFound == 1 ? "" : "s") of data in the last \(searchedDays) days.")
                    .font(.footnote)
                Text("myTwin needs at least \(EnergyModel.minimumNights) to compare today with your normal.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
    }

    /// Asking is the only way the app can learn what a good day feels like for you.
    @ViewBuilder private var ratingRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How's your energy today?")
                .font(.subheadline.weight(.medium))
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { value in
                    Button("\(value)") { record(rating: Double(value)) }
                        .buttonStyle(.bordered)
                        .tint(BrandTitle.brand[1])
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var voiceBar: some View {
        if let note = voice.statusNote {
            Text(note)
                .font(.footnote)
                .foregroundStyle(voice.isAwake ? Color.accentColor : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(.bar)
        }
    }

    // MARK: - Actions

    private func record(rating: Double) {
        guard let todayFeatures else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        diary.record(rating: rating, features: todayFeatures)
        Task { await updateEnergy() }
    }

    /// Listens for "my twin" from the moment the app opens.
    private func listen() async {
        await voice.startLiveVoice { sentence in
            showChat = true  // open the conversation so you can see what it heard
            guard !chat.isResponding else { return }
            Task { await chat.send(sentence) }
        }
    }

    private func updateEnergy() async {
        defer { shareMood() }           // even without Health data: then it is an average day
        guard health.isAuthorized, let energyModel else { return }
        let (history, searched) = await health.history()
        searchedDays = searched
        nightsFound = energyModel.usableNights(in: history).count
        todayFeatures = energyModel.features(from: history)
        // Replay the model for each of the last seven days, using only what was known then.
        week = (0..<7).compactMap { offset in
            let slice = Array(history.dropFirst(offset))
            guard let day = slice.first else { return nil }
            return (day.date, energyModel.reading(from: slice, diary: diary)?.band)
        }
        withAnimation(.easeOut(duration: 0.4)) {
            energy = energyModel.reading(from: history, diary: diary)
        }
        coverage = await health.coverage(days: 90)
        await notifications.reschedule(bedtime: health.typicalBedtime(from: history))
    }

    /// Hands today's starting charge to the widget and puts the matching face on the app
    /// icon, so the app, the widget and the icon all show the same twin.
    private func shareMood() {
        TwinState.save(dayStart: dayStart)
        WidgetCenter.shared.reloadAllTimelines()
        TwinIcon.show(mood)
    }

    /// Wakes at the top of each hour, when the charge (and the mood) can change.
    private func followTheHours() async {
        while !Task.isCancelled {
            let nextHour = Calendar.current.nextDate(after: .now, matching: DateComponents(minute: 0),
                                                     matchingPolicy: .nextTime) ?? .now.addingTimeInterval(3600)
            try? await Task.sleep(for: .seconds(max(nextHour.timeIntervalSinceNow, 1)))
            now = .now
            TwinIcon.show(mood)
        }
    }
}

#Preview {
    ContentView()
}
