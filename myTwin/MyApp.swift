import SwiftUI

@main struct MyApp: App {
    /// Registered here rather than on a screen: iOS launches the app in the background when
    /// your watch syncs, and no screen exists then.
    @State private var health = HealthManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    health.watchForNewData { await TwinRefresh.run() }
                }
        }
    }
}
