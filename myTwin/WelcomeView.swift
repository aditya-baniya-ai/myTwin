import SwiftUI

/// The welcome screen that appears on first launch to collect the user's name and age.
/// Once filled in, it's never shown again — the profile is saved to UserDefaults.
struct WelcomeView: View {
    @Binding var profile: UserProfile
    var onComplete: () -> Void

    @State private var nameText = ""
    @State private var ageText = ""
    @State private var glowing = false
    @FocusState private var focusedField: Field?

    private enum Field { case name, age }

    private var ageValue: Int? {
        Int(ageText).flatMap { (1...120).contains($0) ? $0 : nil }
    }

    private var isValid: Bool {
        !nameText.trimmingCharacters(in: .whitespaces).isEmpty && ageValue != nil
    }

    var body: some View {
        ZStack {
            // Background matching the app's dark gradient
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.06, blue: 0.14),
                         Color(red: 0.10, green: 0.08, blue: 0.20),
                         Color.black],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Brand title
                BrandTitle()
                    .padding(.bottom, 8)

                Text("Your personal energy twin")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 40)

                // Input card
                VStack(spacing: 20) {
                    Text("Let's get to know you")
                        .font(.title3.weight(.bold))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Name field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your name")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("What should we call you?", text: $nameText)
                            .textContentType(.name)
                            .autocorrectionDisabled()
                            .font(.body)
                            .padding(12)
                            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 12))
                            .focused($focusedField, equals: .name)
                    }

                    // Age field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your age")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("Age", text: $ageText)
                            .keyboardType(.numberPad)
                            .font(.body)
                            .padding(12)
                            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 12))
                            .focused($focusedField, equals: .age)
                    }

                    Text("This stays on your iPhone — no accounts, no servers.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(24)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(.white.opacity(0.1))
                )
                .padding(.horizontal, 24)

                Spacer()

                // Continue button
                Button(action: save) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(colors: BrandTitle.brand, startPoint: .leading, endPoint: .trailing)
                                .opacity(isValid ? 1 : 0.3),
                            in: .capsule
                        )
                        .shadow(color: BrandTitle.brand[1].opacity(isValid ? 0.4 : 0), radius: 16, y: 6)
                }
                .buttonStyle(.plain)
                .disabled(!isValid)
                .padding(.horizontal, 32)
                .padding(.bottom, 20)
                .animation(.easeOut(duration: 0.25), value: isValid)
            }
        }
        .onAppear { focusedField = .name }
    }

    private func save() {
        profile.name = nameText.trimmingCharacters(in: .whitespaces)
        profile.age = ageValue ?? 0
        onComplete()
    }
}

#Preview("Welcome") {
    @Previewable @State var profile = UserProfile()
    WelcomeView(profile: $profile) { }
}
