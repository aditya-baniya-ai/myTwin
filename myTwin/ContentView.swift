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

    @State private var tab: TwinTab = .twin
    @State private var planSpan: PlanSpan = .day
    @State private var pro = Subscription()
    @State private var showPaywall = false
    @State private var showCustomerCentre = false
    @State private var showShowcase = false
    @State private var showVoicePicker = false
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
    @State private var workoutDetails: [WorkoutDetail] = []
    @State private var loggingWeight = false
    @State private var dismissed = DismissedSuggestions.today()

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
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(TwinTab.allCases) { page in
                        view(for: page)
                            .containerRelativeFrame(.horizontal)
                            .id(page)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: swiped)
            .scrollIndicators(.hidden)
            .background { BatteryBackdrop(energy: charge * 100) }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Next to the chat button: how he sounds, without going to the You page.
                Button("Dash's voice", systemImage: "waveform") {
                    showVoicePicker = true
                }
                Button("Ask myTwin", systemImage: "bubble.left.and.text.bubble.right") {
                    showChat = true
                }
            }
            .sheet(isPresented: $loggingWeight) {
                LogWeightSheet(last: weights.last?.pounds) { pounds in
                    try await health.logWeight(pounds: pounds)
                    weights = await health.weights()
                }
            }
            .sheet(isPresented: $askGemini) {
                GeminiPermissionSheet { gemini.allowed = $0 }
            }
            .navigationDestination(isPresented: $showChat) {
                ChatView(chat: chat, voice: voice)
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .task {
                askGemini = gemini.needsAnswer      // once; the answer is remembered
                await pro.start()
                await health.refreshAuthorizationState()
                calendar.loadTodayEvents()
                calendar.loadWeekEvents()
                await updateEnergy()
                await listen()
            }
            .task { await followTheHours() }
            .task { await pro.watchForChanges() }
            // Both models read today's plan through this, and only the screen knows the
            // day's charge, bedtime and what has been dismissed.
            .onAppear {
                chat.planSource.summary = { [self] in
                    TodayPlanText.summary(.init(dayStart: dayStart,
                                                bedtime: bedtimeDate,
                                                events: DayPlanner.items(from: calendar.events),
                                                dismissed: dismissed,
                                                trainedToday: trainedToday,
                                                easyDay: energy?.band == .below))
                }
            }
            .onChange(of: pro.isPro, initial: true) { chat.proEnabled = pro.isPro }
            .sheet(isPresented: $showShowcase) { AvatarShowcase() }
            .sheet(isPresented: $showVoicePicker) {
                VoicePicker(voice: voice, isPro: pro.isPro)
            }
            .sheet(isPresented: $showPaywall) { ProPaywall(pro: pro) }
            .sheet(isPresented: $showCustomerCentre) { ProCustomerCentre() }
            .refreshable {
                await health.refresh()
                calendar.loadTodayEvents()
                calendar.loadWeekEvents()
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

    // MARK: - The five pages

    /// The page you have swiped to. Tapping the bar sets it, which scrolls there.
    private var swiped: Binding<TwinTab?> {
        Binding(get: { tab }, set: { if let page = $0 { tab = page } })
    }

    @ViewBuilder private func view(for page: TwinTab) -> some View {
        switch page {
        case .twin: twinPage
        case .predictions: predictionsPage
        case .activity: activityPage
        case .plan: planPage
        case .you: youPage
        }
    }

    /// Dash himself, how charged he is, and one line about the day as it stands.
    /// Everything worth a glance under Dash: the forecast, today's numbers, what he
    /// suggests changing, and what he's connected to. Only the calendar is cut down — the
    /// whole day lives on the Plan page.
    private var twinPage: some View {
        ScrollView {
            VStack(spacing: 18) {
                twinContent
                    .containerRelativeFrame(.vertical)    // avatar fills the first screen

                if pro.isPro {
                    tabLink("Predictions", tab: .predictions) {
                        PredictionsCard(points: DayCharge.forecast(from: dayStart, until: bedtimeDate))
                    }
                } else {
                    LockedCard(title: "Your energy, hour by hour",
                               detail: "See where your peak lands and when the dip hits, before the day starts.") {
                        showPaywall = true
                    }
                }

                if health.isAuthorized {
                    tabLink("Activity", tab: .activity) {
                        ActivityGrid(steps: health.snapshot.steps,
                                     activeEnergy: health.snapshot.activeEnergyKcal,
                                     sleepWeek: sleepWeek, weights: weights) { loggingWeight = true }
                    }
                }

                suggestedChanges                          // the calendar, in brief

                tabLink("Connections", tab: .you) { connections }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }

    /// Today's suggestions in brief, with a way through to the calendar itself.
    private var suggestedChanges: some View {
        let today = DayPlanner.plan(events: DayPlanner.items(from: calendar.events), dayStart: dayStart,
                                    now: .now, bedtime: bedtimeDate, excluding: dismissed,
                                    trained: trainedToday, easyDay: energy?.band == .below)
        let suggestions = pro.isPro ? today.filter { $0.kind == .suggestion } : []
        return VStack(alignment: .leading, spacing: 10) {
            Text("Suggested changes")
                .font(.title3.weight(.bold))
                .padding(.leading, 4)
            if !pro.isPro {
                LockedCard(title: "Plans that fit your day",
                           detail: "A workout in your strongest free hour, a nap at the dip, the last coffee that still clears before bed.") {
                    showPaywall = true
                }
            }
            VStack(spacing: 12) {
                if !pro.isPro {
                    EmptyView()
                } else if suggestions.isEmpty {
                    Text("Nothing to change today.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(suggestions) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.symbol).foregroundStyle(item.color)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title).font(.subheadline.weight(.semibold))
                                Text(timeRangeText(item.start, item.end))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                Divider()
                Button {
                    withAnimation(.snappy) { tab = .plan }
                } label: {
                    HStack {
                        Text("See your full calendar").font(.subheadline.weight(.medium))
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(BrandTitle.brand[1])
            }
            .dashboardCard()
        }
    }

    /// He lifts for either way of starting: tapping him, or saying his name. Only the tap
    /// used to show, so the wake word worked with nothing on screen to prove it.
    private var listening: Bool { voice.isDictating || voice.isAwake }

    private var twinContent: some View {
        VStack(spacing: 10) {
            BrandTitle()
                .padding(.top, 20)
            Avatar3DView(energy: charge * 100)
                .frame(maxWidth: .infinity, maxHeight: .infinity)     // whatever is left
                .background { if listening { ListeningGlow() } }
                .scaleEffect(listening ? 1.03 : 1)                    // he lifts while listening
                .offset(y: listening ? -10 : 0)
                .animation(.spring(response: 0.45, dampingFraction: 0.7), value: listening)
                .onTapGesture(perform: talk)
                .accessibilityLabel("Your twin, \(Int(charge * 100)) percent charged. Tap to talk.")
                .accessibilityHint(voice.isDictating ? "Tap again when you're done" : "Tap to start listening")
            chargeLabel
            verdict
                .padding(.horizontal, 20)
            Text(DayGreeting.line(charge: charge, reading: energy, next: nextEvent,
                                  dayStart: dayStart, healthConnected: health.isAuthorized,
                                  userName: UserProfile().firstName))
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 4)
            meetDashButton
                .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity)
    }

    /// Opens the showcase: every state and every gesture Dash has, on demand.
    private var meetDashButton: some View {
        Button {
            showShowcase = true
        } label: {
            Label("See all of Dash", systemImage: "figure.walk.motion")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: .capsule)
                .overlay(Capsule().strokeBorder(.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows every energy state and gesture")
    }

    private var predictionsPage: some View {
        page("Predictions", tab: .predictions) {
            if pro.isPro {
                PredictionsCard(points: DayCharge.forecast(from: dayStart, until: bedtimeDate))
            } else {
                LockedCard(title: "Your energy, hour by hour",
                           detail: "See where your peak lands and when the dip hits, before the day starts.") {
                    showPaywall = true
                }
            }
            if health.isAuthorized, todayFeatures != nil, !diary.ratedToday() {
                ratingRow.dashboardCard()
            }
            if health.isAuthorized, !week.isEmpty {
                DashboardSection(title: "Your last 7 days") { WeekStrip(days: week).dashboardCard() }
            }
            oftenAsked
        }
    }

    /// The questions you keep asking, as one tap each. Hidden until there are a few, so it
    /// isn't an empty card on your first day.
    @ViewBuilder private var oftenAsked: some View {
        let asked = AskedQuestions.top()
        if !asked.isEmpty {
            DashboardSection(title: "You often ask") {
                VStack(spacing: 0) {
                    ForEach(asked) { item in
                        Button {
                            tab = .twin
                            Task { await chat.send(item.question) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.turn.down.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(BrandTitle.brand[1])
                                Text(item.question)
                                    .font(.subheadline)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 10)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        if item.id != asked.last?.id { Divider() }
                    }
                }
                .dashboardCard()
            }
        }
    }

    private var activityPage: some View {
        page("Today's activity", tab: .activity) {
            activity
            if health.isAuthorized {
                ActivityDetail(snapshot: health.snapshot, workouts: workoutDetails)
            }
        }
    }

    private var planPage: some View {
        page("Plan", tab: .plan) {
            Picker("Plan", selection: $planSpan) {
                Text("Day").tag(PlanSpan.day)
                Text("Week").tag(PlanSpan.week)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if planSpan == .day { plan } else { weekPlan }
        }
    }

    /// Today in detail, or the week at a glance.
    private enum PlanSpan { case day, week }

    private var weekPlan: some View {
        let days = Calendar.current
        let start = days.startOfDay(for: .now)
        let week = (0..<7).map { ahead -> (date: Date, allDay: [String], events: [PlanItem]) in
            let day = days.date(byAdding: .day, value: ahead, to: start) ?? start
            let onThatDay = calendar.week.filter { days.isDate($0.startDate, inSameDayAs: day) }
            return (day, onThatDay.filter(\.isAllDay).map { $0.title ?? "Untitled" },
                    DayPlanner.items(from: onThatDay))
        }
        return WeekPlan(days: week)
    }

    /// What myTwin is connected to and what it can actually read.
    private var youPage: some View {
        page("You", tab: .you) {
            voiceRow
            proRow
#if DEBUG
            proResetRow
#endif
            connections
            if health.isAuthorized {
                DashboardSection(title: "What myTwin can read") {
                    CoverageSection(coverage: coverage, windowDays: 90).dashboardCard()
                }
            }
            if let error = health.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    /// How Dash sounds, in both modes.
    private var voiceRow: some View {
        Button {
            showVoicePicker = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.title3)
                    .foregroundStyle(BrandTitle.brand[0])
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dash's voice")
                        .font(.subheadline.weight(.semibold))
                    Text("Try the voices and pick one")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .dashboardCard()
        }
        .buttonStyle(.plain)
    }

    /// Your plan: the paywall when you don't have Pro, RevenueCat's Customer Center when you do.
    private var proRow: some View {
        Button {
            if pro.isPro { showCustomerCentre = true } else { showPaywall = true }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: pro.isPro ? "bolt.heart.fill" : "lock.fill")
                    .font(.title3)
                    .foregroundStyle(BrandTitle.brand[1])
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pro.isPro ? "myTwin Pro" : "Get myTwin Pro")
                        .font(.subheadline.weight(.semibold))
                    Text(pro.isPro ? "Manage or restore your plan"
                                   : "The forecast, the plans, and Dash's full voice")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .dashboardCard()
        }
        .buttonStyle(.plain)
    }

#if DEBUG
    /// A way back to the free app while testing, since a Test Store purchase can't be cancelled.
    @ViewBuilder private var proResetRow: some View {
        if pro.isPro {
            Button {
                Task { await pro.resetForTesting() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title3)
                        .foregroundStyle(.orange)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reset to free")
                            .font(.subheadline.weight(.semibold))
                        Text("Testing only — a Test Store purchase can't be cancelled")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if pro.busy {
                        ProgressView()
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .dashboardCard()
            }
            .buttonStyle(.plain)
            .disabled(pro.busy)
        }
    }
#endif

    /// The same frame around every page but Dash's: a title, then cards.
    private func page<Content: View>(_ title: String, tab pageTab: TwinTab, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(title)
                    .font(.largeTitle.bold())
                    .padding(.leading, 4)
                content()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }

    /// A tappable summary section on the main dashboard. Tapping it switches to the
    /// corresponding detail tab so users can explore more.
    private func tabLink<Content: View>(_ title: String, tab destination: TwinTab,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.title3.weight(.bold))
                    .padding(.leading, 4)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.3)) { tab = destination }
        }
    }

    /// Where today's numbers come from, and whether each source is switched on.
    @ViewBuilder private var connections: some View {
        VStack(spacing: 14) {
            source("Apple Health", symbol: "heart.fill", tint: .pink,
                   state: health.isAuthorized ? "Connected" : "Not connected",
                   detail: "Sleep, heart rate, steps, workouts and weight") {
                Task { await health.requestAuthorization(); await updateEnergy() }
            }
            Divider()
            source("Calendar", symbol: "calendar", tint: .blue,
                   state: calendar.isAuthorized ? "Connected" : "Not connected",
                   detail: "Today's events, so the plan fits around them") {
                Task { await calendar.requestAccess() }
            }
            Divider()
            source("Gemini", symbol: "sparkles", tint: BrandTitle.brand[1],
                   state: gemini.allowed == true ? (gemini.isOnline ? "On, and online" : "On, offline just now")
                                                 : "Off, answers stay on your iPhone",
                   detail: "Smarter answers when you're online", action: nil)
        }
        .dashboardCard()
    }

    private func source(_ name: String, symbol: String, tint: Color, state: String, detail: String,
                        action: (() -> Void)?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline.weight(.semibold))
                Text(state).font(.caption).foregroundStyle(.secondary)
                Text(detail).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if let action, state.hasPrefix("Not") {
                Button("Connect", action: action)
                    .buttonStyle(.bordered)
                    .tint(tint)
            }
        }
    }

    /// The next thing on the calendar, which is usually what you want to know.
    private var nextEvent: (title: String, start: Date)? {
        calendar.events
            .filter { !$0.isAllDay && $0.startDate > .now }
            .min { $0.startDate < $1.startDate }
            .map { ($0.title ?? "Your next event", $0.startDate) }
    }

    // MARK: - Pieces of the screen

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

    /// The day's rows: your own events always, suggestions only with Pro.
    private var planItems: [PlanItem] {
        let full = DayPlanner.plan(events: DayPlanner.items(from: calendar.events),
                                   dayStart: dayStart, now: .now, bedtime: bedtimeDate,
                                   excluding: dismissed, trained: trainedToday,
                                   easyDay: energy?.band == .below)
        return pro.isPro ? full : full.filter { $0.kind == .event }
    }

    /// Today's events with suggestions in the free time, or the button to connect the calendar.
    @ViewBuilder private var plan: some View {
        if calendar.isAuthorized {
            SmartCalendar(allDay: calendar.events.filter(\.isAllDay).map { $0.title ?? "Untitled" },
                          items: planItems,
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
            Text(energy.headline)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else if !health.isAuthorized {
            Text("Connect Apple Health")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Text("Not enough sleep data yet")
                .font(.footnote)
                .foregroundStyle(.secondary)
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

    @ViewBuilder private var bottomBar: some View {
        VStack(spacing: 10) {
            if voice.isDictating || chat.isResponding || calendar.pendingChange != nil {
                InlineConversation(isListening: voice.isDictating, hint: voice.listeningHint,
                                   isThinking: chat.isResponding, change: calendar.pendingChange,
                                   confirm: chat.confirmChange, cancel: chat.cancelChange)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let note = voice.statusNote, tab == .twin {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(voice.isAwake ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
            }
            TwinTabBar(tab: $tab)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background {
            // Anything scrolling underneath fades out rather than colliding with the bar.
            LinearGradient(colors: [.clear, Color(.systemBackground).opacity(0.55),
                                    Color(.systemBackground).opacity(0.8)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
                .ignoresSafeArea()
        }
        .animation(.snappy, value: chat.isResponding)
    }

    // MARK: - Actions

    private func record(rating: Double) {
        guard let todayFeatures else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        diary.record(rating: rating, features: todayFeatures)
        Task { await updateEnergy() }
    }

    /// Tap Dash to talk, tap again when you're done. No pause cuts you off, and if you
    /// walk away it stops by itself.
    private func talk() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        if voice.isDictating { voice.finishDictation() } else { voice.startDictation() }
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
        trainedToday = await !health.workoutsToday().isEmpty
        workoutDetails = await health.workoutDetails()
        await TwinRefresh.schedule(reading: energy, dayStart: dayStart,
                                   bedtime: health.typicalBedtime(from: history),
                                   calendar: calendar, trained: trainedToday, through: notifications)
    }

    /// Hands today's starting charge to the widget and puts the matching face on the app
    /// icon, so the app, the widget and the icon all show the same twin.
    private func shareMood() {
        TwinRefresh.share(dayStart: dayStart)
    }

    /// Wakes at the top of each hour, when the charge changes.
    private func followTheHours() async {
        while !Task.isCancelled {
            let nextHour = Calendar.current.nextDate(after: .now, matching: DateComponents(minute: 0),
                                                     matchingPolicy: .nextTime) ?? .now.addingTimeInterval(3600)
            try? await Task.sleep(for: .seconds(max(nextHour.timeIntervalSinceNow, 1)))
            now = .now
        }
    }
}

#Preview {
    ContentView()
}
