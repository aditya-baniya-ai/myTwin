import SwiftUI
import FoundationModels

struct ChatView: View {
    let chat: ChatManager
    let voice: VoiceManager  // listening starts on the home screen, so it is shared
    @State private var input = ""

    var body: some View {
        Group {
            switch SystemLanguageModel.default.availability {
            case .available:
                conversation
            case .unavailable where chat.gemini.isActive:
                conversation                    // Gemini can answer while online
            case .unavailable(let reason):
                ContentUnavailableView("Chat isn't available", systemImage: "sparkles",
                                       description: Text(explanation(for: reason)))
            }
        }
        .navigationTitle("Ask myTwin")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                voice.speaksAnswers.toggle()
                if !voice.speaksAnswers { voice.stopSpeaking() }
            } label: {
                Label(voice.speaksAnswers ? "Mute" : "Speak answers",
                      systemImage: voice.speaksAnswers ? "speaker.wave.2" : "speaker.slash")
            }
        }
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if chat.messages.isEmpty {
                        Text("Say \"twin\" to wake me, or type below.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                    }
                    ForEach(chat.messages) { message in
                        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                            Text(message.text)
                                .padding(12)
                                .foregroundStyle(message.isUser ? Color.white : Color.primary)
                                .background(message.isUser ? Color.accentColor : Color(.secondarySystemBackground),
                                            in: .rect(cornerRadius: 16))
                            if !message.isUser {    // which one answered
                                Label(message.byGemini ? "Gemini" : "On this iPhone",
                                      systemImage: message.byGemini ? "sparkles" : "iphone")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
                    }
                    if let change = chat.calendar.pendingChange {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(change.question)
                                .font(.headline)
                            HStack {
                                Button("Cancel", action: chat.cancelChange)
                                    .buttonStyle(.bordered)
                                Button("Confirm", action: chat.confirmChange)
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
                    }
                    if chat.isResponding {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .defaultScrollAnchor(.bottom)

            if let note = voice.statusNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(voice.isAwake ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            HStack {
                Button {
                    Task { await toggleLiveVoice() }
                } label: {
                    Image(systemName: voice.isLive ? "mic.fill" : "mic")
                        .font(.title2)
                        .foregroundStyle(voice.isLive ? Color.red : Color.accentColor)
                }
                .disabled(voice.status == .preparing)

                TextField("Ask about your day", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { send(input) }

                Button("Send", systemImage: "arrow.up.circle.fill") { send(input) }
                    .labelStyle(.iconOnly)
                    .font(.title)
                    .disabled(input.isEmpty || chat.isResponding)
            }
            .padding()
        }
        // Show the words as they are recognised.
        .onChange(of: voice.transcript) { _, heard in input = heard }
    }

    private func toggleLiveVoice() async {
        if voice.isLive {
            await voice.stopLiveVoice()
        } else {
            await voice.startLiveVoice { text in
                guard !chat.isResponding else { return }
                Task { await chat.send(text) }
            }
        }
    }

    private func send(_ text: String) {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !chat.isResponding else { return }
        input = ""
        Task { await chat.send(message) }
    }

    private func explanation(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible: "This device doesn't support Apple Intelligence."
        case .appleIntelligenceNotEnabled: "Turn on Apple Intelligence in Settings to chat with myTwin."
        case .modelNotReady: "Apple Intelligence is still getting ready. Try again in a few minutes."
        @unknown default: "The on-device AI model isn't available right now."
        }
    }
}
