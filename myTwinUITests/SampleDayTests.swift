import XCTest

final class SampleDayTests: XCTestCase {
    /// Dash's nudge slides in a few seconds after launch and can cover whatever a test is
    /// scrolling to, so close it first.
    @MainActor private func dismissNudge(_ app: XCUIApplication) {
        let notNow = app.buttons["Not now"]
        if notNow.waitForExistence(timeout: 8) { notNow.tap() }
    }
    /// Scrolls a short, fixed distance towards `element` until it can be tapped. A swipe
    /// flings too far and can carry a small card right past the screen.
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch
        let middle = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        for _ in 0..<12 where !element.isHittable {
            let above = element.exists && element.frame.minY < window.frame.midY
            middle.press(forDuration: 0.05, thenDragTo: middle.withOffset(CGVector(dx: 0, dy: above ? 220 : -220)))
        }
    }
    @MainActor func testSampleRescuePreviewConfirmUndoAndExplanation() {
        let app = XCUIApplication()
        app.launchArguments = ["--sample-day"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Demo · fictional data · 2 PM"].waitForExistence(timeout: 30))
        dismissNudge(app)
        let rescue = app.buttons["Rescue my day"].firstMatch
        // Slowly: a fast fling scrolls it from just below the screen to just above it.
        for _ in 0..<4 where !rescue.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(rescue.isHittable)
        rescue.tap()
        // The sheet picks your suggested activity as it opens, which clears a preview made
        // in the same instant; a person never taps that fast, a test can.
        let preview = app.buttons["Preview my rescue"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        preview.tap()
        if !app.staticTexts["Your proposed change"].waitForExistence(timeout: 3) { preview.tap() }
        XCTAssertTrue(app.staticTexts["Your proposed change"].waitForExistence(timeout: 5))
        let confirm = app.buttons["Confirm demo change"]
        for _ in 0..<3 where !confirm.isHittable { app.swipeUp() }
        XCTAssertTrue(confirm.exists)
        confirm.tap()
        let undo = app.buttons["Undo change"]
        for _ in 0..<4 where !undo.isHittable { app.swipeUp() }
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Confirmed sample rescue"; screenshot.lifetime = .keepAlways; add(screenshot)
        undo.tap()
        XCTAssertFalse(app.staticTexts["Demo plan updated"].exists)
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
        XCTAssertTrue(app.staticTexts["Demo · fictional data · 2 PM"].waitForExistence(timeout: 30))
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
        reveal(better, in: app)
        XCTAssertTrue(better.isHittable)
        better.tap()
        // Answered: the question goes, and the next event takes its place with a tip.
        XCTAssertTrue(app.staticTexts["Up next"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Did that help?"].exists)
        XCTAssertFalse(app.buttons["Share my moment"].exists, "sharing was removed")
    }

}
