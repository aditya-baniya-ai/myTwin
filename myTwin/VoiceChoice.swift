import AVFoundation
import Foundation

/// Which voice Dash speaks with, in both modes, remembered between launches.
///
/// There are two, because there are two ways he can speak: Gemini's own voice when you
/// have Pro and a connection, and the iPhone's built-in speech the rest of the time.
/// Neither can stand in for the other, so each is chosen separately.
enum VoiceChoice {
    private static let geminiKey = "voice.gemini"
    private static let deviceKey = "voice.device"

    // MARK: - Gemini

    /// One of Gemini's prebuilt voices. Google publishes each voice's character but not
    /// its gender, so these were sorted by ear.
    struct GeminiVoice: Identifiable, Hashable {
        let name: String
        let character: String
        let sounds: String          // "male" / "female", by ear rather than by spec
        var id: String { name }
    }

    static let geminiVoices: [GeminiVoice] = [
        .init(name: "Puck", character: "Upbeat", sounds: "male"),
        .init(name: "Charon", character: "Informative", sounds: "male"),
        .init(name: "Fenrir", character: "Excitable", sounds: "male"),
        .init(name: "Orus", character: "Firm", sounds: "male"),
        .init(name: "Iapetus", character: "Clear", sounds: "male"),
        .init(name: "Algenib", character: "Gravelly", sounds: "male"),
        .init(name: "Kore", character: "Firm", sounds: "female"),
        .init(name: "Aoede", character: "Breezy", sounds: "female"),
        .init(name: "Leda", character: "Youthful", sounds: "female"),
        .init(name: "Zephyr", character: "Bright", sounds: "female"),
        .init(name: "Sulafat", character: "Warm", sounds: "female"),
        .init(name: "Vindemiatrix", character: "Gentle", sounds: "female"),
    ]

    static let defaultGemini = "Puck"

    static var gemini: String {
        get { UserDefaults.standard.string(forKey: geminiKey) ?? defaultGemini }
        set { UserDefaults.standard.set(newValue, forKey: geminiKey) }
    }

    // MARK: - The iPhone's own voice

    /// Every voice the iPhone can speak this language with, best quality first. The
    /// MacinTalk novelty voices are left out: they are still installed and still report a
    /// gender, but they sound like 1984.
    static func deviceVoices(for identifier: String = Locale.current.identifier) -> [AVSpeechSynthesisVoice] {
        let legacy = "com.apple.speech.synthesis.voice"
        let language = identifier.prefix(2)
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) && !$0.identifier.hasPrefix(legacy) }
            .sorted {
                rank($0.quality) != rank($1.quality)
                    ? rank($0.quality) > rank($1.quality)
                    : $0.name < $1.name
            }
    }

    /// The chosen voice, or the best male one if nothing has been chosen yet.
    static func device(for identifier: String = Locale.current.identifier) -> AVSpeechSynthesisVoice? {
        if let saved = UserDefaults.standard.string(forKey: deviceKey),
           let voice = AVSpeechSynthesisVoice(identifier: saved) {
            return voice
        }
        let voices = deviceVoices(for: identifier)
        return voices.first { $0.gender == .male && $0.language == identifier }
            ?? voices.first { $0.gender == .male }
            ?? AVSpeechSynthesisVoice(language: identifier)
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    static var deviceIdentifier: String? {
        get { UserDefaults.standard.string(forKey: deviceKey) }
        set { UserDefaults.standard.set(newValue, forKey: deviceKey) }
    }

    static func rank(_ quality: AVSpeechSynthesisVoiceQuality) -> Int {
        switch quality {
        case .premium: 3
        case .enhanced: 2
        default: 1
        }
    }

    static func qualityName(_ quality: AVSpeechSynthesisVoiceQuality) -> String? {
        switch quality {
        case .premium: "Premium"
        case .enhanced: "Enhanced"
        default: nil
        }
    }

    /// What a voice says when you try it out.
    static let sample = "Hi, I'm myTwin. You've got good energy this morning, so let's use it."
}
