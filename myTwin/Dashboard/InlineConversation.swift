import SwiftUI

/// A ring that breathes around Dash while he is listening to you.
struct ListeningRing: View {
    @State private var wide = false

    var body: some View {
        Circle()
            .strokeBorder(LinearGradient(colors: BrandTitle.brand, startPoint: .topLeading,
                                         endPoint: .bottomTrailing),
                          lineWidth: 3)
            .scaleEffect(wide ? 1.02 : 0.88)
            .opacity(wide ? 0.12 : 0.55)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { wide = true }
            }
    }
}

/// Under Dash while you talk to him: that he is listening, that he is thinking, and any
/// calendar change waiting for a Confirm. His answer is spoken aloud and written down in
/// the chat, never printed over the dashboard.
struct InlineConversation: View {
    let isListening: Bool
    let hint: String                 // how to finish: let go, or tap again
    let isThinking: Bool
    let change: CalendarChange?
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if isListening {
                listening
            } else if isThinking {
                thinking
            }
            if let change { confirmCard(change) }
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: isListening)
    }

    private var listening: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.fill")
                .foregroundStyle(.red)
                .symbolEffect(.pulse)
            Text(hint)
                .font(.subheadline)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground).opacity(0.8), in: .capsule)
    }

    private var thinking: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Thinking…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground).opacity(0.8), in: .capsule)
    }

    private func confirmCard(_ change: CalendarChange) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(change.question)
                .font(.subheadline.weight(.semibold))
            HStack {
                Button("Cancel", action: cancel)
                    .buttonStyle(.bordered)
                Button("Confirm", action: confirm)
                    .buttonStyle(.borderedProminent)
                    .tint(BrandTitle.brand[1])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCard(padding: 14)
    }
}

#Preview("Listening") {
    InlineConversation(isListening: true, hint: "Listening… let go when you're done",
                       isThinking: false, change: nil, confirm: {}, cancel: {})
        .padding()
}

#Preview("Thinking") {
    InlineConversation(isListening: false, hint: "", isThinking: true,
                       change: nil, confirm: {}, cancel: {})
        .padding()
}
