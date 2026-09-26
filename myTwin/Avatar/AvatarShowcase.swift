import SwiftUI

/// One of the one-shot clips on Dash's timeline. Each is a separate action baked in
/// Blender and laid end to end in the exported USDZ.
struct AvatarGesture: Identifiable, Equatable {
    let clip: String
    let name: String
    let symbol: String

    var id: String { clip }

    static let all = [
        AvatarGesture(clip: "wave", name: "Wave", symbol: "hand.wave.fill"),
        AvatarGesture(clip: "jump", name: "Jump", symbol: "figure.jumprope"),
        AvatarGesture(clip: "stretch", name: "Stretch", symbol: "figure.flexibility"),
        AvatarGesture(clip: "yawn", name: "Yawn", symbol: "wind"),
        AvatarGesture(clip: "doze", name: "Doze", symbol: "zzz"),
    ]
}

private extension AvatarEnergyState {
    /// A score in the middle of this state's band, so picking it lands squarely on the
    /// right idle loop rather than at a boundary.
    var showcaseScore: Double {
        switch self {
        case .energetic: 92
        case .normal: 68
        case .tired: 42
        case .exhausted: 15
        }
    }

    var title: String {
        switch self {
        case .energetic: "Energetic"
        case .normal: "Normal"
        case .tired: "Tired"
        case .exhausted: "Exhausted"
        }
    }

    var blurb: String {
        switch self {
        case .energetic: "Rested and charged. Stands tall, and won't keep still."
        case .normal: "An ordinary day. Easy breathing, the odd stretch."
        case .tired: "Running low. Shoulders drop and the yawns start."
        case .exhausted: "Nothing left. He can barely stay upright."
        }
    }
}

/// Dash, live and driveable: pick a state to watch him change, or ask for a gesture.
/// Built for showing the character off rather than for reading your day.
struct AvatarShowcase: View {
    @Environment(\.dismiss) private var dismiss
    @State private var state: AvatarEnergyState = .energetic
    @State private var gesture: AvatarGesture?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Avatar3DView(energy: state.showcaseScore, gesture: gesture)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 16) {
                    Text(state.blurb)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(.snappy, value: state)

                    statePicker
                    gestureRow

                    Text("Modelled, rigged and animated in Blender: nine clips on one "
                         + "timeline, sixteen face shapes, and a baked normal map for skin, "
                         + "hair and cloth. Drag him to turn him round.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(20)
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Meet Dash")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// The four energy states, which are four different idle loops.
    private var statePicker: some View {
        HStack(spacing: 8) {
            ForEach(AvatarEnergyState.allCases, id: \.self) { item in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.snappy) { state = item }
                } label: {
                    Text(item.title)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if state == item {
                                Capsule().fill(LinearGradient(colors: item.glow,
                                                              startPoint: .top, endPoint: .bottom))
                            } else {
                                Capsule().fill(.quaternary)
                            }
                        }
                        .foregroundStyle(state == item ? .white : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(state == item ? [.isSelected] : [])
            }
        }
    }

    /// The one-shot actions, played on demand instead of on his own schedule.
    private var gestureRow: some View {
        HStack(spacing: 8) {
            ForEach(AvatarGesture.all) { item in
                Button {
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                    // A fresh value every tap, so asking twice replays it.
                    gesture = nil
                    DispatchQueue.main.async { gesture = item }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: item.symbol).font(.system(size: 17, weight: .semibold))
                        Text(item.name).font(.caption2.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.quaternary, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview("Showcase") {
    AvatarShowcase()
}
