import SwiftUI
import FoundationModels

struct ChatView: View {
    let chat: ChatManager
    @State private var voice = VoiceManager()
    @State private var input = ""

    var body: some View {
        Group {
            switch SystemLanguageModel.default.availability {
            case .available:
                conversation
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
        .onDisappear { Task { await voice.stopConversation() } }
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if chat.messages.isEmpty {
                        Text("Try: \"What's on my calendar today?\"")
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                    }
                    ForEach(chat.messages) { message in
                        Text(message.text)
                            .padding(12)
                            .foregroundStyle(message.isUser ? Color.white : Color.primary)
                            .background(message.isUser ? Color.accentColor : Color(.secondarySystemBackground),
                                        in: .rect(cornerRadius: 16))
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

            if let note = voiceNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(voice.status == .listening ? Color.secondary : Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            HStack {
                Button {
                    Task { await toggleHandsFree() }
                } label: {
                    Image(systemName: voice.handsFree ? "waveform.circle.fill" : "waveform.circle")
                        .font(.title2)
                        .foregroundStyle(voice.handsFree ? Color.red : Color.accentColor)
                }
                .disabled(voice.status == .preparing)

                Button {
                    Task { await toggleMicrophone() }
                } label: {
                    Image(systemName: voice.status == .listening ? "mic.fill" : "mic")
                        .font(.title2)
                        .foregroundStyle(voice.status == .listening ? Color.red : Color.accentColor)
                }
                .disabled(chat.isResponding || voice.status == .preparing || voice.handsFree)

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
        // Read each new answer aloud.
        .onChange(of: chat.messages.count) { _, _ in
            guard let last = chat.messages.last, !last.isUser else { return }
            voice.speak(last.text)
        }
    }

    private var voiceNote: String? {
        switch voice.status {
        case .idle: nil
        case .preparing: "Getting the offline voice model ready…"
        case .listening: voice.handsFree ? "Hands-free on. Just talk, and talk over me to interrupt."
                                         : "Listening… I'll send when you stop talking."
        case .unavailable(let reason): reason
        }
    }

    private func toggleHandsFree() async {
        if voice.handsFree {
            await voice.stopConversation()
        } else {
            await voice.startConversation { send($0) }
        }
    }

    private func toggleMicrophone() async {
        voice.stopSpeaking()  // talking over it should interrupt it
        if voice.status == .listening {
            await voice.finish()
        } else {
            await voice.start { send($0) }
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
