import SwiftUI

@main struct MyApp: App {
    /// Registered here rather than on a screen: iOS launches the app in the background when
    /// your watch syncs, and no screen exists then.
    @State private var sample = ProcessInfo.processInfo.arguments.contains("--sample-day")
    @State private var health = HealthManager()
    @State private var profile = UserProfile()
    @State private var onboarded: Bool = UserProfile().isComplete

    var body: some Scene {
        WindowGroup {
            if sample {
                ContentView(isSample: true, leaveSample: { sample = false }).id("sample")
            } else if onboarded {
                ContentView(enterSample: { sample = true }).id("personal")
                    .task {
                        health.watchForNewData { await TwinRefresh.run() }
                    }
            } else {
                WelcomeView(profile: $profile, trySample: { sample = true }) {
                    withAnimation(.easeInOut(duration: 0.4)) { onboarded = true }
                }
            }
        }
    }
}
