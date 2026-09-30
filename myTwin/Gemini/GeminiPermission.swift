import SwiftUI

/// The one-time question: may myTwin use Gemini when you're online? Apple requires apps to
/// name the AI company and get a clear yes before personal data leaves the phone (App
/// Review Guideline 5.1.2(i)).
struct GeminiPermissionSheet: View {
    /// Called with the answer: true to allow, false to keep everything on the iPhone.
    let answer: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(LinearGradient(colors: BrandTitle.brand,
                                                        startPoint: .leading, endPoint: .trailing))
                    Text("Use Gemini when you're online?")
                        .font(.title2.bold())
                    Text("Do you allow myTwin to use Google's Gemini for your answers in online mode?")
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

                choice("With Gemini", tint: BrandTitle.brand[1], fill: BrandTitle.brand[1].opacity(0.12), points: [
                    ("waveform", "A natural, human-sounding voice"),
                    ("brain.head.profile", "Smarter answers about your sleep, energy and plans"),
                    ("cloud", "What you say or type, your goals, health summary, energy forecast and calendar go to Google's servers"),
                ])
                choice("Without Gemini", tint: .secondary, fill: Color(.secondarySystemBackground), points: [
                    ("lock.iphone", "Everything stays on your iPhone"),
                    ("text.bubble", "Simpler answers and the standard iPhone voice"),
                ])

                Text("If you allow it, myTwin uses Gemini whenever you're online, without asking again. Pro mentor conversations need Gemini and an internet connection. Other chat can answer on your iPhone offline.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button {
                    reply(true)
                } label: {
                    Text("Allow").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(BrandTitle.brand[1])
                Button("Don't Allow") { reply(false) }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .interactiveDismissDisabled()           // a real answer, not a swipe away
    }

    private func reply(_ allow: Bool) {
        answer(allow)
        dismiss()
    }

    private func choice(_ title: String, tint: Color, fill: Color,
                        points: [(icon: String, text: String)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            ForEach(points.indices, id: \.self) { index in
                Label {
                    Text(points[index].text)
                } icon: {
                    Image(systemName: points[index].icon).foregroundStyle(tint)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(fill))
    }
}
