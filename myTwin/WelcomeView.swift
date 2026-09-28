import SwiftUI

/// First launch: try the demo as a guest, or set myTwin up with your own data.
///
/// As a guest you pick the free or the Pro version and land in a fictional day. As a user
/// you give your name and age, then connect Apple Health and Calendar. The profile is saved
/// to UserDefaults, and once it is complete this screen isn't shown again.
struct WelcomeView: View {
    enum Step { case start, guest, user, connect }

    @Binding var profile: UserProfile
    /// Where to begin: `.user` when you leave the demo to set up your own account.
    @State var step: Step = .start
    /// Starts the demo, with Pro (`true`) or without.
    var chooseDemo: (Bool) -> Void = { _ in }
    var onComplete: () -> Void

    @State private var nameText = ""
    @State private var ageText = ""
    @FocusState private var focusedField: Field?
    @State private var health = HealthManager()
    @State private var calendar = CalendarManager()
    @State private var greeting: AvatarGesture?

    private enum Field { case name, age }

    private var ageValue: Int? {
        Int(ageText).flatMap { (1...120).contains($0) ? $0 : nil }
    }

    private var isValid: Bool {
        !nameText.trimmingCharacters(in: .whitespaces).isEmpty && ageValue != nil
    }

    var body: some View {
        ZStack {
            WelcomeBackground()
            Group {
                switch step {
                case .start: start
                case .guest: GuestChoice(back: { go(.start) }, choose: chooseDemo)
                case .user: user
                case .connect: connect
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .opacity))
        }
        .preferredColorScheme(.dark)
    }

    private func go(_ next: Step) {
        focusedField = nil
        withAnimation(.snappy) { step = next }
    }

    // MARK: - Welcome

    private var start: some View {
        VStack(spacing: 0) {
            Spacer()
            // Dash himself, live and charged, waving hello once he's on his feet.
            Avatar3DView(energy: 90, gesture: greeting)
                .frame(height: 300)
                .task {
                    try? await Task.sleep(for: .seconds(2))
                    greeting = AvatarGesture.all.first { $0.clip == "wave" }
                }
            BrandTitle()
                .padding(.top, 12)
                .padding(.bottom, 6)
            Text("Your personal energy twin")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()

            VStack(spacing: 14) {
                WelcomeChoice(title: "Continue as a guest",
                              detail: "Explore with a fictional day. Nothing is connected or saved.",
                              systemImage: "play.rectangle.fill", prominent: true) { go(.guest) }
                WelcomeChoice(title: "Continue as a user",
                              detail: "You need to connect with Apple Health, Calendar, and everything.",
                              systemImage: "person.crop.circle.fill", prominent: false) { go(.user) }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }

    // MARK: - About you

    private var user: some View {
        VStack(spacing: 0) {
            BackButton { go(.start) }
            Spacer()

            VStack(spacing: 20) {
                Text("Let's get to know you")
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Your name")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("What should we call you?", text: $nameText)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 12))
                        .focused($focusedField, equals: .name)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Your age")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Age", text: $ageText)
                        .keyboardType(.numberPad)
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
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.1)))
            .padding(.horizontal, 24)

            Spacer()
            PrimaryButton(title: "Continue", enabled: isValid) {
                profile.name = nameText.trimmingCharacters(in: .whitespaces)
                profile.age = ageValue ?? 0
                go(.connect)
            }
        }
        .onAppear {
            nameText = profile.name
            ageText = profile.age > 0 ? String(profile.age) : ""
        }
    }

    // MARK: - Connect

    private var connect: some View {
        VStack(spacing: 0) {
            BackButton { go(.user) }
            Spacer()

            VStack(alignment: .leading, spacing: 18) {
                Text("Connect your data")
                    .font(.title3.weight(.bold))
                Text("myTwin works out your energy from your sleep and heart rate, and plans around your calendar.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ConnectRow(title: "Apple Health", detail: "Sleep, heart rate, steps, workouts and weight",
                           systemImage: "heart.fill", tint: .pink, connected: health.isAuthorized) {
                    Task { await health.requestAuthorization() }
                }
                ConnectRow(title: "Calendar", detail: "Your events, so the plan fits around them",
                           systemImage: "calendar", tint: .blue, connected: calendar.isAuthorized) {
                    Task { await calendar.requestAccess() }
                }

                Text("Everything stays on your iPhone. You can connect later from the You page.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.1)))
            .padding(.horizontal, 24)

            Spacer()
            PrimaryButton(title: health.isAuthorized && calendar.isAuthorized ? "Continue" : "Continue anyway",
                          enabled: true, action: onComplete)
        }
        .task { await health.refreshAuthorizationState() }
    }
}

/// Continue with or without Pro, in the demo. Also opened from the You page.
struct GuestChoice: View {
    let back: () -> Void
    let choose: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            BackButton(action: back)
            Spacer()
            Text("How would you like to try myTwin?")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 28)

            VStack(spacing: 14) {
                WelcomeChoice(title: "Continue with Pro",
                              detail: "Every feature unlocked, with demo data.",
                              systemImage: "bolt.heart.fill", prominent: true) { choose(true) }
                WelcomeChoice(title: "Continue without Pro",
                              detail: "The free version. Pro features show a lock and the upgrade screen.",
                              systemImage: "lock.open.fill", prominent: false) { choose(false) }
            }
            .padding(.horizontal, 24)

            Text("Demo only. This doesn't buy or unlock real Pro.\nYou can switch to your own account at any time.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 20)
            Spacer()
            Spacer()
        }
    }
}

// MARK: - Pieces

struct WelcomeBackground: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.06, green: 0.06, blue: 0.14),
                                Color(red: 0.10, green: 0.08, blue: 0.20),
                                Color.black],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

/// A big choice: a title, one line on what it means, and an icon.
private struct WelcomeChoice: View {
    let title: String
    let detail: String
    let systemImage: String
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(prominent ? .white.opacity(0.85) : .secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).opacity(0.7)
            }
            .foregroundStyle(.white)
            .padding(18)
            .frame(maxWidth: .infinity)
            .background {
                if prominent {
                    LinearGradient(colors: BrandTitle.brand, startPoint: .leading, endPoint: .trailing)
                        .clipShape(.rect(cornerRadius: 20))
                } else {
                    RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(prominent ? 0 : 0.12)))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }
}

private struct ConnectRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    let connected: Bool
    let connect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if connected {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(.green)
                    .accessibilityLabel("\(title) connected")
            } else {
                Button("Connect", action: connect)
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                    .accessibilityLabel("Connect \(title)")
            }
        }
    }
}

private struct BackButton: View {
    let action: () -> Void

    var body: some View {
        HStack {
            Button("Back", systemImage: "chevron.left", action: action)
                .font(.body.weight(.medium))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

private struct PrimaryButton: View {
    let title: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(LinearGradient(colors: BrandTitle.brand, startPoint: .leading, endPoint: .trailing)
                                .opacity(enabled ? 1 : 0.3), in: .capsule)
                .shadow(color: BrandTitle.brand[1].opacity(enabled ? 0.4 : 0), radius: 16, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .padding(.horizontal, 32)
        .padding(.bottom, 20)
        .animation(.easeOut(duration: 0.25), value: enabled)
    }
}

#Preview("Welcome") {
    @Previewable @State var profile = UserProfile()
    WelcomeView(profile: $profile) { }
}
