import SwiftUI

/// Remembers which character you picked. Stored on the phone, nowhere else.
@MainActor
@Observable
final class AvatarChoice {
    private static let key = "avatarStyleID"

    var style: AvatarStyle {
        didSet { UserDefaults.standard.set(style.id, forKey: Self.key) }
    }

    init() {
        style = AvatarStyle.named(UserDefaults.standard.string(forKey: Self.key))
    }
}

/// Pick your twin. Everyone shows the same expression, so you can see what each looks
/// like when you are running low.
struct AvatarPicker: View {
    @Bindable var choice: AvatarChoice
    let charge: Double
    @Environment(\.dismiss) private var dismiss
    @State private var preview: Double = 0.85

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    AvatarView(charge: preview, style: choice.style, size: 160)
                        .padding(.top, 28)

                    VStack(spacing: 6) {
                        Text("Drag to see how \(choice.style.name) looks as the day wears on")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Slider(value: $preview, in: 0.1...1)
                            .tint(BrandTitle.brand[1])
                    }
                    .padding(.horizontal)

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(AvatarStyle.all) { style in
                            Button {
                                choice.style = style
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                VStack(spacing: 6) {
                                    AvatarView(charge: preview, style: style, size: 96,
                                               showsBatteryRing: false)
                                    Text(style.name)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.primary)
                                }
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 18)
                                        .fill(choice.style == style
                                              ? BrandTitle.brand[1].opacity(0.16) : Color(.secondarySystemBackground)))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18)
                                        .strokeBorder(choice.style == style ? BrandTitle.brand[1] : .clear,
                                                      lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Choose your twin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
            }
            .onAppear { preview = charge }
        }
    }
}
