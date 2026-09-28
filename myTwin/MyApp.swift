import SwiftUI

@main struct MyApp: App {
    /// Registered here rather than on a screen: iOS launches the app in the background when
    /// your watch syncs, and no screen exists then.
    @State private var health = HealthManager()
    @State private var profile = UserProfile()
    @State private var onboarded: Bool = UserProfile().isComplete
    /// The guest demo, with Pro (`true`) or without. Nil when you're not in it.
    /// `--sample-day` opens it with Pro and `--demo-free` without, for demos and UI tests.
    @State private var demo: Bool? = {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--demo-free") { return false }
        return arguments.contains("--sample-day") ? true : nil
    }()
    /// On your own home screen, picking Pro or Free before trying the demo.
    @State private var choosingDemo = false
    /// Where the welcome screen starts: its first page, or "about you" when you leave the
    /// demo to set up your own account.
    @State private var welcomeStep = WelcomeView.Step.start

    var body: some Scene {
        WindowGroup {
            // One navigation container for the whole app. Swapping the demo and personal
            // screens inside it, rather than each bringing its own, keeps their layout and
            // their touch areas lined up.
            NavigationStack {
                if let pro = demo {
                    ContentView(isSample: true,
                                demoPro: Binding(get: { demo ?? pro }, set: { demo = $0 }),
                                leaveSample: leaveDemo)
                        .id("demo")
                } else if onboarded {
                    if choosingDemo {
                        GuestChoice(back: { choosingDemo = false }, choose: startDemo)
                            .background { WelcomeBackground() }
                            .preferredColorScheme(.dark)
                    } else {
                        ContentView(enterSample: { choosingDemo = true }).id("personal")
                            .task {
                                health.watchForNewData { await TwinRefresh.run() }
                            }
                    }
                } else {
                    WelcomeView(profile: $profile, step: welcomeStep, chooseDemo: startDemo) {
                        withAnimation(.easeInOut(duration: 0.4)) { onboarded = true }
                    }
                    .id(welcomeStep)
                }
            }
        }
    }

    private func startDemo(pro: Bool) {
        choosingDemo = false
        demo = pro
    }

    /// Out of the demo: to your home screen, or to setting up your account if you haven't.
    private func leaveDemo() {
        welcomeStep = .user
        demo = nil
    }
}
