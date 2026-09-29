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

    /// In Week, tap a day to see all of it laid out like today, then go back.
    @MainActor func testWeekDayOpensInFull() {
        let app = XCUIApplication()
        app.launchArguments = ["--sample-day"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Demo · fictional data · 2 PM"].waitForExistence(timeout: 30))
        dismissNudge(app)
        open("Plan", in: app)
        app.buttons["Week"].firstMatch.tap()

        let day = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Dinner with Sam'")).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        day.tap()
        XCTAssertTrue(app.staticTexts["Dinner with Sam"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Team standup"].exists)
        XCTAssertTrue(app.staticTexts["Mom's birthday"].exists, "all-day events too")
        XCTAssertFalse(app.staticTexts["SUGGESTED"].exists, "no suggestions on other days")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Week day in full"; shot.lifetime = .keepAlways; add(shot)

        app.buttons["Week"].firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Farmers market'")).firstMatch
            .waitForExistence(timeout: 5), "back to the week")
    }

    /// Add a goal to today after the day has begun, and tick it off.
    @MainActor func testAddAGoalForToday() {
        let app = XCUIApplication()
        app.launchArguments = ["--sample-day"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Demo · fictional data · 2 PM"].waitForExistence(timeout: 30))
        dismissNudge(app)
        open("Tomorrow", in: app)

        let field = app.textFields["Add a goal for today"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Call the bank, 15 min\n")
        let goal = app.buttons["Call the bank"]
        XCTAssertTrue(goal.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Say today's goals"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Add a length'")).firstMatch.exists,
                       "the hint line is gone")

        // Tap its name to edit it: give it a time, 4 PM.
        goal.tap()                                         // return already put the keyboard away
        let timed = app.switches["Time"]
        XCTAssertTrue(timed.waitForExistence(timeout: 5))
        timed.switches.firstMatch.tap()
        let wheels = app.pickerWheels
        XCTAssertTrue(wheels.element(boundBy: 0).waitForExistence(timeout: 5))
        wheels.element(boundBy: 0).adjust(toPickerWheelValue: "4")
        wheels.element(boundBy: 1).adjust(toPickerWheelValue: "00")
        wheels.element(boundBy: 2).adjust(toPickerWheelValue: "PM")
        let editor = XCTAttachment(screenshot: app.screenshot())
        editor.name = "Editing a goal"; editor.lifetime = .keepAlways; add(editor)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH '4:00'")).firstMatch.waitForExistence(timeout: 5),
                      "its time shows on the row")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Goal added for today"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Tick off Call the bank"].tap()

        // With Pro, the rest go into today's calendar, after 2 PM, with times you can change.
        let plan = app.buttons["Plan the rest of today"]
        for _ in 0..<4 where !plan.isHittable { app.swipeUp(velocity: .slow) }
        plan.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Planned' AND label CONTAINS 'into today'"))
            .firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH '7:00'")).firstMatch.exists, "Call mom at 7pm")
        let planned = XCTAttachment(screenshot: app.screenshot())
        planned.name = "Today planned"; planned.lifetime = .keepAlways; add(planned)
    }

    /// Write a goal for tomorrow and let Pro plan it into the (demo) calendar.
    @MainActor func testTomorrowGoalsArePlanned() {
        let app = XCUIApplication()
        app.launchArguments = ["--sample-day"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Demo · fictional data · 2 PM"].waitForExistence(timeout: 30))
        dismissNudge(app)
        open("Tomorrow", in: app)
        XCTAssertTrue(app.staticTexts["Did you finish today's goals?"].waitForExistence(timeout: 5))

        let box = app.textViews["Goals for tomorrow"]
        XCTAssertTrue(box.waitForExistence(timeout: 5))
        box.tap()
        box.typeText("Write the report, 2 hrs, morning\nCall mom at 8pm")
        app.buttons["Done"].firstMatch.tap()

        let plan = app.buttons["Plan my day tomorrow"]
        for _ in 0..<4 where !plan.isHittable { app.swipeUp(velocity: .slow) }
        plan.tap()
        XCTAssertTrue(app.staticTexts["Planned 2 goals into tomorrow, with reminders."].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Tomorrow planned"; screenshot.lifetime = .keepAlways; add(screenshot)

        // Tap a planned time to change it: Call mom, 8 PM to 9 PM.
        let time = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '8:00'")).firstMatch
        XCTAssertTrue(time.waitForExistence(timeout: 5))
        time.tap()
        let hour = app.pickerWheels.element(boundBy: 0)
        XCTAssertTrue(hour.waitForExistence(timeout: 5))
        hour.adjust(toPickerWheelValue: "9")
        let moved = XCTAttachment(screenshot: app.screenshot())
        moved.name = "Changing the time"; moved.lifetime = .keepAlways; add(moved)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Moved Call mom to 9:00'")).firstMatch
            .waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH '9:00'")).firstMatch.exists)
        let after = XCTAttachment(screenshot: app.screenshot())
        after.name = "Time changed"; after.lifetime = .keepAlways; add(after)

        // Planning again keeps the time you chose.
        plan.tap()
        XCTAssertTrue(app.staticTexts["Kept your 2 times. Nothing new to plan."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH '9:00'")).firstMatch.exists)
    }
}
