import Foundation
import AVFoundation
import CoreMedia
import Speech

/// Live voice: listens for the wake phrase "my twin", then takes spoken instructions,
/// speaks answers, and lets you talk over it.
///
/// The microphone stays on while the app talks, so it also hears the app's own voice.
/// Echo cancellation removes most of it and `echoOverlap` throws away the rest.
@MainActor
@Observable
final class VoiceManager {
    enum Status: Equatable {
        case idle
        case preparing  // one-time download of the offline language model
        case listening
        case unavailable(String)
    }

    enum VoiceError: LocalizedError {
        case noAudioFormat
        var errorDescription: String? { "This device's microphone format isn't supported." }
    }

    /// How long a pause means "your sentence is finished". Too short and it cuts people off.
    private let pauseBeforeSending: TimeInterval = 2.0
    /// Back to sleep after this much quiet, so it stops reacting to the room.
    private let sleepAfterIdle: TimeInterval = 30
    /// How long the app's own voice keeps echoing after it stops talking.
    private let echoTail: Duration = .milliseconds(800)

    var status: Status = .idle
    var transcript = ""
    var speaksAnswers = true
    private(set) var isLive = false
    private(set) var isAwake = false

    /// One line of plain status, shown on both the home screen and the chat.
    var statusNote: String? {
        switch status {
        case .idle: nil
        case .preparing: "Getting the offline voice model ready…"
        case .listening: isAwake ? "Listening. Just talk, and talk over me to interrupt."
                                 : "Say \"my twin\" to wake me."
        case .unavailable(let reason): reason
        }
    }

    private let locale = Locale.current
    private let engine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var analyzer: SpeechAnalyzer?
    private var inputStream: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var silenceTask: Task<Void, Never>?
    private var speechEndTask: Task<Void, Never>?
    private var onSentence: ((String) -> Void)?
    private var finalText = ""
    private var lastHeard = Date.now
    private var lastSpoken = ""
    private var isSpeakingNow = false
    // Where the last sent sentence ended in the audio. Results before this are already
    // spoken for: without this the recogniser re-delivers them and the app hears you twice.
    private var sentUpTo = CMTime.zero
    private var latestResultEnd = CMTime.zero

    // MARK: - Starting and stopping

    /// Starts listening. Nothing is sent until you say the wake phrase.
    func startLiveVoice(onSentence: @escaping (String) -> Void) async {
        guard !isLive else { return }
        isLive = true
        isAwake = false
        self.onSentence = onSentence
        status = .preparing
        transcript = ""
        finalText = ""
        sentUpTo = .zero
        latestResultEnd = .zero

        do {
            guard await requestPermissions() else {
                isLive = false
                status = .unavailable("Microphone or speech access is off. Turn it on in Settings.")
                return
            }
            guard await SpeechTranscriber.supportedLocales.contains(where: matches) else {
                isLive = false
                status = .unavailable("On-device dictation isn't available for your language.")
                return
            }

            let transcriber = SpeechTranscriber(locale: locale,
                                                transcriptionOptions: [],
                                                reportingOptions: [.volatileResults],
                                                attributeOptions: [])
            try await installModelIfNeeded(for: transcriber)

            guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                throw VoiceError.noAudioFormat
            }

            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            inputStream = continuation
            analyzer = SpeechAnalyzer(inputSequence: stream, modules: [transcriber])

            readResults(from: transcriber)
            try startAudio(analyzerFormat: analyzerFormat)
            watchForSilence()
            status = .listening
        } catch {
            await stopLiveVoice()
            status = .unavailable(error.localizedDescription)
        }
    }

    /// Stops listening and releases the microphone.
    func stopLiveVoice() async {
        isLive = false
        isAwake = false
        onSentence = nil
        stopSpeaking()

        silenceTask?.cancel()
        resultsTask?.cancel()
        silenceTask = nil
        resultsTask = nil

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        inputStream?.finish()
        inputStream = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        analyzer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        transcript = ""
        finalText = ""
        if status == .listening || status == .preparing { status = .idle }
    }

    // MARK: - Speaking

    /// Reads an answer aloud with the built-in offline voice.
    func speak(_ text: String) {
        guard speaksAnswers else { return }
        stopSpeaking()

        // While listening, leave the recording session alone: switching categories would tear
        // down the microphone and its echo cancellation.
        if status != .listening {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try? session.setActive(true)
        }

        lastSpoken = spokenText(text)
        isSpeakingNow = true

        let utterance = AVSpeechUtterance(string: lastSpoken)
        utterance.voice = AVSpeechSynthesisVoice(language: locale.identifier)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
        watchForSpeechEnd()
    }

    func stopSpeaking() {
        speechEndTask?.cancel()
        speechEndTask = nil
        isSpeakingNow = false
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    /// After the app stops talking, ignore the tail of its own voice before listening again.
    private func watchForSpeechEnd() {
        speechEndTask = Task { [weak self] in
            while let self, synthesizer.isSpeaking, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard let self, !Task.isCancelled else { return }
            isSpeakingNow = false
            try? await Task.sleep(for: echoTail)
            guard !Task.isCancelled else { return }
            transcript = ""
            finalText = ""
            sentUpTo = latestResultEnd
            lastHeard = .now
        }
    }

    /// The model sometimes replies in markdown, which sounds like "asterisk asterisk".
    private func spokenText(_ text: String) -> String {
        text.replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "–", with: "to")
    }

    // MARK: - Microphone

    private func startAudio(analyzerFormat: AVAudioFormat) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let input = engine.inputNode
        // Echo cancellation, so the microphone hears you and not the app's own voice.
        try? input.setVoiceProcessingEnabled(true)

        let micFormat = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: micFormat, to: analyzerFormat) else {
            throw VoiceError.noAudioFormat
        }

        let continuation = inputStream
        input.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { buffer, _ in
            // Runs on the audio thread. The recogniser needs its own format: feeding it the
            // microphone's format transcribes nothing at all, with no error.
            guard let converted = convertBuffer(buffer, with: converter, to: analyzerFormat) else { return }
            continuation?.yield(AnalyzerInput(buffer: converted))
        }
        engine.prepare()
        try engine.start()
    }

    // MARK: - Results

    private func readResults(from transcriber: SpeechTranscriber) {
        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self else { return }
                    latestResultEnd = max(latestResultEnd, result.range.end)

                    // Skip audio that was already sent as a sentence.
                    guard result.range.end > sentUpTo else { continue }

                    let text = String(result.text.characters)
                    if isSpeakingNow {
                        guard isInterruption(text) else {
                            // The app hearing itself: throw it away.
                            finalText = ""
                            transcript = ""
                            continue
                        }
                        stopSpeaking()  // you talked over it
                        finalText = ""
                    }

                    let heard = result.isFinal ? finalText + text : finalText + text
                    if result.isFinal { finalText += text }

                    if isAwake {
                        transcript = heard
                        lastHeard = .now
                    } else if let command = commandAfterWakePhrase(in: heard) {
                        wakeUp(with: command)
                    } else if result.isFinal {
                        // Not addressed to the app: forget it and keep waiting.
                        finalText = ""
                        transcript = ""
                        sentUpTo = latestResultEnd
                    }
                }
            } catch {
                self?.status = .unavailable("Couldn't hear you: \(error.localizedDescription)")
            }
        }
    }

    private func wakeUp(with command: String) {
        isAwake = true
        finalText = command
        transcript = command
        lastHeard = .now
        if command.isEmpty { speak("Yes?") }
    }

    /// Real speech while the app is talking, rather than its own voice coming back.
    private func isInterruption(_ heard: String) -> Bool {
        let heardWords = spokenWords(heard)
        guard heardWords.count >= 2 else { return false }  // single words are usually echo

        // A number the app never said ("move it to 5") means you're giving a new instruction.
        let spoken = Set(spokenWords(lastSpoken))
        if heardWords.contains(where: { $0.first?.isNumber == true && !spoken.contains($0) }) { return true }

        return echoOverlap(heard: heard, spoken: lastSpoken) < 0.6
    }

    /// Sends the sentence once you have been quiet for a moment, then keeps listening.
    private func watchForSilence() {
        lastHeard = .now
        silenceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, status == .listening else { return }
                let quietFor = Date.now.timeIntervalSince(lastHeard)
                let sentence = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

                guard isAwake else { continue }

                if sentence.isEmpty {
                    if !isSpeakingNow, quietFor > sleepAfterIdle { isAwake = false }
                    continue
                }
                guard !isSpeakingNow, quietFor > pauseBeforeSending else { continue }

                sentUpTo = latestResultEnd  // don't hear this sentence a second time
                transcript = ""
                finalText = ""
                lastHeard = .now
                onSentence?(sentence)
            }
        }
    }

    // MARK: - Setup

    private func requestPermissions() async -> Bool {
        guard await AVAudioApplication.requestRecordPermission() else { return false }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    /// The offline language model downloads once, then dictation works with no connection.
    private func installModelIfNeeded(for transcriber: SpeechTranscriber) async throws {
        guard await !SpeechTranscriber.installedLocales.contains(where: matches) else { return }
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else { return }
        try await request.downloadAndInstall()
    }

    private func matches(_ other: Locale) -> Bool {
        other.identifier(.bcp47) == locale.identifier(.bcp47)
    }
}

/// Converts one microphone buffer into the recogniser's format. Runs on the audio thread.
/// (`AnalyzerInputConverter` would do this, but it needs iOS 27.)
nonisolated func convertBuffer(_ buffer: AVAudioPCMBuffer,
                               with converter: AVAudioConverter,
                               to format: AVAudioFormat) -> AVAudioPCMBuffer? {
    let ratio = format.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
    guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

    var used = false
    var error: NSError?
    converter.convert(to: output, error: &error) { _, status in
        if used {
            status.pointee = .noDataNow
            return nil
        }
        used = true
        status.pointee = .haveData
        return buffer
    }
    guard error == nil, output.frameLength > 0 else { return nil }
    return output
}

/// Finds "my twin" (or "hey twin") and returns whatever was said after it, "" if nothing.
/// Returns nil when the phrase isn't there, so the app stays asleep.
nonisolated func commandAfterWakePhrase(in text: String) -> String? {
    let phrase = /(?i)\b(?:hey|my|hi)[\s,-]*twins?\b[\s,.!?]*/
    guard let match = text.firstMatch(of: phrase) else { return nil }
    return String(text[match.range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
}

/// How much of what was heard also appears in what the app just said, 0…1.
/// A high score means the microphone picked up the app's own voice.
nonisolated func echoOverlap(heard: String, spoken: String) -> Double {
    let heardWords = spokenWords(heard)
    guard !heardWords.isEmpty else { return 0 }
    let spokenWords = Set(spokenWords(spoken))
    let shared = heardWords.filter { spokenWords.contains($0) }.count
    return Double(shared) / Double(heardWords.count)
}

private nonisolated func spokenWords(_ text: String) -> [String] {
    // Dictation writes "p.m." where the app said "PM": without dropping the dots those
    // tokenise differently and the app's own voice stops looking like an echo.
    text.lowercased()
        .replacingOccurrences(of: ".", with: "")
        .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        .map(String.init)
}
