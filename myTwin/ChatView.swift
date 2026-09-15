import SwiftUI
import FoundationModels

struct ChatView: View {
    let chat: ChatManager
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

            HStack {
                TextField("Ask about your day", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(send)
                Button("Send", systemImage: "arrow.up.circle.fill", action: send)
                    .labelStyle(.iconOnly)
                    .font(.title)
                    .disabled(input.isEmpty || chat.isResponding)
            }
            .padding()
        }
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !chat.isResponding else { return }
        input = ""
        Task { await chat.send(text) }
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
