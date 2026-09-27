import XCTest
@testable import myTwin

final class DailySupportTests: XCTestCase {
    @MainActor func testRescueRequiresProExceptFictionalSample() async {
        let name = "myTwinTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let personal = DailySupport(defaults: defaults)
        XCTAssertFalse(personal.canRescue(proEnabled: false), "No first free rescue")
        XCTAssertTrue(personal.canRescue(proEnabled: true))
        personal.save(PlannedAction(movement: .walk, title: "Walk", start: .now,
                                   end: .now.addingTimeInterval(600), isRescue: true))
        XCTAssertFalse(personal.canRescue(proEnabled: false), "Previous use cannot bypass expired Pro")
        XCTAssertTrue(DailySupport(isSample: true, defaults: defaults).canRescue(proEnabled: false))
    }
    @MainActor func testSampleCannotWritePersonalPreferencesOrHistory() async {
        let name = "myTwinTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let personal = DailySupport(defaults: defaults)
        personal.report(.good)
        var prefs = PlanningPreferences(); prefs.minutes = 45; prefs.movement = .pilates
        personal.savePreferences(prefs)
        let before = defaults.dictionaryRepresentation() as NSDictionary
        let sample = DailySupport(isSample: true, defaults: defaults)
        sample.report(.low)
        sample.savePreferences(PlanningPreferences())
        sample.finish(sample.actions[1], outcome: .better)
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
        let restored = DailySupport(defaults: defaults)
        XCTAssertEqual(restored.currentCheckIn, .good)
        XCTAssertEqual(restored.preferences.minutes, 45)
        XCTAssertTrue(restored.actions.isEmpty)
    }
    @MainActor func testRescuePersistenceAndUndoRestoresOriginal() async {
        let name = "myTwinTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let daily = DailySupport(defaults: defaults)
        let original = PlannedAction(movement: .strength, title: "Strength", start: .now, end: .now.addingTimeInterval(3600))
        daily.save(original)
        var replacement = original; replacement.id = UUID(); replacement.isRescue = true; replacement.title = "Stretch"
        daily.save(replacement, replacing: original)
        let restored = DailySupport(defaults: defaults)
        XCTAssertEqual(restored.actions, [replacement])
        restored.undo(replacement, restoring: original)
        XCTAssertEqual(restored.actions, [original])
        XCTAssertEqual(DailySupport(defaults: defaults).actions, [original])
    }
    @MainActor func testRepeatedOutcomeEvidenceAndSkip() async {
        let daily = DailySupport(isSample: true)
        for index in 0..<3 {
            let walk = PlannedAction(movement: .walk, title: "Walk \(index)", start: .now, end: .now.addingTimeInterval(600))
            let stretch = PlannedAction(movement: .stretch, title: "Stretch \(index)", start: .now, end: .now.addingTimeInterval(600))
            daily.save(walk); daily.finish(walk, outcome: .worse)
            daily.save(stretch); daily.finish(stretch, outcome: .better)
        }
        XCTAssertEqual(daily.suggestedMovement, .stretch)
        XCTAssertTrue(daily.evidence(for: .stretch)?.contains("3 of 3") == true)
        let action = daily.actions.last!
        daily.finish(action, outcome: nil, skipped: true)
        XCTAssertNil(daily.evidence(for: .stretch))
        XCTAssertEqual(daily.suggestedMovement, .walk)
    }
}
