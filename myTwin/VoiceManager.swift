import Foundation
import AVFoundation
import CoreMedia
import Speech

/// Live voice: listens for the wake word "twin", then takes spoken instructions,
/// speaks answers (in the iPhone's voice, or Gemini's when it answers), and lets you talk
/// over it.
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

    /// Hands-free, how long a pause means "your sentence is finished". Long, because being
    /// cut off mid-thought is worse than waiting. Tap Dash instead and nothing cuts you off.
    private let pauseBeforeSending: TimeInterval = 5.0
    /// Back to sleep after this much quiet, so it stops reacting to the room.
    private let sleepAfterIdle: TimeInterval = 30
    /// How long the app's own voice keeps echoing after it stops talking.
    private let echoTail: Duration = .milliseconds(800)

    var status: Status = .idle
    var transcript = ""
    var speaksAnswers = true
    /// The identifier of the voice being tried out right now, for the voice picker.
    private(set) var previewing: String?
    private(set) var isLive = false
    private(set) var isAwake = false
    /// Tap to talk: listening until you tap again, however long you pause.
    private(set) var isDictating = false
    /// A call, Siri or another app has the microphone. Nothing can be heard until it ends.
    private(set) var isInterrupted = false
    /// The microphone is really running, not just meant to be.
    private(set) var isHearing = false
    /// How loud the microphone is right now, 0 to 1, for the recording bar.
    private(set) var inputLevel: Float = 0
    /// When the current tap-to-talk began, for the recording bar's timer.
    private(set) var dictationStarted: Date?
    /// You tapped to send and the recogniser is still catching up with what you said.
    private(set) var isFinishing = false
    /// Where this dictation goes instead of the chat, such as the goals box. Cleared when
    /// the dictation ends.
    private var dictationTarget: ((String) -> Void)?
    /// A reply in a conversation with Dash: it ends by itself after a short silence, or gives
    /// up if nothing is said. Nil for tap-to-talk, which only your tap ends.
    private var autoEnd: (pause: TimeInterval, giveUp: TimeInterval, onSilence: () -> Void)?
    /// When the microphone last heard something as loud as speech. Silence is judged by this,
    /// not by when words arrive: the recogniser delivers them seconds late and in bursts.
    private var lastLoud = Date.distantPast

    /// One line of plain status, shown on both the home screen and the chat.
    var statusNote: String? {
        switch status {
        case .idle: nil
        case .preparing: "Preparing on-device speech… You can type in chat while it loads."
        case _ where isInterrupted: "Your microphone is busy with a call."
        case .listening where !isHearing: nil            // starting up: not worth saying
        case .listening where isDictating: nil          // the recording bar says it
        case .listening: isAwake ? "Listening…"
                                 : "Tap Dash to talk, or say \"twin\"."
        case .unavailable(let reason): reason
        }
    }

    private let locale = Locale.current
    private let engine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    // Gemini's voice arrives as 24 kHz, 16-bit mono PCM and plays through the same engine as
    // the microphone, so echo cancellation can take it back out of what the microphone hears.
    private let player = AVAudioPlayerNode()
    private let geminiFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000,
                                             channels: 1, interleaved: false)!
    private var speechConverter: AVAudioConverter?
    private var playbackGeneration = 0
    private var dictationGeneration = 0
    private var queuedSpeech = 0         // pieces of Gemini's voice waiting to play
    private var speechCut = false        // you talked over Gemini: skip the rest of that answer
    /// An answer is still arriving from Gemini. Its audio comes in pieces over the network,
    /// so the queue draining for a moment doesn't mean he has finished talking.
    private var geminiAnswering = false
    /// When his words last arrived. While they are still streaming, `lastSpoken` is behind
    /// the speaker and the echo test cannot be trusted.
    private var lastGeminiWordsAt: Date?
    private var analyzer: SpeechAnalyzer?
    private var inputStream: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var silenceTask: Task<Void, Never>?
    private var engineTask: Task<Void, Never>?
    private var interruptionTask: Task<Void, Never>?
    private var analyzerFormat: AVAudioFormat?
    private var speechEndTask: Task<Void, Never>?
    private var onSentence: ((String) -> Void)?
    /// What you have said so far, in pieces. The recogniser often revises a stretch it
    /// already reported, so pieces are replaced by range rather than piled up: without this
    /// the same sentence comes back twice, with two different endings.
    private var pieces: [(range: CMTimeRange, text: String)] = []
    private var lastHeard = Date.now
    private var lastSpoken = ""
    /// When Gemini's voice began. Its words arrive on a separate, slower stream, so for a
    /// moment the speaker is ahead of `lastSpoken` and its own echo looks like a stranger.
    private var geminiAudioStarted: Date?
    /// How long the words are given to catch up with the voice.
    private let transcriptionLag: TimeInterval = 2.0
    private var isSpeakingNow = false
    private var previewTask: Task<Void, Never>?
    /// Consecutive results that didn't look like echo, so one stray word can't cut an answer.
    private var nonEchoResults = 0
    // The recogniser delivers speech in pieces; the wake phrase can straddle two of them.
    private var recentSpeech: [String] = []
    // Where the last sent sentence ended in the audio. Results before this are already
    // spoken for: without this the recogniser re-delivers them and the app hears you twice.
    private var sentUpTo = CMTime.zero
    private var latestResultEnd = CMTime.zero
    /// How much audio has gone to the recogniser, on its own clock.
    private var audioFed = 0.0

    // MARK: - Starting and stopping

    /// Starts listening. Nothing is sent until you say the wake phrase. Already listening,
    /// it hands what you say to the new `onSentence` instead: there is one microphone, and
    /// the screen in front of you gets it.
    func startLiveVoice(onSentence: @escaping (String) -> Void) async {
        guard !isLive else { self.onSentence = onSentence; return }
        isLive = true
        isAwake = false
        self.onSentence = onSentence
        status = .preparing
        transcript = ""
        pieces = []
        sentUpTo = .zero
        latestResultEnd = .zero
        audioFed = 0

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
            self.analyzerFormat = analyzerFormat
            try startAudio(analyzerFormat: analyzerFormat)
            watchForSilence()
            watchTheEngine()
            watchForInterruptions()
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
        isDictating = false
        isFinishing = false
        dictationStarted = nil
        dictationTarget = nil; autoEnd = nil
        onSentence = nil
        stopSpeaking()

        silenceTask?.cancel()
        resultsTask?.cancel()
        engineTask?.cancel()
        interruptionTask?.cancel()
        silenceTask = nil
        resultsTask = nil
        engineTask = nil
        interruptionTask = nil
        isInterrupted = false

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        inputStream?.finish()
        inputStream = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        analyzer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        transcript = ""
        pieces = []
        recentSpeech = []
        if status == .listening || status == .preparing { status = .idle }
    }

    // MARK: - Tap to talk

    /// Your turn in a conversation with Dash: no tap and no "twin". What you say goes to
    /// `target` once you've been quiet for `pause` seconds; if you say nothing for `giveUp`
    /// seconds, `onSilence` is called instead. Returns false when the microphone isn't ready.
    @discardableResult
    func listenForReply(pause: TimeInterval = 3, giveUp: TimeInterval = 30,
                        target: @escaping (String) -> Void, onSilence: @escaping () -> Void) -> Bool {
        guard status == .listening, !isInterrupted else { return false }
        startDictation(into: target)
        autoEnd = (pause, giveUp, onSilence)
        lastLoud = .distantPast
        return true
    }

    /// Returns once Dash has stopped talking and the echo of his voice has died away, so the
    /// microphone can open without hearing him.
    func waitUntilQuiet() async {
        try? await Task.sleep(for: .milliseconds(300))     // speech takes a moment to start
        while !Task.isCancelled && (synthesizer.isSpeaking || queuedSpeech > 0 || geminiAnswering || isSpeakingNow) {
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: echoTail)
    }

    /// A dictation whose words go to `target` rather than to Dash.
    func startDictation(into target: @escaping (String) -> Void) {
        guard status == .listening else { return }
        startDictation()
        dictationTarget = target
    }

    /// Starts a dictation that you end yourself, so no pause is ever taken for the end.
    func startDictation() {
        guard status == .listening else { return }
        dictationGeneration += 1
        stopSpeaking()                  // tapping Dash while he talks means you want the floor
        dictationTarget = nil; autoEnd = nil
        isDictating = true
        isAwake = true
        dictationStarted = .now
        recentSpeech = []
        pieces = []
        transcript = ""
        sentUpTo = latestResultEnd      // ignore whatever was said before the tap
        lastHeard = .now
    }

    /// Ends the dictation and sends what you said, once the recogniser has caught up.
    ///
    /// The recogniser runs seconds behind your voice and reports in bursts, so at the tap
    /// most of the sentence can still be on its way. Waiting for the words to stop changing
    /// sent "so" and dropped "how's my day today?" that followed a second later. Instead,
    /// the recogniser is told to finish everything up to the tap, and the sentence goes
    /// once it has, or after four seconds at most.
    func finishDictation() {
        guard isDictating, !isFinishing else { return }
        isFinishing = true
        let generation = dictationGeneration
        let tap = CMTime(seconds: audioFed, preferredTimescale: 1000)
        let analyzer = analyzer
        var finalized = false
        Task {
            try? await analyzer?.finalize(through: tap)
            finalized = true
        }
        Task { [weak self] in
            let deadline = Date.now.addingTimeInterval(4)
            while let self, isDictating, !finalized, latestResultEnd < tap, Date.now < deadline {
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .milliseconds(150))   // its last results are still arriving
            guard let self, generation == dictationGeneration else { return }
            isFinishing = false
            guard isDictating else { return }
            isDictating = false
            isAwake = false
            dictationStarted = nil
            let sentence = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            sentUpTo = latestResultEnd
            transcript = ""
            pieces = []
            lastHeard = .now
            let target = dictationTarget ?? onSentence
            dictationTarget = nil; autoEnd = nil
            if !sentence.isEmpty { target?(withoutWakePhrase(sentence)) }
        }
    }

    /// Ends the dictation and throws away what was said.
    func cancelDictation() {
        guard isDictating else { return }
        dictationGeneration += 1
        dictationTarget = nil; autoEnd = nil
        isDictating = false
        isFinishing = false
        isAwake = false
        dictationStarted = nil
        sentUpTo = latestResultEnd
        transcript = ""
        pieces = []
        lastHeard = .now
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
        utterance.voice = VoiceChoice.device(for: locale.identifier)
        synthesizer.speak(utterance)
        watchForSpeechEnd()
    }

    /// Speaks a sample in one particular voice, for trying voices out. Separate from
    /// `speak` so a preview never counts as something Dash said.
    func preview(_ voice: AVSpeechSynthesisVoice?) {
        previewTask?.cancel()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: VoiceChoice.sample)
        utterance.voice = voice
        previewing = voice?.identifier
        synthesizer.speak(utterance)
        previewTask = Task { [weak self] in
            // The synthesizer takes a moment to report itself as speaking.
            try? await Task.sleep(for: .milliseconds(150))
            while let self, synthesizer.isSpeaking, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard let self, !Task.isCancelled else { return }
            previewing = nil
        }
    }

    func stopPreview() {
        previewTask?.cancel()
        previewTask = nil
        previewing = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    func stopSpeaking() {
        playbackGeneration += 1
        queuedSpeech = 0
        speechCut = true
        nonEchoResults = 0
        geminiAnswering = false
        speechEndTask?.cancel()
        speechEndTask = nil
        isSpeakingNow = false
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        if player.isPlaying {
            player.stop()
            speechCut = true
        }
    }

    // MARK: - Gemini's voice

    /// Call as each Gemini answer starts, so it plays even if you cut off the last one.
    func startGeminiAnswer() {
        stopSpeaking()
        speechCut = false
        lastSpoken = ""
        geminiAudioStarted = nil
        lastGeminiWordsAt = nil
        geminiAnswering = true
    }

    /// Call when Gemini has sent everything, or stopped. Until then the app keeps treating
    /// him as talking even if the audio queue empties between pieces.
    func endGeminiAnswer() {
        geminiAnswering = false
    }

    /// Plays the next piece of Gemini's voice as it streams in.
    func play(geminiSpeech pcm: Data) {
        guard speaksAnswers, !speechCut, let piece = floatBuffer(fromPCM16: pcm) else { return }
        do { try startPlayer() } catch { return }
        guard let buffer = matchEngine(piece) else { return }
        queuedSpeech += 1
        isSpeakingNow = true
        if geminiAudioStarted == nil { geminiAudioStarted = .now }
        // The manager lives as long as the app, so holding it until the piece plays is fine.
        let generation = playbackGeneration
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
            Task { @MainActor in
                guard generation == self.playbackGeneration else { return }
                self.queuedSpeech -= 1
            }
        }
        if speechEndTask == nil { watchForSpeechEnd() }
    }

    /// The words Gemini is saying, so its voice coming back through the microphone isn't
    /// taken for yours.
    func addGeminiWords(_ words: String) {
        lastSpoken += words
        lastGeminiWordsAt = .now
    }

    private func startPlayer() throws {
        // Attached only now: adding it before the microphone starts stops the engine dead,
        // and then nothing is ever heard.
        attachPlayer()
        if !engine.isRunning {
            // Not listening: play through the speaker and leave the microphone off.
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            try engine.start()
        }
        if !player.isPlaying { player.play() }
    }

    private func attachPlayer() {
        guard player.engine == nil else { return }
        engine.attach(player)
        // The mixer's own format: a 24 kHz connection alongside the microphone's echo
        // cancellation is what stopped the engine.
        engine.connect(player, to: engine.mainMixerNode, format: nil)
    }

    /// Gemini's 24 kHz voice, resampled to whatever the engine plays.
    private func matchEngine(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let format = player.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format != buffer.format else { return buffer }
        if speechConverter?.inputFormat != buffer.format || speechConverter?.outputFormat != format {
            speechConverter = AVAudioConverter(from: buffer.format, to: format)
        }
        guard let speechConverter else { return nil }
        return convertBuffer(buffer, with: speechConverter, to: format)
    }

    /// 16-bit samples as they arrive from Gemini, to the float samples the engine plays.
    private func floatBuffer(fromPCM16 pcm: Data) -> AVAudioPCMBuffer? {
        let frames = pcm.count / 2
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: geminiFormat, frameCapacity: AVAudioFrameCount(frames)),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        pcm.withUnsafeBytes { raw in
            for index in 0..<frames {
                samples[index] = Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: index * 2, as: Int16.self))) / 32768
            }
        }
        return buffer
    }

    /// After the app stops talking, ignore the tail of its own voice before listening again.
    private func watchForSpeechEnd() {
        speechEndTask = Task { [weak self] in
            while let self, synthesizer.isSpeaking || queuedSpeech > 0 || geminiAnswering,
                  !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard let self, !Task.isCancelled else { return }
            isSpeakingNow = false
            try? await Task.sleep(for: echoTail)
            guard !Task.isCancelled else { return }
            transcript = ""
            pieces = []
            sentUpTo = latestResultEnd
            lastHeard = .now
            speechEndTask = nil
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
        if engine.isRunning { engine.stop() }  // it may be playing Gemini: voice processing needs it stopped
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let input = engine.inputNode
        // Echo cancellation, so the microphone hears you and not the app's own voice.
        try? input.setVoiceProcessingEnabled(true)

        let micFormat = input.outputFormat(forBus: 0)
        // A microphone that isn't ready reports an empty format, and tapping it aborts the
        // app rather than throwing.
        guard micFormat.sampleRate > 0, micFormat.channelCount > 0 else { throw VoiceError.noAudioFormat }
        guard let converter = AVAudioConverter(from: micFormat, to: analyzerFormat) else {
            throw VoiceError.noAudioFormat
        }

        let continuation = inputStream
        input.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { [weak self] buffer, _ in
            // Runs on the audio thread. The recogniser needs its own format: feeding it the
            // microphone's format transcribes nothing at all, with no error.
            let level = loudness(of: buffer)
            guard let converted = convertBuffer(buffer, with: converter, to: analyzerFormat) else {
                return
            }
            continuation?.yield(AnalyzerInput(buffer: converted))
            let seconds = Double(converted.frameLength) / analyzerFormat.sampleRate
            Task { @MainActor in
                self?.inputLevel = level
                self?.audioFed += seconds
                if level > 0.3 { self?.lastLoud = .now }
            }
        }
        engine.prepare()
        try engine.start()
        isHearing = engine.isRunning
    }

    /// While a call holds the microphone there is nothing to restart, and trying would only
    /// fight it. This notices the call starting and ending.
    private func watchForInterruptions() {
        interruptionTask?.cancel()
        interruptionTask = Task { [weak self] in
            let interruptions = NotificationCenter.default.notifications(named: AVAudioSession.interruptionNotification)
            for await note in interruptions {
                guard let self else { return }
                let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt ?? 0
                switch AVAudioSession.InterruptionType(rawValue: raw) {
                case .began:
                    isInterrupted = true
                    isDictating = false          // whatever you were saying is lost with the microphone
                    dictationTarget = nil; autoEnd = nil
                    isFinishing = false
                    dictationStarted = nil
                    isAwake = false
                case .ended:
                    isInterrupted = false        // the engine watchdog starts the microphone again
                default:
                    break
                }
            }
        }
    }

    /// A call, Siri or an audio glitch can stop the engine under us. Start it again, so the
    /// microphone never goes quiet without anyone noticing.
    private func watchTheEngine() {
        engineTask?.cancel()
        engineTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                isHearing = engine.isRunning
                guard isLive, status == .listening, !isInterrupted, !engine.isRunning,
                      let analyzerFormat else { continue }
                engine.inputNode.removeTap(onBus: 0)
                try? startAudio(analyzerFormat: analyzerFormat)
                isHearing = engine.isRunning
            }
        }
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
                            nonEchoResults = 0
                            pieces = []
                            transcript = ""
                            continue
                        }
                        // Echo that slips past the test tends to come alone. Real speech
                        // keeps coming, so wait for a second result before cutting him off.
                        nonEchoResults += 1
                        guard nonEchoResults >= 2 else { continue }
                        stopSpeaking()  // you talked over it
                        pieces = []
                    }

                    let heard = sentence(adding: text, for: result.range)
                    if result.isFinal { keep(text, for: result.range) }

                    if isAwake {
                        transcript = heard
                        lastHeard = .now
                    } else if let command = commandAfterWakePhrase(in: (recentSpeech + [heard]).joined(separator: " ")) {
                        wakeUp(with: command, at: result.range)
                    } else if result.isFinal {
                        // The recogniser often splits the wake word across two results, so keep
                        // the last couple: clearing immediately meant it never matched.
                        recentSpeech = (recentSpeech + [text]).suffix(2).map { $0 }
                        pieces = []
                        transcript = ""
                        sentUpTo = latestResultEnd
                    }
                }
            } catch {
                self?.status = .unavailable("Couldn't hear you: \(error.localizedDescription)")
            }
        }
    }

    private func wakeUp(with command: String, at range: CMTimeRange) {
        isAwake = true
        recentSpeech = []
        pieces = command.isEmpty ? [] : [(range, command)]
        transcript = command
        lastHeard = .now
        if command.isEmpty { speak("Yes?") }
    }

    /// What you have said, with `text` replacing any earlier version of the same stretch.
    private func sentence(adding text: String, for range: CMTimeRange) -> String {
        (pieces.filter { $0.range.intersection(range).isEmpty } + [(range: range, text: text)])
            .sorted { $0.range.start < $1.range.start }
            .map(\.text)
            .joined()
    }

    private func keep(_ text: String, for range: CMTimeRange) {
        pieces.removeAll { !$0.range.intersection(range).isEmpty }
        pieces.append((range, text))
    }

    /// Real speech while the app is talking, rather than its own voice coming back.
    private func isInterruption(_ heard: String) -> Bool {
        let heardWords = spokenWords(heard)
        guard heardWords.count >= 2 else { return false }  // single words are usually echo

        // Gemini's audio outruns its transcription for the whole answer, not just its
        // start: whatever he has just said may not be in `lastSpoken` yet, so his own echo
        // matches nothing and reads as you cutting in. While his words are still arriving,
        // there is nothing trustworthy to compare against.
        if let words = lastGeminiWordsAt, Date.now.timeIntervalSince(words) < transcriptionLag {
            return false
        }
        if let started = geminiAudioStarted, lastSpoken.isEmpty,
           Date.now.timeIntervalSince(started) < transcriptionLag {
            return false
        }

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

                // Tap to talk only ever ends with your tap: the recogniser reports seconds
                // late and in bursts, so "no new words for a while" happened mid-sentence.
                // A reply to Dash ends when the microphone itself has gone quiet.
                if isDictating {
                    guard let auto = autoEnd, !isFinishing, !isSpeakingNow else { continue }
                    if sentence.isEmpty {
                        if let started = dictationStarted, Date.now.timeIntervalSince(started) > auto.giveUp {
                            cancelDictation()
                            auto.onSilence()
                        }
                    } else {
                        // A soft voice may never count as loud: then the last words heard stand in.
                        let quietSince = lastLoud == .distantPast ? lastHeard : lastLoud
                        if Date.now.timeIntervalSince(quietSince) > auto.pause { finishDictation() }
                    }
                    continue
                }

                if sentence.isEmpty {
                    if !isSpeakingNow, quietFor > sleepAfterIdle { isAwake = false }
                    continue
                }
                guard !isSpeakingNow, quietFor > pauseBeforeSending else { continue }

                sentUpTo = latestResultEnd  // don't hear this sentence a second time
                transcript = ""
                pieces = []
                lastHeard = .now
                isAwake = false              // one question per wake: say "twin" again for more
                onSentence?(withoutWakePhrase(sentence))
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

/// A buffer's loudness on a 0-1 scale: -50 dB and below is silence, -10 dB is loud speech.
nonisolated func loudness(of buffer: AVAudioPCMBuffer) -> Float {
    guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
    var sum: Float = 0
    for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
    let decibels = 10 * log10(max(sum / Float(buffer.frameLength), 1e-10))
    return min(max((decibels + 50) / 40, 0), 1)
}

/// Finds "twin" (also "my twin", "hey twin") and returns whatever was said after it, ""
/// if nothing. Returns nil when the word isn't there, so the app stays asleep.
nonisolated func commandAfterWakePhrase(in text: String) -> String? {
    // "twin" elongated, and the near-misses dictation actually produces for it. Everything
    // here starts with the "tw" sound, which is what makes it recognisable as his name.
    let phrase = /(?i)\b(?:hey|my|hi|ok)?[\s,-]*(?:tw[iy]+n+s?|tween+|twain|twine|twinny)\b[\s,.!?]*/
    guard let match = text.firstMatch(of: phrase) else { return nil }
    return String(text[match.range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Drops a leading "twin", so the question reads the way you meant it.
nonisolated func withoutWakePhrase(_ text: String) -> String {
    guard let command = commandAfterWakePhrase(in: text), text.count - command.count <= 20 else { return text }
    return command
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
