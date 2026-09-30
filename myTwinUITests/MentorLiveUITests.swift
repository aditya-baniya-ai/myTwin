import XCTest

/// Opt-in network integration: only fictional demo data goes to Gemini.
final class MentorLiveUITests: XCTestCase {
    @MainActor func testProMentorTypedFollowUpAndEnd() throws {
        guard ProcessInfo.processInfo.environment["MYTWIN_LIVE_TESTS"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_MYTWIN_LIVE_TESTS=1 to exercise Gemini with demo data.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--sample-day", "-geminiDecision", "YES"]
        app.launch()
        let end = app.buttons["End"]
        XCTAssertTrue(end.waitForExistence(timeout: 40))
        let field = app.textFields["Type your answer"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: field)
        waitForExpectations(timeout: 60)
        XCTAssertTrue(app.buttons["Talk to Dash"].exists)
        field.tap()
        field.typeText("The literature review matters most.")
        app.buttons["mentor.send"].tap()
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: field)
        waitForExpectations(timeout: 60)
        XCTAssertFalse(app.staticTexts["Gemini is unavailable right now. Check your connection and try again, or tap End."].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Pro mentor after typed reply"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        end.tap()
        XCTAssertFalse(end.exists)
    }

    @MainActor func testFreeDemoKeepsOneLineCard() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--demo-free", "-geminiDecision", "YES"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Demo · fictional data · 2 PM"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["Not now"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["End"].exists)
        XCTAssertFalse(app.textFields["Type your answer"].exists)
    }
}
