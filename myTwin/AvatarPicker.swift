import SwiftUI

/// Pick your twin. The slider tries out a made-up energy score, so you can see how the
/// character moves and looks as the day wears on; it never touches today's real score.
struct AvatarPicker: View {
    let avatars: AvatarManager
    /// Today's score, 0-100: where the slider starts.
    let energy: Double
    @Environment(\.dismiss) private var dismiss
    @State private var preview: Double = 85

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Avatar3DView(character: avatars.selected, energy: preview,
                                 isLive: !Avatar3DView.drawsOnlyFirstScene)
                        .frame(height: 340)
                        .padding(.top, 12)

                    VStack(spacing: 6) {
                        Text("Drag to see how \(avatars.selected.name) looks as the day wears on")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Slider(value: $preview, in: 0...100)
                            .tint(BrandTitle.brand[1])
                    }
                    .padding(.horizontal)

                    // Rendered stills, not live scenes: only the preview above runs in 3D.
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(AvatarCharacter.all) { character in
                            Button {
                                avatars.selected = character
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                VStack(spacing: 6) {
                                    Image(character.stillName(for: AvatarEnergyState(score: preview)))
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: 110)
                                    Text(character.name)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.primary)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 18)
                                        .fill(avatars.selected == character
                                              ? BrandTitle.brand[1].opacity(0.16) : Color(.secondarySystemBackground)))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18)
                                        .strokeBorder(avatars.selected == character ? BrandTitle.brand[1] : .clear,
                                                      lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 24)
            }
            .background { BatteryBackdrop(energy: preview) }
            .navigationTitle("Choose your twin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
            }
            .onAppear { preview = energy }
        }
    }
}
