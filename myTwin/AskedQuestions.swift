import Foundation

/// A tally of what you ask most, so the questions you keep typing become one tap.
///
/// It stays on this iPhone, in UserDefaults, and holds only questions you have already
/// asked out loud or in writing. Nothing is sent anywhere by keeping it, and `forget()`
/// empties it.
@MainActor
enum AskedQuestions {
    private static let key = "asked.questions"
    private static let capacity = 50
    /// Below this, the card would be a list of one and not worth the room.
    static let minimumDistinct = 3

    struct Asked: Codable, Identifiable, Hashable {
        let question: String        // as first asked, so it reads the way you say it
        var count: Int
        var last: Date
        var id: String { question.lowercased() }
    }

    static func record(_ question: String) {
        let cleaned = tidy(question)
        guard cleaned.count >= 8, cleaned.count <= 120 else { return }  // not a stray word or a speech
        var all = stored()
        if let index = all.firstIndex(where: { $0.id == cleaned.lowercased() }) {
            all[index].count += 1
            all[index].last = .now
        } else {
            all.append(Asked(question: cleaned, count: 1, last: .now))
        }
        if all.count > capacity {
            all.sort { $0.last > $1.last }
            all = Array(all.prefix(capacity))
        }
        save(all)
    }

    /// The ones worth offering: most asked first, ties going to whichever was asked last.
    static func top(_ limit: Int = 5) -> [Asked] {
        let all = stored().filter { $0.count > 1 }
        guard stored().count >= minimumDistinct else { return [] }
        return Array(all.sorted {
            $0.count != $1.count ? $0.count > $1.count : $0.last > $1.last
        }.prefix(limit))
    }

    static func forget() {
        UserDefaults.standard.removeObject(forKey: key)
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

    private static func stored() -> [Asked] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let all = try? JSONDecoder().decode([Asked].self, from: data)
        else { return [] }
        return all
    }

    private static func save(_ all: [Asked]) {
        guard let data = try? JSONEncoder().encode(all) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
