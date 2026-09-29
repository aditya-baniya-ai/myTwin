import XCTest

/// The "up next" Live Activity, seen from outside the app: the Dynamic Island once the app
/// is in the background, and the Lock Screen view in Notification Centre.
final class NextUpLiveActivityUITests: XCTestCase {
    @MainActor func testUpNextShowsOutsideTheApp() {
        let app = XCUIApplication()
        app.launchArguments = ["--sample-day"]
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
