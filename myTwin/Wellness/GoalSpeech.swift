import Foundation
import FoundationModels

/// Turns goals said out loud into lines for the goals box: one goal per line, in the form
/// the goal reader understands ("Finish the lit review, 2 hr, morning").
///
/// Apple's on-device model splits the run-on sentence into goals. Tested on this Mac's
/// model: told to copy the person's words exactly, it kept every detail and invented
/// nothing in 24 runs, though it sometimes left two goals joined by "and", which the
/// splitting below takes care of. Without the model, the splitting alone does the job.
enum GoalSpeech {

    static func lines(from said: String) async -> [String] {
        var pieces = [said]
        if case .available = SystemLanguageModel.default.availability,
           let goals = try? await LanguageModelSession(instructions: Self.instructions)
               .respond(to: said, generating: SpokenGoals.self).content.goals {
            let faithful = goals.filter { copied($0, from: said) }
            if !faithful.isEmpty { pieces = faithful }
        }
        return pieces.flatMap { split(GoalParser.normalize($0)) }.compactMap(line)
    }

    private static let instructions = "Split what someone said out loud into their separate goals for tomorrow. Copy their words exactly. Never add words, times or goals they didn't say."

    /// Most of the line's words appear in what was said: a guard against the model
    /// inventing a goal.
    static func copied(_ line: String, from said: String) -> Bool {
        func words(_ text: String) -> [String] { text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init) }
        let heard = Set(words(said))
        let mine = words(line)
        guard !mine.isEmpty else { return false }
        return Double(mine.filter(heard.contains).count) / Double(mine.count) >= 0.8
    }

    private static let actions = "call|email|text|finish|read|write|study|work|pick|submit|meet|do|clean|cook|buy|run|walk|prepare|review|practice|practise|pay|send|book|visit|plan|start|fix|make|take|get|watch|go|head|drop|grab|reply|apply|meditate|stretch|train|shop|wash|water|feed"
    private static let joins = try! Regex("(?i)(?:[.!?;]+\\s+|,?\\s+and then\\s+|,\\s*then\\s+|\\s+then\\s+(?=(?:\(actions))\\b)|,?\\s+and\\s+(?=(?:\(actions))\\b))")

    /// Sentences, and actions joined by "then" or "and": "call mom at 7pm and go to the gym"
    /// is two goals, "salt and pepper" is not.
    static func split(_ text: String) -> [String] {
        text.split(separator: joins).map(String.init)
    }

    /// One spoken goal as a line for the box, keeping only what was said.
    static func line(_ piece: String) -> String? {
        guard let goal = GoalParser.line(piece) else { return nil }
        let said = piece.lowercased()
        var parts = [goal.title]
        if said.contains(/\d+(?:\.\d+)?\s*(?:h|hr|hrs|hour|hours|m|min|mins|minute|minutes)\b/) {
            parts.append(goal.minutes % 60 == 0 ? "\(goal.minutes / 60) hr"
                         : goal.minutes > 60 ? "\(Double(goal.minutes) / 60) hr" : "\(goal.minutes) min")
        }
        if let hour = goal.hour {
            let half = hour >= 12 ? "pm" : "am"
            let clock = hour % 12 == 0 ? 12 : hour % 12
            parts.append("at \(clock)\(goal.minute.map { $0 > 0 ? String(format: ":%02d", $0) : "" } ?? "")\(half)")
        } else if let window = goal.window {
            parts.append(window.rawValue)
        }
        return parts.joined(separator: ", ")
    }
}

@Generable
nonisolated struct SpokenGoals {
    @Guide(description: "Each separate goal, copied word for word from what the person said, together with the words that say how long it takes or when.")
    var goals: [String]
}
