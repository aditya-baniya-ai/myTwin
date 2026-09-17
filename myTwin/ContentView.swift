import SwiftUI
import EventKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var health: HealthManager
    @State private var calendar: CalendarManager
    @State private var chat: ChatManager
    @State private var voice = VoiceManager()
    @State private var showChat = false

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
                if !health.isAuthorized {
                    Section {
                        Button("Connect Apple Health") {
                            Task { await health.requestAuthorization() }
                        }
                    } footer: {
                        Text("myTwin reads sleep, HRV, heart rate and activity to predict your energy.")
                    }
                } else {
                    Section("Recovery") {
                        metric("HRV (24h avg)", health.snapshot.hrvMs, format: "%.0f ms")
                        metric("Resting heart rate", health.snapshot.restingHR, format: "%.0f bpm")
                        metric("Respiratory rate", health.snapshot.respiratoryRate, format: "%.1f /min")
                        metric("Sleep last night", health.snapshot.sleepHours, format: "%.1f h")
                    }
                    Section("Activity today") {
                        metric("Steps", health.snapshot.steps, format: "%.0f")
                        metric("Active energy", health.snapshot.activeEnergyKcal, format: "%.0f kcal")
                    }
                }
                if let error = health.errorMessage {
                    Text(error).foregroundStyle(.red)
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
            }
            .navigationTitle("myTwin")
            .toolbar {
                Button("Ask myTwin", systemImage: "bubble.left.and.text.bubble.right") {
                    showChat = true
                }
            }
            .navigationDestination(isPresented: $showChat) {
                ChatView(chat: chat, voice: voice)
            }
            .safeAreaInset(edge: .bottom) { voiceBar }
            .task {
                await health.refreshAuthorizationState()
                calendar.loadTodayEvents()
                await listen()
            }
            .refreshable {
                await health.refresh()
                calendar.loadTodayEvents()
            }
            // Don't hold the microphone while the app is in the background.
            .onChange(of: scenePhase) { _, phase in
                Task {
                    switch phase {
                    case .active: await listen()
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

    /// Listens for "my twin" from the moment the app opens.
    private func listen() async {
        await voice.startLiveVoice { sentence in
            showChat = true  // open the conversation so you can see what it heard
            guard !chat.isResponding else { return }
            Task { await chat.send(sentence) }
        }
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

    private func metric(_ label: String, _ value: Double?, format: String) -> some View {
        LabeledContent(label, value: value.map { String(format: format, $0) } ?? "—")
    }
}

#Preview {
    ContentView()
}
