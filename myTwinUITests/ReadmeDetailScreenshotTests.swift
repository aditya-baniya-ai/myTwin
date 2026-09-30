import XCTest

final class ReadmeDetailScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["MYTWIN_README_SHOTS"] == "1" else {
            throw XCTSkip("Opt-in README screenshot capture.")
        }
    }
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
        app.launchArguments += ["-geminiDecision", "NO"]
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
        let previewShot = XCTAttachment(screenshot: app.screenshot())
        previewShot.name = "rescue-preview"; previewShot.lifetime = .keepAlways; add(previewShot)
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
        let whyShot = XCTAttachment(screenshot: app.screenshot())
        whyShot.name = "why-this-plan"; whyShot.lifetime = .keepAlways; add(whyShot)
        okay.tap()
        XCTAssertTrue(app.buttons["Rescue my day"].exists)
    }
    @MainActor func testSamplePreferencesAndOutcome() {
        let app = XCUIApplication()
        app.launchArguments = ["--sample-day"]
        app.launchArguments += ["-geminiDecision", "NO"]
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

import XCTest

final class ReadmeForecastScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["MYTWIN_README_SHOTS"] == "1" else {
            throw XCTSkip("Opt-in README screenshot capture.")
        }
    }
    @MainActor func testTomorrowPreviewAndFreeGate() {
        let app = XCUIApplication()
        app.launchArguments = ["--sample-day"]
        app.launchArguments += ["-geminiDecision", "NO"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Demo · fictional data · 2 PM"].waitForExistence(timeout: 30))
        let dismiss = app.buttons["Not now"]
        if dismiss.waitForExistence(timeout: 5) { dismiss.tap() }
        app.buttons["Tomorrow"].tap()
        let outlook = app.staticTexts["tomorrowOutlook"]
        XCTAssertTrue(outlook.waitForExistence(timeout: 5))
        XCTAssertFalse(outlook.label.contains("Still learning"))
        let sleep = app.steppers["tomorrowSleep"]
        XCTAssertTrue(sleep.exists)
        for _ in 0..<6 where !sleep.isHittable { app.swipeUp(velocity: .slow) }   // below the goals
        let initial = XCTAttachment(screenshot: app.screenshot())
        initial.name = "Tomorrow prediction"
        initial.lifetime = .keepAlways
        add(initial)
        // Less sleep than usual: the outlook follows the number you set.
        let before = outlook.label
        let decrease = sleep.buttons["tomorrowSleep-Decrement"]
        for _ in 0..<6 { decrease.tap() }
        XCTAssertNotEqual(outlook.label, before, "the outlook responds to expected sleep")
        XCTAssertTrue(outlook.label.contains("below"), outlook.label)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Tomorrow after a short night"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.terminate()
        app.launchArguments = ["--demo-free"]
        app.launchArguments += ["-geminiDecision", "NO"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Demo · fictional data · 2 PM"].waitForExistence(timeout: 30))
        if dismiss.waitForExistence(timeout: 5) { dismiss.tap() }
        app.buttons["Tomorrow"].tap()
        let unlock = app.buttons["Unlock tomorrow’s prediction"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 5))
        XCTAssertFalse(app.steppers["tomorrowSleep"].exists)
        for _ in 0..<6 where !unlock.isHittable { app.swipeUp(velocity: .slow) }
        unlock.tap()
        XCTAssertTrue(app.staticTexts["Part of myTwin Pro"].waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(app.staticTexts.matching(identifier: "Tomorrow’s prediction").count, 1,
                                    "the paywall names the forecast, not goal planning")
        XCTAssertFalse(app.staticTexts["Planning your goals into your calendar"].exists)
    }
}

import XCTest

/// The "up next" Live Activity, seen from outside the app: the Dynamic Island once the app
/// is in the background, and the Lock Screen view in Notification Centre.
final class ReadmeLiveActivityScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["MYTWIN_README_SHOTS"] == "1" else {
            throw XCTSkip("Opt-in README screenshot capture.")
        }
    }
    @MainActor func testUpNextShowsOutsideTheApp() {
        let app = XCUIApplication()
        app.launchArguments = ["--sample-day"]
        app.launchArguments += ["-geminiDecision", "NO"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Demo · fictional data · 2 PM"].waitForExistence(timeout: 30))
        sleep(2)

        XCUIDevice.shared.press(.home)
        sleep(2)
        let island = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        island.name = "Dynamic Island"; island.lifetime = .keepAlways; add(island)

        // Pull Notification Centre down from the top left, where Live Activities show.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.005))
            .press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.7)))
        sleep(2)
        let lock = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        lock.name = "Lock Screen"; lock.lifetime = .keepAlways; add(lock)
        XCTAssertTrue(springboard.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Dash thinks'")).firstMatch
            .waitForExistence(timeout: 5), "the Live Activity is showing")
    }
}
