import Foundation
import Network

/// Whether myTwin should use Google's Gemini right now.
///
/// You're asked once. If you allow it, Gemini answers whenever the phone is online (Wi-Fi
/// or mobile data), without asking again. Offline, or if you said no, everything stays on
/// the iPhone.
@MainActor
@Observable
final class GeminiAccess {
    /// Google's default model for real-time voice conversations (checked 2026-09-19).
    static let model = "gemini-3.8-live"
    private static let decisionKey = "geminiDecision"

    /// Your one-time answer: true for allow, false for don't, nil until you're asked.
    var allowed: Bool? {
        didSet { UserDefaults.standard.set(allowed, forKey: Self.decisionKey) }
    }
    private(set) var isOnline = false

    /// Built in from Config/Secrets.xcconfig, which is never committed. Nil when missing.
    let apiKey: String?

    private let monitor = NWPathMonitor()

    /// Ask once, and only when the app can actually reach Gemini.
    var needsAnswer: Bool { allowed == nil && apiKey != nil }

    /// True when a conversation should go to Gemini rather than stay on the iPhone.
    var isActive: Bool { allowed == true && apiKey != nil && isOnline }

    init() {
        allowed = UserDefaults.standard.object(forKey: Self.decisionKey) == nil
            ? nil : UserDefaults.standard.bool(forKey: Self.decisionKey)
        let key = (Bundle.main.object(forInfoDictionaryKey: "GeminiAPIKey") as? String)?
            .trimmingCharacters(in: .whitespaces)
        apiKey = key?.isEmpty == false ? key : nil

        // The monitor reports on the main queue, so the update can be applied right away.
        monitor.pathUpdateHandler = { [weak self] path in
            MainActor.assumeIsolated { self?.isOnline = path.status == .satisfied }
        }
        monitor.start(queue: .main)
    }
}
