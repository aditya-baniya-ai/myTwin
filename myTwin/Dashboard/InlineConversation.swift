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

/// While you talk to Dash: how long you've been talking, dots that rise with your voice so
/// you can see he's hearing you, and buttons to throw it away or send it.
struct DictationBar: View {
    let level: Float
    let since: Date
    var isSending = false
    let cancel: () -> Void
    let send: () -> Void

    private static let dotCount = 24
    @State private var levels = [Float](repeating: 0, count: dotCount)

    var body: some View {
        HStack(spacing: 12) {
            Button("Discard", systemImage: "trash", action: cancel)
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(.primary)

            TimelineView(.periodic(from: since, by: 1)) { context in
                Text(Duration.seconds(max(0, context.date.timeIntervalSince(since).rounded(.down))),
                     format: .time(pattern: .minuteSecond))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // Newest on the right. A gentle wave keeps flowing through the dots the whole time
            // he's listening, even while you pause; your voice lifts them tall and white.
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                HStack(spacing: 4) {
                    ForEach(levels.indices, id: \.self) { index in
                        let wave = 0.1 + 0.07 * sin(time * 6 - Double(index) * 0.55)
                        let height = max(Double(levels[index]), wave)
                        Capsule()
                            .fill(levels[index] > 0.15 ? Color.primary : Color.secondary.opacity(0.6))
                            .frame(width: 5, height: 5 + height * 22)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .frame(height: 28)
            .accessibilityHidden(true)

            Button(action: send) {
                if isSending {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "arrow.up").font(.title3.weight(.semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(Color.blue, in: .circle)
            .disabled(isSending)
            .accessibilityLabel(isSending ? "Sending" : "Send")
        }
        .padding(.leading, 18)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: .capsule)
        .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
        .onChange(of: level) { _, now in
            levels = Array((levels + [now]).suffix(Self.dotCount))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dash is listening")
    }
}

/// Under Dash while he works on your question: that he is thinking, and any calendar
/// change waiting for a Confirm. His answer is spoken aloud and written down in the chat,
/// never printed over the dashboard.
struct InlineConversation: View {
    let isThinking: Bool
    let change: CalendarChange?
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if isThinking { thinking }
            if let change { confirmCard(change) }
        }
        .frame(maxWidth: .infinity)
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
    DictationBar(level: 0.6, since: .now.addingTimeInterval(-2), cancel: {}, send: {})
        .padding()
}

#Preview("Thinking") {
    InlineConversation(isThinking: true, change: nil, confirm: {}, cancel: {})
        .padding()
}
