import SwiftUI
import EventKit
import WidgetKit

struct ContentView: View {
    let isSample: Bool
    let leaveSample: () -> Void
    let enterSample: () -> Void
    @State private var daily: DailySupport
    @State private var showPreferences = false
    @State private var showExplanation = false
    @State private var showRescue = false
    @State private var pendingRescue = false
    @State private var rescueMinutes: Int?
    @State private var undoAction: PlannedAction?
    @State private var undoOriginal: PlannedAction?
    @State private var planningProblem: String?
    @State private var signalHistory: [DaySignals] = []
    @State private var dashGesture: AvatarGesture?
    /// Something Dash brought up himself, and when. See DashNudges.
    @State private var nudge: DashNudge?
    @State private var nudgeAt: Date?
    /// The sample day's own memory of nudges, so it never writes to the real one.
    @State private var sampleNudgeLog = DashNudges.Log()

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
    @State private var askedLocked = false
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

    init(isSample: Bool = false, leaveSample: @escaping () -> Void = {}, enterSample: @escaping () -> Void = {}) {
        self.isSample = isSample
        self.leaveSample = leaveSample
        self.enterSample = enterSample
        _daily = State(initialValue: DailySupport(isSample: isSample))
        _dismissed = State(initialValue: isSample ? [] : DismissedSuggestions.today())
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
        // Swipe between the pages, or tap the bar. A paging TabView rather than a paging
        // ScrollView: after switching between the sample and your own day, the ScrollView
        // came back drawn a bar-height lower than where it took taps.
        TabView(selection: $tab) {
            ForEach(TwinTab.allCases) { page in
                view(for: page).tag(page)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background { BatteryBackdrop(energy: charge * 100) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Next to the chat button: how he sounds, without going to the You page.
            Button("Dash's voice", systemImage: "waveform") {
                showVoicePicker = true
            }
            if !isSample {
                Button("Ask myTwin", systemImage: "bubble.left.and.text.bubble.right") { showChat = true }
            }
        }
        .sheet(isPresented: $loggingWeight) {
            LogWeightSheet(last: weights.last?.pounds, goal: daily.preferences.weightGoal) { pounds in
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
            if isSample { await updateEnergy(); return }
            await pro.start()
            askGemini = gemini.needsAnswer
            await health.refreshAuthorizationState()
            calendar.loadTodayEvents()
            calendar.loadWeekEvents()
            await updateEnergy()
            await listen()
        }
        .task { await followTheHours() }
        // Dash speaks up on whichever page you're on, not only his own.
        .task {
            try? await Task.sleep(for: .seconds(3))      // let the day load and him appear
            while !Task.isCancelled {
                await considerNudge()
                try? await Task.sleep(for: .seconds(15 * 60))
            }
        }
        .task { if !isSample { await pro.watchForChanges() } }
        // Both models read today's plan through this, and only the screen knows the
        // day's charge, bedtime and what has been dismissed.
        .onAppear {
            chat.rescueDay = { minutes in rescueMinutes = minutes; openRescue() }
            chat.planSource.summary = { [self] in
                guard pro.isPro else { return "Adaptive plans and hour-by-hour forecasts require myTwin Pro. Rescue my day also requires an active myTwin Pro entitlement." }
                guard hasPrediction else { return "No measured forecast yet. The user can report how they feel and use Rescue my day to choose an activity." }
                return TodayPlanText.summary(.init(dayStart: dayStart, bedtime: bedtimeDate,
                    events: currentEvents, dismissed: dismissed, trainedToday: trainedToday,
                    easyDay: easyDay, preferences: effectivePreferences))
            }
            chat.planSource.weekRecap = { [self] in
                WeekRecap.text(history: signalHistory, model: energyModel)
            }
        }
        .onChange(of: pro.isPro, initial: true) {
            chat.proEnabled = pro.isPro
            if !canRescue { showRescue = false }
        }
        .onChange(of: gemini.allowed) { if gemini.allowed != true { chat.endGemini() } }
        .sheet(isPresented: $showShowcase) { AvatarShowcase() }
        .sheet(isPresented: $showVoicePicker) {
            VoicePicker(voice: voice, isPro: pro.isPro)
        }
        .sheet(isPresented: $showPaywall, onDismiss: {
            let resumeRescue = pendingRescue && pro.isPro
            pendingRescue = false
            if resumeRescue { showRescue = true }
        }) { ProPaywall(pro: pro) }
        .sheet(isPresented: $showPreferences) {
            PlanningPreferencesView(preferences: daily.preferences) { value in
                daily.savePreferences(value)
                Task {
                    if !isSample && (value.morningReminder || value.eventReminders || value.bedtimeReminder) {
                        await notifications.requestPermission()
                    }
                    await reschedule()
                }
            }
        }
        .sheet(isPresented: $showExplanation) {
            EnergyExplanationView(history: signalHistory, reading: energy,
                checkIn: daily.currentCheckIn, isSample: isSample, report: recordCheckIn)
        }
        .sheet(isPresented: $showRescue) {
            RescueDayView(daily: daily, calendar: calendar, events: { currentEvents },
                          now: { planningNow }, allowed: { canRescue }, initialMinutes: rescueMinutes) { action, original in
                undoAction = action
                undoOriginal = original
                dashGesture = AvatarGesture.all.first { $0.clip == "wave" }
                Task { await reschedule() }
            }
        }
        .onChange(of: calendar.revision) { Task { await reschedule() } }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            guard !isSample else { return }
            calendar.loadTodayEvents()
            calendar.loadWeekEvents()
            Task { await reschedule() }
        }
        .sheet(isPresented: $showCustomerCentre) { ProCustomerCentre() }
        .refreshable {
            guard !isSample else { return }
            await health.refresh()
            calendar.loadTodayEvents()
            calendar.loadWeekEvents()
            await updateEnergy()
        }
        // Don't hold the microphone while the app is in the background.
        .onChange(of: scenePhase) { _, phase in
            Task {
                guard !isSample else { return }
                switch phase {
                case .active:
                    now = .now
                    dismissed = DismissedSuggestions.today()
                    calendar.loadTodayEvents()
                    calendar.loadWeekEvents()
                    await pro.refresh()
                    await health.refresh()          // your watch may have synced since
                    await updateEnergy()
                    await listen()
                    await considerNudge()           // back in the app: anything worth saying now?
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

    // MARK: - The five pages

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
                if isSample { sampleBanner }
                twinContent.frame(height: asksCheckIn ? 420 : 520)   // Dash takes the card's room
                supportCard
                ActionFeedbackView(daily: daily, now: planningNow)

                if fullAccess && hasPrediction {
                    tabLink("Predictions", tab: .predictions) {
                        PredictionsCard(points: DayCharge.forecast(from: dayStart, now: planningNow, until: bedtimeDate))
                    }
                } else if fullAccess {
                    Text("Still learning. You can check in and rescue your day while your sleep baseline builds.")
                        .dashboardCard()
                } else {
                    LockedCard(title: "Your energy, hour by hour",
                               detail: "See where your peak lands and when the dip hits, before the day starts.") {
                        showPaywall = true
                    }
                }

                if health.isAuthorized && !isSample {
                    tabLink("Activity", tab: .activity) {
                        ActivityGrid(steps: health.snapshot.steps,
                                     activeEnergy: health.snapshot.activeEnergyKcal,
                                     sleepWeek: sleepWeek, weights: weights, preferences: daily.preferences) { loggingWeight = true }
                    }
                }

                suggestedChanges                          // the calendar, in brief

                if !isSample { tabLink("Connections", tab: .you) { connections } }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }

    /// Today's suggestions in brief, with a way through to the calendar itself.
    private var suggestedChanges: some View {
        let suggestions = fullAccess && hasPrediction ? plannedItems.filter { $0.kind == .suggestion } : []
        return VStack(alignment: .leading, spacing: 10) {
            Text("Suggested changes")
                .font(.title3.weight(.bold))
                .padding(.leading, 4)
            if !fullAccess {
                LockedCard(title: "Plans that fit your day",
                           detail: "A workout in your strongest free hour, a nap at the dip, the last coffee that still clears before bed.") {
                    showPaywall = true
                }
            }
            VStack(spacing: 12) {
                if !fullAccess {
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
            Avatar3DView(energy: charge * 100, gesture: dashGesture)
                .frame(maxWidth: .infinity, maxHeight: .infinity)     // whatever is left
                .background { if listening { ListeningGlow() } }
                .scaleEffect(listening ? 1.03 : 1)                    // he lifts while listening
                .offset(y: listening ? -10 : 0)
                .animation(.spring(response: 0.45, dampingFraction: 0.7), value: listening)
                .onTapGesture { if isSample { openRescue() } else { talk() } }
                .accessibilityLabel(hasPrediction ? "Your twin, illustrative energy estimate. Tap to talk." : "Your twin is still learning. Tap to talk.")
                .accessibilityHint(voice.isDictating ? "Tap again when you're done" : "Tap to start listening")
            chargeLabel
            verdict
                .padding(.horizontal, 20)
            Text(daily.currentCheckIn.map { "You said you feel \($0.title.lowercased()). Let's find what fits today." }
                 ?? DayGreeting.line(charge: charge, reading: energy, next: nextEvent,
                                  dayStart: dayStart, healthConnected: health.isAuthorized || isSample,
                                  userName: isSample ? "Alex" : UserProfile().firstName))
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

    /// The week as a few sentences rather than a chart. Hidden until there are enough
    /// nights to say something true.
    @ViewBuilder private var weekRecap: some View {
        let lines = energyModel.map { WeekRecap.lines(history: signalHistory, model: $0) } ?? []
        if !lines.isEmpty {
            DashboardSection(title: "Your week") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(lines, id: \.self) { line in
                        Text(line)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .dashboardCard()
            }
        }
    }

    private var predictionsPage: some View {
        page("Predictions", tab: .predictions) {
            if fullAccess && hasPrediction {
                PredictionsCard(points: DayCharge.forecast(from: dayStart, now: planningNow, until: bedtimeDate))
            } else if fullAccess {
                Text("Still learning. Add at least seven recent nights of sleep in Apple Health; you can check in and rescue your day now.")
                    .dashboardCard()
            } else {
                LockedCard(title: "Your energy, hour by hour",
                           detail: "See where your peak lands and when the dip hits, before the day starts.") {
                    showPaywall = true
                }
            }
            Button("Why this plan?", systemImage: "info.circle") { showExplanation = true }
            if asksCheckIn { checkInCard }
            if health.isAuthorized, !week.isEmpty {
                DashboardSection(title: "Your last 7 days") { WeekStrip(days: week).dashboardCard() }
            }
            weekRecap
            if !isSample { oftenAsked }
        }
    }

    /// The questions you keep asking, as one tap each; three starters until you have
    /// repeated a couple. Pro shows the latest answer under each and asks again on a tap.
    /// Free shows the questions, and a tap explains they come with Pro.
    @ViewBuilder private var oftenAsked: some View {
        let _ = chat.messages.count                        // re-read after each answer
        let asked = AskedQuestions.top()
        let items = asked.isEmpty
            ? AskedQuestions.starters.map { AskedQuestions.Asked(question: $0, count: 0, last: .now) }
            : asked
        DashboardSection(title: asked.isEmpty ? "Try asking" : "You often ask") {
            VStack(spacing: 0) {
                ForEach(items) { item in
                    Button {
                        guard pro.isPro else { askedLocked = true; return }
                        tab = .twin
                        Task { await chat.send(item.question) }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BrandTitle.brand[1])
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.question)
                                    .font(.subheadline)
                                if pro.isPro, let answer = item.answer {
                                    Text(answer)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                            }
                            .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            if !pro.isPro {
                                Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 10)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    if item.id != items.last?.id { Divider() }
                }
            }
            .dashboardCard()
        }
        .alert("Buy premium to use this feature.", isPresented: $askedLocked) {
            Button("See myTwin Pro") { showPaywall = true }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("With Pro, Dash answers these for you and keeps the answers here.")
        }
    }

    private var activityPage: some View {
        page("Today's activity", tab: .activity) {
            if isSample {
                Text("Sample day uses fictional sleep and calendar data. Your real activity and health records are not shown here.").dashboardCard()
            } else {
                activity
            }
            if !isSample && health.isAuthorized {
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
            if isSample { sampleBanner }
            if canRescue {
                Button("Rescue my day", systemImage: "wand.and.stars") { openRescue() }.buttonStyle(.borderedProminent)
            }
            if planSpan == .day { plan } else if isSample {
                Text("Sample mode shows one fictional day. Your real week is available after connecting Calendar.")
            } else { weekPlan }
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
            if isSample { sampleBanner }
            Button("Make it yours", systemImage: "slider.horizontal.3") { showPreferences = true }.dashboardCard()
            if !isSample { Button("Try a sample day", systemImage: "play.rectangle", action: enterSample).dashboardCard() }
            if !isSample {
                voiceRow
                proRow
#if DEBUG
                proResetRow
#endif
            }
            if !isSample { connections }
            if notifications.permissionDenied && !isSample {
                Text("Notifications are off in Settings. Your plan still works in the app.").font(.footnote)
            }
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
                   detail: "Change whether Google receives your questions and tool results") { askGemini = true }
            Button("Change Gemini permission") { askGemini = true }.font(.subheadline)
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
                         sleepWeek: sleepWeek, weights: weights, preferences: daily.preferences) { loggingWeight = true }
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
        fullAccess && hasPrediction ? plannedItems : currentEvents
    }

    /// Today's events with suggestions in the free time, or the button to connect the calendar.
    @ViewBuilder private var plan: some View {
        if calendar.isAuthorized || isSample {
            SmartCalendar(allDay: isSample ? [] : calendar.events.filter(\.isAllDay).map { $0.title ?? "Untitled" },
                          items: planItems,
                          now: planningNow,
                          accept: acceptSuggestion,
                          dismiss: { item in
                              if isSample { dismissed.insert(item.title) }
                              else { DismissedSuggestions.add(item.title); dismissed = DismissedSuggestions.today() }
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
        daily.preferences.bedtime(on: planningNow)
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
    private var charge: Double { hasPrediction ? DayCharge.remaining(from: dayStart, at: planningNow) : 0.65 }

    private var mood: AvatarEnergyState { AvatarEnergyState(score: charge * 100) }

    private var chargeLabel: some View {
        Text(hasPrediction ? "\(Int(charge * 100))% · illustrative estimate"
                           : asksCheckIn ? "Still learning · check in below" : "Still learning")
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
            } else if let nudge {
                NudgeCard(nudge: nudge, more: { tellMore(nudge) }, dismiss: { self.nudge = nil })
                    .padding(.horizontal, 16)
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

    private var planningNow: Date { isSample ? SampleDay.now : .now }
    private var fullAccess: Bool { isSample || pro.isPro }
    private var hasPrediction: Bool { energy != nil }
    private var canRescue: Bool { daily.canRescue(proEnabled: pro.isPro) }
    /// Reads `now` so the card comes back when the hour turns into a new part of the day.
    private var asksCheckIn: Bool { daily.asksForCheckIn(now: isSample ? SampleDay.now : max(now, .now)) }
    private var easyDay: Bool { daily.currentCheckIn.map { $0 == .low } ?? (energy?.band == .below) }
    private var effectivePreferences: PlanningPreferences {
        var value = daily.preferences
        value.movement = daily.suggestedMovement
        return value
    }
    private var currentEvents: [PlanItem] {
        if !isSample { return DayPlanner.items(from: calendar.events) }
        let fixed = [PlanItem(kind: .event, title: "Project meeting", start: SampleDay.at(14, minute: 30), end: SampleDay.at(15), color: .blue, eventID: "sample-meeting"),
                     PlanItem(kind: .event, title: "Class", start: SampleDay.at(16), end: SampleDay.at(17), color: .purple, eventID: "sample-class")]
        return fixed + daily.actions.filter { !$0.skipped }.map {
            PlanItem(kind: .event, title: $0.title, start: $0.start, end: $0.end, color: .green,
                     movement: $0.movement, eventID: $0.eventID ?? $0.id.uuidString)
        }
    }
    private var plannedItems: [PlanItem] {
        DayPlanner.plan(events: currentEvents, dayStart: dayStart, now: planningNow, bedtime: bedtimeDate,
                        excluding: dismissed, trained: trainedToday, easyDay: easyDay, preferences: effectivePreferences)
    }
    private var sampleBanner: some View {
        HStack {
            Label("Sample day · fictional data · 2 PM", systemImage: "play.rectangle.fill").font(.caption.bold())
            Spacer()
            Button("Exit", action: leaveSample)
        }.padding(12).background(.orange.opacity(0.15), in: .rect(cornerRadius: 12))
    }
    private var checkInCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How do you feel right now?").font(.headline)
            HStack {
                ForEach(ReportedEnergy.allCases) { value in
                    Button(value.title) { recordCheckIn(value) }
                        .buttonStyle(.bordered)
                        .tint(daily.currentCheckIn == value ? .green : .accentColor)
                        .accessibilityAddTraits(daily.currentCheckIn == value ? [.isSelected] : [])
                }
            }
            Text("Self-reported · works without a watch").font(.caption).foregroundStyle(.secondary)
        }.dashboardCard()
    }
    private var supportCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if asksCheckIn { checkInCard.transition(.opacity) }
            if canRescue {
                Button { openRescue() } label: {
                    Label("Rescue my day", systemImage: "wand.and.stars").font(.headline).frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large)
                Text("A plan that fits how you feel. Preview every change.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Why this plan?") { showExplanation = true }
                Spacer()
                Button("Make it yours") { showPreferences = true }
            }.font(.subheadline)
            if let action = undoAction {
                VStack(alignment: .leading, spacing: 8) {
                    Label(isSample ? "Sample plan updated" : "Calendar updated", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("\(action.title) · \(timeRangeText(action.start, action.end))").font(.subheadline)
                    Button("Undo change") { undoRescue(action) }
                }.dashboardCard()
            }
            if let planningProblem { Text(planningProblem).foregroundStyle(.red).font(.footnote) }
        }
    }
    private func openRescue() {
        if canRescue { showRescue = true }
        else { pendingRescue = true; showPaywall = true }
    }
    private func recordCheckIn(_ value: ReportedEnergy) {
        withAnimation(.snappy) { daily.report(value, now: planningNow) }
        if !isSample, let todayFeatures { diary.record(rating: value.rating, features: todayFeatures) }
        // A check-in changes recommendations, not the measured sleep or plotted battery.
    }
    private func acceptSuggestion(_ item: PlanItem) {
        guard fullAccess else { showPaywall = true; return }
        let action = PlannedAction(movement: item.movement ?? .rest, title: item.title,
                                   start: item.start, end: item.end, reportedEnergy: daily.currentCheckIn,
                                   tracksOutcome: item.movement != nil)
        do {
            let saved = isSample ? action : try calendar.saveActivity(action, replacing: nil, bedtime: bedtimeDate)
            daily.save(saved)
            planningProblem = nil
        } catch { planningProblem = error.localizedDescription }
    }
    private func undoRescue(_ action: PlannedAction) {
        do {
            if !isSample { try calendar.undoActivity(action, restoring: undoOriginal) }
            daily.undo(action, restoring: undoOriginal)
            undoAction = nil
            undoOriginal = nil
            planningProblem = nil
        } catch { planningProblem = error.localizedDescription }
    }
    private func reschedule() async {
        guard !isSample else { return }
        await TwinRefresh.schedule(reading: energy, dayStart: dayStart,
            bedtime: (daily.preferences.bedtimeHour, daily.preferences.bedtimeMinute),
            calendar: calendar, trained: trainedToday, through: notifications)
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
        guard !isSample else { return }
        await voice.startLiveVoice { sentence in
            guard !chat.isResponding else { return }
            Task { await chat.send(sentence) }
        }
    }

    private func updateEnergy() async {
        defer { if !isSample { shareMood() } }
        guard let energyModel else { return }
        if !isSample && !health.isAuthorized { energy = nil; signalHistory = []; await reschedule(); return }
        let (history, searched) = isSample ? (SampleDay.history, 14) : await health.history()
        signalHistory = history
        searchedDays = searched
        nightsFound = energyModel.usableNights(in: history).count
        todayFeatures = energyModel.features(from: history)
        sleepWeek = history.prefix(7).reversed().map { $0.asleepMinutes.map { $0 / 60 } }
        // Replay the model for each of the last seven days, using only what was known then.
        week = (0..<7).compactMap { offset in
            let slice = Array(history.dropFirst(offset))
            guard let day = slice.first else { return nil }
            return (day.date, energyModel.reading(from: slice)?.band)
        }
        withAnimation(.easeOut(duration: 0.4)) {
            energy = energyModel.reading(from: history, diary: isSample ? nil : diary)
        }
        if isSample { return }
        coverage = await health.coverage(days: 90)
        weights = await health.weights()
        trainedToday = await !health.workoutsToday().isEmpty
        workoutDetails = await health.workoutDetails()
        await reschedule()
    }

    /// Hands today's starting charge to the widget and puts the matching face on the app
    /// icon, so the app, the widget and the icon all show the same twin.
    private func shareMood() {
        TwinRefresh.share(dayStart: dayStart, hasPrediction: energy != nil)
    }

    /// Wakes at the top of each hour, when the charge changes.
    /// Lets Dash bring something up on his own when nothing else is happening. The forecast,
    /// the plan and the calendar only come into it with Pro; the week and a long sit don't.
    private func considerNudge() async {
        if let at = nudgeAt, Date.now.timeIntervalSince(at) > 30 * 60 { nudge = nil }  // stale by now
        guard nudge == nil, !voice.isDictating, !chat.isResponding,
              calendar.pendingChange == nil else { return }

        let now = planningNow
        let planning = fullAccess && hasPrediction
        let situation = DashNudges.Situation(
            now: now, dayStart: dayStart,
            forecast: planning ? DayCharge.forecast(from: dayStart, now: now, until: bedtimeDate) : [],
            events: planning ? currentEvents : [],
            suggestions: planning ? plannedItems.filter { $0.kind == .suggestion } : [],
            stepsLastTwoHours: isSample ? nil : await health.steps(since: now.addingTimeInterval(-2 * 3600)),
            hasWeekRecap: !(energyModel.map { WeekRecap.lines(history: signalHistory, model: $0) } ?? []).isEmpty)

        var log = isSample ? sampleNudgeLog : DashNudges.Log.load()
        let found = DashNudges.next(situation, quiet: effectivePreferences.isQuiet(now), log: &log)
        if isSample { sampleNudgeLog = log } else { log.save() }
        guard let found else { return }

        withAnimation(.snappy) { nudge = found }
        nudgeAt = .now
        dashGesture = nil                                 // a fresh value, so he waves again
        DispatchQueue.main.async { dashGesture = AvatarGesture.all.first { $0.clip == "wave" } }
        if voice.speaksAnswers { voice.speak(found.line) }
    }

    /// Takes Dash up on it: asks him the follow-up in the user's words. It isn't counted
    /// among the questions they ask, since he brought it up.
    private func tellMore(_ nudge: DashNudge) {
        self.nudge = nil
        Task { await chat.send(nudge.question, record: false) }
    }

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
    NavigationStack { ContentView() }
}
