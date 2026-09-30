import XCTest

/// Exercises personal mode through a real RevenueCat Test Store entitlement, never a Pro override.
/// Opt in only on a clean Simulator using the repository's Test Store configuration.
final class PersonalProUITests: XCTestCase {
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let centre = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        for _ in 0..<12 where !element.isHittable {
            let above = element.exists && element.frame.minY < app.windows.firstMatch.frame.midY
            centre.press(forDuration: 0.05, thenDragTo: centre.withOffset(CGVector(dx: 0, dy: above ? 200 : -200)))
        }
    }
    @MainActor private func shot(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
    @MainActor func testPersonalProPlanningAndMentorWithoutHealthHistory() throws {
        guard ProcessInfo.processInfo.environment["MYTWIN_TEST_STORE"] == "1" else {
            throw XCTSkip("Requires opt-in Test Store integration on a clean Simulator.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-userProfile.name", "Jordan", "-userProfile.age", "24", "-geminiDecision", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["You"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts["Demo · fictional data · 2 PM"].exists)
        let planning = app.buttons["planTomorrowEntry"]
        reveal(planning, in: app)
        XCTAssertTrue(planning.isHittable, "Planning is visible in personal mode during the afternoon too")
        shot(app, "personal-planning-entry")
        planning.tap()
        XCTAssertTrue(app.textViews["Goals for tomorrow"].waitForExistence(timeout: 5))
        app.buttons["You"].tap()
        let upgrade = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Get myTwin Pro'")).firstMatch
        let active = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Manage or restore your plan'")).firstMatch
        if !active.waitForExistence(timeout: 5) {
            reveal(upgrade, in: app)
            upgrade.tap()
            let purchase = app.buttons["Start with Pro"]
            XCTAssertTrue(purchase.waitForExistence(timeout: 15))
            reveal(purchase, in: app)
            purchase.tap()
            let testSheet = app.alerts["Test Store Purchase"]
            XCTAssertTrue(testSheet.waitForExistence(timeout: 15), "Never interact with a real-store purchase")
            testSheet.buttons["Test valid purchase"].tap()
            XCTAssertTrue(active.waitForExistence(timeout: 20))
        }
        shot(app, "personal-pro-settings")
        app.buttons["Tomorrow"].tap()
        let planTomorrow = app.buttons["Plan my day tomorrow"]
        reveal(planTomorrow, in: app)
        XCTAssertTrue(planTomorrow.exists)
        XCTAssertTrue(app.staticTexts["Puts each goal into tomorrow's free time, work in your strongest hours, with a reminder before each."].exists)
        XCTAssertFalse(app.buttons["Unlock tomorrow’s prediction"].exists)
        shot(app, "personal-pro-tomorrow")
        app.buttons["Dash"].tap()
        let start = app.buttons["startMentor"]
        reveal(start, in: app)
        XCTAssertTrue(start.isEnabled)
        shot(app, "personal-pro-start-conversation")
        start.tap()
        XCTAssertTrue(app.staticTexts["Use Gemini when you're online?"].waitForExistence(timeout: 5))
        shot(app, "personal-pro-gemini-permission")
        // Don't send the personal account's data in this test; network turns are covered by the demo.
        app.buttons["Don't Allow"].tap()
        XCTAssertTrue(app.buttons["startMentor"].waitForExistence(timeout: 5))
    }
}
