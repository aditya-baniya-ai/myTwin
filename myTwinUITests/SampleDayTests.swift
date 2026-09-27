import XCTest

final class SampleDayTests: XCTestCase {
    /// Dash's nudge slides in a few seconds after launch and can cover whatever a test is
    /// scrolling to, so close it first.
    @MainActor private func dismissNudge(_ app: XCUIApplication) {
        let notNow = app.buttons["Not now"]
        if notNow.waitForExistence(timeout: 8) { notNow.tap() }
    }
    @MainActor func testSampleRescuePreviewConfirmUndoAndExplanation() {
        let app = XCUIApplication()
        app.launchArguments = ["--sample-day"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Sample day · fictional data · 2 PM"].waitForExistence(timeout: 30))
        dismissNudge(app)
        let rescue = app.buttons["Rescue my day"].firstMatch
        // Slowly: a fast fling scrolls it from just below the screen to just above it.
        for _ in 0..<4 where !rescue.isHittable { app.swipeUp(velocity: .slow) }
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
        dismissNudge(app)
        let preferences = app.buttons["Make it yours"].firstMatch
        for _ in 0..<4 where !preferences.isHittable { app.swipeUp() }
        preferences.tap()
        XCTAssertTrue(app.navigationBars["Make it yours"].waitForExistence(timeout: 5))
        let equipment = app.switches["I have strength equipment"]
        XCTAssertTrue(equipment.exists)
        // The title appears while the sheet is still sliding up; wait until the switch takes
        // touches, and press rather than tap, since an instant tap can miss a switch.
        let toggle = equipment.switches.firstMatch
        expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: toggle)
        waitForExpectations(timeout: 5)
        toggle.press(forDuration: 0.2)
        expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: equipment)
        waitForExpectations(timeout: 3)
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
