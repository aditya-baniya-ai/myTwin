import Foundation
import AVFoundation
import Speech

/// Listens with Apple's on-device recogniser and speaks answers back.
///
/// In hands-free mode the microphone stays on while the app talks, so you can interrupt it.
/// That means the microphone also hears the app's own voice: echo cancellation removes most of
/// it, and `echoOverlap` throws away whatever gets through.
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

    var status: Status = .idle
    var transcript = ""
    var speaksAnswers = true
    private(set) var handsFree = false

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

    // MARK: - Hands-free conversation

    /// Keeps listening after every answer, so the phone can stay in your pocket.
    func startConversation(onSentence: @escaping (String) -> Void) async {
        handsFree = true
        await start(onSentence: onSentence)
    }

    func stopConversation() async {
        handsFree = false
        stopSpeaking()
        await stop()
    }

    // MARK: - Listening

    /// Starts listening. `onSentence` is called each time you stop talking.
    func start(onSentence: @escaping (String) -> Void) async {
        guard status != .listening else { return }
        self.onSentence = onSentence
        status = .preparing
        transcript = ""
        finalText = ""

        do {
            guard await requestPermissions() else {
                status = .unavailable("Microphone or speech access is off. Turn it on in Settings.")
                return
            }
            guard await SpeechTranscriber.supportedLocales.contains(where: matches) else {
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
            await stop()
            status = .unavailable(error.localizedDescription)
        }
    }

    /// Stops listening and sends whatever was heard.
    func finish() async {
        let sentence = transcript
        let handler = onSentence
        await stop()
        if !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { handler?(sentence) }
    }

    /// Stops listening and releases the microphone.
    func stop() async {
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

        if status == .listening || status == .preparing { status = .idle }
    }

    // MARK: - Speaking

    /// Reads an answer aloud with the built-in offline voice.
    func speak(_ text: String) {
        guard speaksAnswers else { return }
        stopSpeaking()

        // In hands-free the recording session stays as it is: switching categories would
        // tear down the microphone and the echo cancellation with it.
        if !handsFree {
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
            try? await Task.sleep(for: .milliseconds(800))  // echo tail: shorter and it hears itself
            guard !Task.isCancelled else { return }
            transcript = ""
            finalText = ""
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

                    if result.isFinal {
                        finalText += text
                        transcript = finalText
                    } else {
                        transcript = finalText + text  // live guess while you're still talking
                    }
                    lastHeard = .now
                }
            } catch {
                self?.status = .unavailable("Couldn't hear you: \(error.localizedDescription)")
            }
        }
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

    /// Sends the sentence once you have been quiet for a moment.
    private func watchForSilence() {
        lastHeard = .now
        silenceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, status == .listening else { return }
                let heardSomething = !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                guard heardSomething, !isSpeakingNow, Date.now.timeIntervalSince(lastHeard) > 1.5 else { continue }

                let sentence = transcript
                if handsFree {
                    // Keep the microphone open for the next thing you say.
                    transcript = ""
                    finalText = ""
                    lastHeard = .now
                    onSentence?(sentence)
                } else {
                    await finish()
                    return
                }
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
