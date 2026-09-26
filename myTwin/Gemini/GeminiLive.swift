import Foundation

/// One live conversation with Gemini over a WebSocket. The app sends what you typed or
/// said; Gemini streams back its spoken answer, the words of that answer, and requests to
/// use the app's tools. Message formats were checked against the live service with a test
/// program on 2026-09-19.
@MainActor
final class GeminiLive {
    enum Event {
        case speech(Data)                   // 24 kHz, 16-bit mono PCM, a piece at a time
        case words(String)                  // the words of that speech, a piece at a time
        case toolCall(id: String?, name: String, arguments: [String: Any])
        case answerComplete                 // every word and sound of the answer has arrived
        case closed
    }

    let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation
    private let socket: URLSessionWebSocketTask

    init(apiKey: String) {
        var request = URLRequest(url: URL(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent")!)
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        socket = URLSession.shared.webSocketTask(with: request)
        (events, continuation) = AsyncStream.makeStream()
    }

    /// Connects and sets up the session. Throws if Gemini doesn't answer within `timeout`.
    func open(instructions: String, tools: [[String: Any]], timeout: Duration = .seconds(6)) async throws {
        socket.resume()
        let watchdog = Task { [socket] in
            try await Task.sleep(for: timeout)
            socket.cancel(with: .goingAway, reason: nil)
        }
        defer { watchdog.cancel() }

        try await send(["setup": [
            "model": "models/\(GeminiAccess.model)",
            "generationConfig": ["responseModalities": ["AUDIO"],
                                 "speechConfig": ["voiceConfig":
                                    ["prebuiltVoiceConfig": ["voiceName": Self.voice]]]],
            "systemInstruction": ["parts": [["text": instructions]]],
            "tools": tools,
            "outputAudioTranscription": [String: Any](),     // the words of each spoken answer
        ]])
        guard try await receive()["setupComplete"] != nil else { throw URLError(.cannotParseResponse) }
        listen()
    }

    /// Which of Gemini's prebuilt voices Dash speaks with. Google documents each voice's
    /// character rather than its gender, so this one was picked by ear: "Puck" is the
    /// upbeat male-sounding voice, which suits him. Swap the name to change it.
    private static let voice = "Puck"

    /// Sends one message from the user. Gemini answers through `events`.
    func ask(_ text: String) async throws {
        try await send(["clientContent": [
            "turns": [["role": "user", "parts": [["text": text]]]],
            "turnComplete": true,
        ]])
    }

    /// Hands back the result of a tool Gemini asked to use.
    func reply(to id: String?, name: String, result: String) async throws {
        var response: [String: Any] = ["name": name, "response": ["result": result]]
        response["id"] = id
        try await send(["toolResponse": ["functionResponses": [response]]])
    }

    func close() {
        socket.cancel(with: .normalClosure, reason: nil)
    }

    /// Reads messages until the connection closes, turning each into events.
    private func listen() {
        Task { [weak self] in
            while let self, let message = try? await self.receive() {
                self.handle(message)
            }
            self?.continuation.yield(.closed)
            self?.continuation.finish()
        }
    }

    private func handle(_ message: [String: Any]) {
        for call in (message["toolCall"] as? [String: Any])?["functionCalls"] as? [[String: Any]] ?? [] {
            continuation.yield(.toolCall(id: call["id"] as? String, name: call["name"] as? String ?? "",
                                         arguments: call["args"] as? [String: Any] ?? [:]))
        }
        guard let content = message["serverContent"] as? [String: Any] else { return }  // also skips "{}" frames

        for part in (content["modelTurn"] as? [String: Any])?["parts"] as? [[String: Any]] ?? [] {
            if let encoded = (part["inlineData"] as? [String: Any])?["data"] as? String,
               let pcm = Data(base64Encoded: encoded) {
                continuation.yield(.speech(pcm))
            }
        }
        if let words = (content["outputTranscription"] as? [String: Any])?["text"] as? String {
            continuation.yield(.words(words))
        }
        // "generationComplete" arrives once everything is sent. "turnComplete" comes seconds
        // later, when Gemini assumes playback has finished, so it isn't used.
        if content["generationComplete"] as? Bool == true {
            continuation.yield(.answerComplete)
        }
    }

    private func send(_ message: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: message)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private func receive() async throws -> [String: Any] {
        let data: Data
        switch try await socket.receive() {
        case .data(let bytes): data = bytes
        case .string(let text): data = Data(text.utf8)
        @unknown default: return [:]
        }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
}
