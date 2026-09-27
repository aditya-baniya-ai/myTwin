import XCTest

final class SampleDayTests: XCTestCase {
    @MainActor func testSampleRescuePreviewConfirmUndoAndExplanation() {
        let app = XCUIApplication()
        app.launchArguments = ["--sample-day"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Sample day · fictional data · 2 PM"].waitForExistence(timeout: 30))
        let rescue = app.buttons["Rescue my day"].firstMatch
        for _ in 0..<4 where !rescue.isHittable { app.swipeUp() }
        XCTAssertTrue(rescue.isHittable)
        rescue.tap()
        app.buttons["Preview my rescue"].tap()
        XCTAssertTrue(app.staticTexts["Your proposed change"].waitForExistence(timeout: 5))
        let confirm = app.buttons["Confirm sample change"]
        for _ in 0..<3 where !confirm.isHittable { app.swipeUp() }
        XCTAssertTrue(confirm.exists)
        confirm.tap()
        let undo = app.buttons["Undo change"]
        for _ in 0..<4 where !undo.isHittable { app.swipeUp() }
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Confirmed sample rescue"; screenshot.lifetime = .keepAlways; add(screenshot)
        undo.tap()
        XCTAssertFalse(app.staticTexts["Sample plan updated"].exists)
        let why = app.buttons["Why this plan?"].firstMatch
        for _ in 0..<3 where !why.isHittable { app.swipeDown() }
        why.tap()
        XCTAssertTrue(app.staticTexts["What was measured"].waitForExistence(timeout: 5))
        let okay = app.buttons["Actually, I feel okay"]
        for _ in 0..<4 where !okay.isHittable { app.swipeUp() }
        okay.tap()
        XCTAssertTrue(app.buttons["Rescue my day"].exists)
    }
    @MainActor func testSamplePreferencesAndOutcome() {
        let app = XCUIApplication()
        app.launchArguments = ["--sample-day"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Sample day · fictional data · 2 PM"].waitForExistence(timeout: 30))
        let preferences = app.buttons["Make it yours"].firstMatch
        for _ in 0..<4 where !preferences.isHittable { app.swipeUp() }
        preferences.tap()
        XCTAssertTrue(app.navigationBars["Make it yours"].waitForExistence(timeout: 5))
        let equipment = app.switches["I have strength equipment"]
        XCTAssertTrue(equipment.exists)
        equipment.switches.firstMatch.tap()
        XCTAssertEqual(equipment.value as? String, "1")
        app.buttons["Save"].tap()
        preferences.tap()
        XCTAssertEqual(app.switches["I have strength equipment"].value as? String, "1")
        app.buttons["Cancel"].tap()
        let better = app.buttons["Better"].firstMatch
        for _ in 0..<5 where !better.isHittable { app.swipeUp() }
        XCTAssertTrue(better.isHittable)
        better.tap()
        XCTAssertTrue(app.staticTexts["You reported feeling better."].exists)
        XCTAssertFalse(app.buttons["Share my moment"].exists, "sharing was removed")
    }

}
