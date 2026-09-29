import XCTest

final class TomorrowForecastUITests: XCTestCase {
    @MainActor func testTomorrowPreviewAndFreeGate() {
        let app = XCUIApplication()
        app.launchArguments = ["--sample-day"]
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
        let initial = XCTAttachment(screenshot: app.screenshot())
        initial.name = "Tomorrow prediction"
        initial.lifetime = .keepAlways
        add(initial)
        let increase = sleep.buttons["tomorrowSleep-Increment"]
        for _ in 0..<5 { increase.tap() }
        XCTAssertTrue(outlook.label.contains("Still learning"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Tomorrow with insufficient comparable nights"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.terminate()
        app.launchArguments = ["--demo-free"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Demo · fictional data · 2 PM"].waitForExistence(timeout: 30))
        if dismiss.waitForExistence(timeout: 5) { dismiss.tap() }
        app.buttons["Tomorrow"].tap()
        XCTAssertTrue(app.buttons["Unlock tomorrow’s prediction"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.steppers["tomorrowSleep"].exists)
    }
}
