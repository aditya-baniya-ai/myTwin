import SwiftUI
import EventKit

struct ContentView: View {
    @State private var health = HealthManager()
    @State private var calendar: CalendarManager
    @State private var chat: ChatManager

    init() {
        // The chat reads the same calendar the home screen shows.
        let calendar = CalendarManager()
        _calendar = State(initialValue: calendar)
        _chat = State(initialValue: ChatManager(calendar: calendar))
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
                NavigationLink {
                    ChatView(chat: chat)
                } label: {
                    Label("Ask myTwin", systemImage: "bubble.left.and.text.bubble.right")
                }
            }
            .task { calendar.loadTodayEvents() }
            .refreshable {
                await health.refresh()
                calendar.loadTodayEvents()
            }
        }
    }

    private func metric(_ label: String, _ value: Double?, format: String) -> some View {
        LabeledContent(label, value: value.map { String(format: format, $0) } ?? "—")
    }
}

#Preview {
    ContentView()
}
