import Foundation

/// A tally of what you ask most, so the questions you keep typing become one tap.
///
/// It stays on this iPhone, in UserDefaults, and holds only questions you have already
/// asked out loud or in writing, with the last answer to each. Nothing is sent anywhere
/// by keeping it, and `forget()` empties it.
@MainActor
enum AskedQuestions {
    private static let key = "asked.questions"
    private static let capacity = 50
    /// Below this many repeated questions, the card offers `starters` instead.
    static let minimumRepeated = 2
    /// Only what you still ask counts, so the card follows your last two weeks.
    static let window: TimeInterval = 14 * 86400
    /// For someone who hasn't asked anything twice yet.
    static let starters = ["How did I sleep last night?",
                           "When will my energy dip today?",
                           "What should I do this afternoon?"]

    struct Asked: Codable, Identifiable, Hashable {
        let question: String        // as first asked, so it reads the way you say it
        var count: Int
        var last: Date
        var answer: String?         // the latest one, shown to Pro subscribers
        var id: String { question.lowercased() }
    }

    static func record(_ question: String, now: Date = .now, defaults: UserDefaults = .standard) {
        let cleaned = tidy(question)
        guard cleaned.count >= 8, cleaned.count <= 120 else { return }  // not a stray word or a speech
        var all = stored(defaults)
        if let index = all.firstIndex(where: { $0.id == cleaned.lowercased() }) {
            all[index].count += 1
            all[index].last = now
        } else {
            all.append(Asked(question: cleaned, count: 1, last: now))
        }
        if all.count > capacity {
            all.sort { $0.last > $1.last }
            all = Array(all.prefix(capacity))
        }
        save(all, defaults)
    }

    /// Keeps the latest answer to a question already recorded.
    static func remember(answer: String, for question: String, defaults: UserDefaults = .standard) {
        var all = stored(defaults)
        guard let index = all.firstIndex(where: { $0.id == tidy(question).lowercased() }) else { return }
        all[index].answer = answer
        save(all, defaults)
    }

    /// The ones worth offering: asked more than once within the window, most asked first,
    /// ties going to whichever was asked last. Empty until there are `minimumRepeated`.
    static func top(_ limit: Int = 5, now: Date = .now, defaults: UserDefaults = .standard) -> [Asked] {
        let repeated = stored(defaults).filter { $0.count > 1 && now.timeIntervalSince($0.last) < window }
        guard repeated.count >= minimumRepeated else { return [] }
        return Array(repeated.sorted {
            $0.count != $1.count ? $0.count > $1.count : $0.last > $1.last
        }.prefix(limit))
    }

    static func forget(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    // MARK: - Pieces

    /// Drops his name and the punctuation, so "Twin, how did I sleep?" and "how did I
    /// sleep" are the same question asked twice rather than two questions asked once.
    private static func tidy(_ question: String) -> String {
        let withoutName = withoutWakePhrase(question)
        return withoutName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?"))
    }

    private static func stored(_ defaults: UserDefaults) -> [Asked] {
        guard let data = defaults.data(forKey: key),
              let all = try? JSONDecoder().decode([Asked].self, from: data)
        else { return [] }
        return all
    }

    private static func save(_ all: [Asked], _ defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: key)
    }
}
