import SwiftUI
import EventKit
import WidgetKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var health: HealthManager
    @State private var calendar: CalendarManager
    @State private var chat: ChatManager
    @State private var voice: VoiceManager
    @State private var diary = EnergyDiary()
    @State private var notifications = NotificationManager()
    @State private var gemini: GeminiAccess

    @State private var showChat = false
    @State private var askGemini = false
    /// Moved on at the top of each hour, when the drain curve and the widget move on.
    @State private var now = Date.now
    @State private var energy: EnergyReading?
    @State private var todayFeatures: [String: Double]?
    @State private var coverage: [String: Int] = [:]
    @State private var nightsFound = 0
    @State private var week: [(date: Date, band: EnergyReading.Band?)] = []
    @State private var searchedDays = 0
    @State private var sleepWeek: [Double?] = []
    @State private var weights: [WeightSample] = []
    /// Apple Health has a workout recorded today, so the plan stops suggesting one.
    @State private var trainedToday = false
    @State private var loggingWeight = false
    @State private var dismissed = DismissedSuggestions.today()
    /// Your finger is down on Dash: listening lasts as long as you hold him.
    @State private var holding = false
    /// When the last hold ended, so letting go doesn't also count as a tap.
    @State private var heldUntil = Date.distantPast

    private let energyModel = EnergyModel()

    init() {
        // The chat uses the same health and calendar data the home screen shows, and speaks
        // through the same voice that listens for "twin".
        let health = HealthManager()
        let calendar = CalendarManager()
        let voice = VoiceManager()
        let gemini = GeminiAccess()
        _health = State(initialValue: health)
        _calendar = State(initialValue: calendar)
        _voice = State(initialValue: voice)
        _gemini = State(initialValue: gemini)
        _chat = State(initialValue: ChatManager(calendar: calendar, health: health, gemini: gemini, voice: voice))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    header
                    Group {
                        DashboardSection(title: "Predictions") {
                            PredictionsCard(points: DayCharge.forecast(from: dayStart, until: bedtimeDate))
                        }
                        DashboardSection(title: "Today's activity") { activity }
                        DashboardSection(title: "Today's plan") { plan }
                        if health.isAuthorized, todayFeatures != nil, !diary.ratedToday() {
                            ratingRow.dashboardCard()
                        }
                        if health.isAuthorized, !week.isEmpty {
                            DashboardSection(title: "Your last 7 days") { WeekStrip(days: week).dashboardCard() }
                        }
                        if health.isAuthorized {
                            DashboardSection(title: "What myTwin can read") {
                                CoverageSection(coverage: coverage, windowDays: 90).dashboardCard()
                            }
                        }
                        if let error = health.errorMessage {
                            Text(error).foregroundStyle(.red)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 24)
            }
            .background { BatteryBackdrop(energy: charge * 100) }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Ask myTwin", systemImage: "bubble.left.and.text.bubble.right") {
                    showChat = true
                }
            }
            .sheet(isPresented: $loggingWeight) {
                LogWeightSheet(last: weights.last?.pounds) { pounds in
                    try await health.logWeight(pounds: pounds)
                    weights = await health.weights()
        trainedToday = await !health.workoutsToday().isEmpty
                }
            }
            .sheet(isPresented: $askGemini) {
                GeminiPermissionSheet { gemini.allowed = $0 }
            }
            .navigationDestination(isPresented: $showChat) {
                ChatView(chat: chat, voice: voice)
            }
            .safeAreaInset(edge: .bottom) { voiceBar }
            .task {
                askGemini = gemini.needsAnswer      // once; the answer is remembered
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
                        await health.refresh()          // your watch may have synced since
                        await updateEnergy()
                        await listen()
                    case .background:
                        chat.endGemini()
                        await voice.stopLiveVoice()
                    default: break
                    }
                }
            }
            // Read each new answer aloud, whichever screen you're on.
            .onChange(of: chat.messages.count) { _, _ in
                guard let last = chat.messages.last, !last.isUser, !last.byGemini else { return }
                voice.speak(last.text)
            }
        }
    }

    // MARK: - Pieces of the screen

    private var header: some View {
        VStack(spacing: 10) {
            BrandTitle()
            Avatar3DView(energy: charge * 100)
                .containerRelativeFrame(.vertical) { height, _ in max(height * 0.7, 320) }
                .overlay { if voice.isDictating { ListeningRing() } }
                .onTapGesture(perform: talk)
                .gesture(HoldToTalk(began: startHolding, ended: stopHolding))
                .accessibilityLabel("Your twin, \(Int(charge * 100)) percent charged. Tap to talk.")
                .accessibilityHint(voice.isDictating ? "Tap again when you're done" : "Tap to start, or hold while you talk")
            chargeLabel
            verdict
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 44)      // room above for the title's glow
    }

    /// Steps, energy, sleep and weight, or the button to connect Apple Health.
    @ViewBuilder private var activity: some View {
        if health.isAuthorized {
            ActivityGrid(steps: health.snapshot.steps, activeEnergy: health.snapshot.activeEnergyKcal,
                         sleepWeek: sleepWeek, weights: weights) { loggingWeight = true }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Button("Connect Apple Health") {
                    Task { await health.requestAuthorization(); await updateEnergy() }
                }
                .buttonStyle(.borderedProminent)
                .tint(BrandTitle.brand[1])
                Text("myTwin reads your sleep, heart rate, activity and weight to work out how today compares with your normal.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .dashboardCard()
        }
    }

    /// Today's events with suggestions in the free time, or the button to connect the calendar.
    @ViewBuilder private var plan: some View {
        if calendar.isAuthorized {
            SmartCalendar(allDay: calendar.events.filter(\.isAllDay).map { $0.title ?? "Untitled" },
                          items: DayPlanner.plan(events: DayPlanner.items(from: calendar.events),
                                                 dayStart: dayStart, now: .now, bedtime: bedtimeDate,
                                                 excluding: dismissed, trained: trainedToday,
                                                 easyDay: energy?.band == .below),
                          now: .now,
                          accept: { calendar.add(title: $0.title, start: $0.start, end: $0.end) },
                          dismiss: { item in
                              DismissedSuggestions.add(item.title)
                              withAnimation { dismissed = DismissedSuggestions.today() }
                          })
            if let error = calendar.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Button("Connect Calendar") {
                    Task { await calendar.requestAccess() }
                }
                .buttonStyle(.borderedProminent)
                .tint(BrandTitle.brand[1])
                if let error = calendar.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
            }
            .dashboardCard()
        }
    }

    /// Your usual bedtime, tonight: where the forecast and the plan stop.
    private var bedtimeDate: Date {
        let (hour, minute) = notifications.bedtime
        let tonight = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
        return hour < 12 ? tonight.addingTimeInterval(86_400) : tonight    // after midnight: tomorrow
    }

    /// Where today's charge started, from the morning prediction. The widget reads the same
    /// number (see TwinState), so the app and the widget always agree.
    /// Until today's reading is worked out, the charge the widget and the app icon are
    /// already showing: starting from a guess made the twin change colour a second in.
    private var dayStart: Double {
        guard let energy, let energyModel else { return TwinState.dayStart() }
        return energyModel.dayStart(for: energy)
    }

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
        VStack(spacing: 10) {
            if voice.isDictating || chat.isResponding || calendar.pendingChange != nil {
                InlineConversation(isListening: voice.isDictating, hint: voice.listeningHint,
                                   isThinking: chat.isResponding, change: calendar.pendingChange,
                                   confirm: chat.confirmChange, cancel: chat.cancelChange)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let note = voice.statusNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(voice.isAwake ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .animation(.snappy, value: chat.isResponding)
    }

    // MARK: - Actions

    private func record(rating: Double) {
        guard let todayFeatures else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        diary.record(rating: rating, features: todayFeatures)
        Task { await updateEnergy() }
    }

    /// Tap Dash to talk and tap again when you're done, or hold him while you talk.
    /// Either way, no pause ever cuts you off.
    private func talk() {
        guard !holding, Date.now.timeIntervalSince(heldUntil) > 0.4 else { return }  // that was a hold
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        if voice.isDictating { voice.finishDictation() } else { voice.startDictation() }
    }

    /// Holding Dash listens for as long as you hold him.
    private func startHolding() {
        guard !holding else { return }
        holding = true
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        voice.startDictation(untilRelease: true)
    }

    private func stopHolding() {
        guard holding else { return }
        holding = false
        heldUntil = .now
        voice.finishDictation()
    }

    /// Listens for "twin" from the moment the app opens. Answers appear under Dash.
    private func listen() async {
        await voice.startLiveVoice { sentence in
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
        sleepWeek = history.prefix(7).reversed().map { $0.asleepMinutes.map { $0 / 60 } }
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
        weights = await health.weights()
        await TwinRefresh.schedule(reading: energy, dayStart: dayStart,
                                   bedtime: health.typicalBedtime(from: history),
                                   calendar: calendar, trained: trainedToday, through: notifications)
    }

    /// Hands today's starting charge to the widget and puts the matching face on the app
    /// icon, so the app, the widget and the icon all show the same twin.
    private func shareMood() {
        TwinRefresh.share(dayStart: dayStart)
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
