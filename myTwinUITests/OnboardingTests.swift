import XCTest

/// The first screen, both ways in: the guest demo with and without Pro, and setting up
/// your own account.
final class OnboardingTests: XCTestCase {
    /// Launch as if myTwin had never been set up. Launch arguments override UserDefaults
    /// for this run only, so the profile saved on the simulator is left alone.
    @MainActor private func freshApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-userProfile.name", "", "-userProfile.age", "0"]
        app.launch()
        return app
    }

    @MainActor private func dismissNudge(_ app: XCUIApplication) {
        let notNow = app.buttons["Not now"]
        if notNow.waitForExistence(timeout: 8) { notNow.tap() }
    }

    @MainActor private func open(_ tab: String, in app: XCUIApplication) {
        app.buttons[tab].firstMatch.tap()
    }

    /// Every page has its own demo banner, so tap the one on screen.
    @MainActor private func onScreen(_ label: String, in app: XCUIApplication) -> XCUIElement {
        let matches = app.buttons.matching(identifier: label)
        let deadline = Date.now.addingTimeInterval(5)
        while Date.now < deadline {
            if let visible = matches.allElementsBoundByIndex.first(where: \.isHittable) { return visible }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return matches.firstMatch
    }

    @MainActor func testGuestWithoutProThenSwitchToPro() {
        let app = freshApp()
        XCTAssertTrue(app.buttons["Continue as a user"].waitForExistence(timeout: 20))
        app.buttons["Continue as a guest"].tap()
        XCTAssertTrue(app.buttons["Continue with Pro"].waitForExistence(timeout: 5))
        app.buttons["Continue without Pro"].tap()

        XCTAssertTrue(app.staticTexts["Demo · fictional data · 2 PM"].waitForExistence(timeout: 30))
        dismissNudge(app)

        // Free: the forecast is locked and there's no rescue.
        open("Predictions", in: app)
        XCTAssertTrue(app.staticTexts["Your energy, hour by hour"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["You often ask"].exists)
        open("Plan", in: app)
        XCTAssertTrue(app.buttons["Week"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Rescue my day"].exists)

        // Flip the demo to Pro: rescue appears, and so do the suggestions.
        onScreen("Pro", in: app).tap()
        XCTAssertTrue(app.buttons["Rescue my day"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["SUGGESTED"].firstMatch.waitForExistence(timeout: 5))

        // The demo calendar has a whole week.
        app.buttons["Week"].tap()
        XCTAssertTrue(app.staticTexts["Dentist"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Mom's birthday"].exists)

        // And activity, as a real user would have.
        open("Activity", in: app)
        XCTAssertTrue(app.staticTexts["6,420"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Demo activity"; screenshot.lifetime = .keepAlways; add(screenshot)

        // Out of the demo, into setting up an account.
        onScreen("Use my account", in: app).tap()
        XCTAssertTrue(app.staticTexts["Let's get to know you"].waitForExistence(timeout: 5))
    }

    @MainActor func testGuestWithProUnlocksEverything() {
        let app = freshApp()
        XCTAssertTrue(app.buttons["Continue as a guest"].waitForExistence(timeout: 20))
        app.buttons["Continue as a guest"].tap()
        app.buttons["Continue with Pro"].tap()
        XCTAssertTrue(app.staticTexts["Demo · fictional data · 2 PM"].waitForExistence(timeout: 30))
        dismissNudge(app)
        open("Predictions", in: app)
        XCTAssertTrue(app.staticTexts["Peak focus"].waitForExistence(timeout: 5), "the forecast is unlocked")
        XCTAssertFalse(app.staticTexts["Your energy, hour by hour"].exists)
        XCTAssertTrue(app.buttons["Ask myTwin"].exists, "chat is available in the demo")
    }

    @MainActor func testUserSetUpNameAgeAndConnect() {
        let app = freshApp()
        XCTAssertTrue(app.buttons["Continue as a user"].waitForExistence(timeout: 20))
        app.buttons["Continue as a user"].tap()

        let name = app.textFields["What should we call you?"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Jordan")
        let age = app.textFields["Age"]
        age.tap()
        age.typeText("24")
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.staticTexts["Connect your data"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Connect Apple Health"].exists || app.images["Apple Health connected"].exists)
        XCTAssertTrue(app.buttons["Connect Calendar"].exists || app.images["Calendar connected"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Connect your data"; screenshot.lifetime = .keepAlways; add(screenshot)

        let next = app.buttons["Continue anyway"].exists ? app.buttons["Continue anyway"] : app.buttons["Continue"]
        next.tap()
        XCTAssertTrue(app.buttons["You"].firstMatch.waitForExistence(timeout: 15), "home screen after setup")
        XCTAssertFalse(app.staticTexts["Demo · fictional data · 2 PM"].exists)
    }
}
