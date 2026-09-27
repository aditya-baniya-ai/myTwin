import SwiftUI

/// The light around Dash while he is listening: he lifts a little and the glow behind him
/// breathes. Quieter than a ring drawn over him, and it reads at a glance.
struct ListeningGlow: View {
    @State private var breathing = false

    var body: some View {
        RadialGradient(colors: [BrandTitle.brand[0].opacity(breathing ? 0.55 : 0.28),
                                BrandTitle.brand[1].opacity(breathing ? 0.28 : 0.12),
                                .clear],
                       center: .center, startRadius: 4, endRadius: breathing ? 230 : 180)
            .blur(radius: 26)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { breathing = true }
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

/// Something Dash brought up himself, with a way to take him up on it or not.
struct NudgeCard: View {
    let nudge: DashNudge
    let more: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(nudge.line, systemImage: "bubble.left.fill")
                .font(.subheadline)
                .labelStyle(.titleAndIcon)
            HStack {
                Button("Not now", action: dismiss)
                    .buttonStyle(.bordered)
                Button("Tell me more", action: more)
                    .buttonStyle(.borderedProminent)
                    .tint(BrandTitle.brand[1])
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // It floats over the page, so it blurs what's behind rather than showing through.
        .background(.regularMaterial, in: .rect(cornerRadius: 22))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
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
