import XCTest
@testable import myTwin

/// What the "You often ask" card offers.
final class AskedQuestionsTests: XCTestCase {
    @MainActor private func store() -> (UserDefaults, () -> Void) {
        let name = "myTwinTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }

    @MainActor func testNeedsTwoRepeatedQuestionsBeforeReplacingTheStarters() async {
        let (defaults, cleanUp) = store(); defer { cleanUp() }
        for _ in 0..<3 { AskedQuestions.record("How did I sleep last night?", defaults: defaults) }
        AskedQuestions.record("What is on my calendar?", defaults: defaults)
        XCTAssertTrue(AskedQuestions.top(defaults: defaults).isEmpty, "one repeated question isn't enough")

        AskedQuestions.record("What is on my calendar?", defaults: defaults)
        XCTAssertEqual(AskedQuestions.top(defaults: defaults).map(\.question),
                       ["How did I sleep last night", "What is on my calendar"], "most asked first")
    }

    @MainActor func testKeepsTheLatestAnswer() async {
        let (defaults, cleanUp) = store(); defer { cleanUp() }
        for question in ["When is my dip today?", "Twin, when is my dip today", "What should I eat?", "What should I eat?"] {
            AskedQuestions.record(question, defaults: defaults)
        }
        AskedQuestions.remember(answer: "Around 3 PM.", for: "When is my dip today?", defaults: defaults)
        AskedQuestions.remember(answer: "Around 4 PM.", for: "when is my dip today", defaults: defaults)
        let dip = AskedQuestions.top(defaults: defaults).first { $0.id == "when is my dip today" }
        XCTAssertEqual(dip?.count, 2, "the wake word doesn't make it a different question")
        XCTAssertEqual(dip?.answer, "Around 4 PM.")
    }

    @MainActor func testOnlyTheLastTwoWeeksCount() async {
        let (defaults, cleanUp) = store(); defer { cleanUp() }
        let old = Date.now.addingTimeInterval(-20 * 86400)
        for question in ["How did I sleep last night?", "What is on my calendar?"] {
            AskedQuestions.record(question, now: old, defaults: defaults)
            AskedQuestions.record(question, now: old, defaults: defaults)
        }
        XCTAssertTrue(AskedQuestions.top(defaults: defaults).isEmpty)
        XCTAssertEqual(AskedQuestions.top(now: old, defaults: defaults).count, 2)
    }
}
