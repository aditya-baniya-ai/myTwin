import AVFoundation
import SwiftUI

/// Choose how Dash sounds. Two lists, because he has two voices: Gemini's when you have
/// Pro and a connection, and the iPhone's the rest of the time. Tap any voice to hear it.
struct VoicePicker: View {
    let voice: VoiceManager
    var isPro: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var gemini = VoiceChoice.gemini
    @State private var deviceIdentifier = VoiceChoice.device()?.identifier

    private var deviceVoices: [AVSpeechSynthesisVoice] { VoiceChoice.deviceVoices() }

    var body: some View {
        NavigationStack {
            List {
                deviceSection
                geminiSection
            }
            .navigationTitle("Dash's voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { voice.stopPreview(); dismiss() }
                }
            }
            .onDisappear { voice.stopPreview() }
        }
    }

    // MARK: - The iPhone's own voice

    private var deviceSection: some View {
        Section {
            if deviceVoices.isEmpty {
                Text("This iPhone has no voices for your language.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(deviceVoices, id: \.identifier) { item in
                row(title: item.name,
                    detail: [item.language,
                             VoiceChoice.qualityName(item.quality),
                             gendered(item.gender)].compactMap { $0 }.joined(separator: " · "),
                    chosen: deviceIdentifier == item.identifier,
                    playing: voice.previewing == item.identifier) {
                    deviceIdentifier = item.identifier
                    VoiceChoice.deviceIdentifier = item.identifier
                    voice.preview(item)
                }
            }
        } header: {
            Text("On this iPhone")
        } footer: {
            Text("Used offline, and whenever Gemini isn't answering. Download an Enhanced or "
                 + "Premium voice in Settings › Accessibility › Spoken Content › Voices and it "
                 + "appears here.")
        }
    }

    // MARK: - Gemini

    private var geminiSection: some View {
        Section {
            ForEach(VoiceChoice.geminiVoices) { item in
                row(title: item.name,
                    detail: "\(item.character) · sounds \(item.sounds)",
                    chosen: gemini == item.name,
                    playing: false) {
                    gemini = item.name
                    VoiceChoice.gemini = item.name
                }
            }
        } header: {
            Text("With Gemini")
        } footer: {
            Text(isPro
                 ? "Used when you're online. Google doesn't publish these voices' genders, so "
                   + "they're sorted by ear. Ask Dash something to hear the one you picked."
                 : "Used when you're online, with myTwin Pro. You can still choose one now.")
        }
    }

    // MARK: - Pieces

    private func row(title: String, detail: String, chosen: Bool, playing: Bool,
                     pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(chosen ? .semibold : .regular))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if playing {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(BrandTitle.brand[1])
                        .symbolEffect(.variableColor)
                } else if chosen {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(BrandTitle.brand[1])
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func gendered(_ gender: AVSpeechSynthesisVoiceGender) -> String? {
        switch gender {
        case .male: "male"
        case .female: "female"
        default: nil
        }
    }
}
