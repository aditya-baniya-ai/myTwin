import EventKit
import XCTest
@testable import myTwin

final class BedtimeEventTests: XCTestCase {
    /// Settings saved before the bedtime switch existed still load, with it on.
    func testOldSettingsStillLoad() throws {
        let name = "myTwinTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let old = #"{"movement":"walk","minutes":30,"hasEquipment":true,"bedtimeHour":22,"bedtimeMinute":30,"sleepGoal":8,"morningReminder":false,"eventReminders":false,"bedtimeReminder":true,"quietStart":21,"quietEnd":8}"#
        defaults.set(Data(old.utf8), forKey: "planning.preferences.v1")
        let loaded = PlanningPreferences.load(defaults: defaults)
        XCTAssertEqual(loaded.minutes, 30, "old values kept, not reset to defaults")
        XCTAssertTrue(loaded.addsBedtimeEvent)
    }

    /// Added once, moved with your bedtime, removed when turned off.
    @MainActor func testBedtimeEventFollowsTheSetting() async throws {
        let calendar = CalendarManager()
        calendar.loadTodayEvents()
        try XCTSkipUnless(calendar.isAuthorized, "needs calendar access on this simulator")
        let name = "myTwinTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer {
            calendar.syncBedtime(on: false, hour: 0, minute: 0, defaults: defaults)
            defaults.removePersistentDomain(forName: name)
        }
        /// Occurrences of the test's own event: the app it runs in keeps its own Bedtime too.
        func bedtimes(daysAhead: Int) -> Int {
            let store = EKEventStore()
            let day = Calendar.current.date(byAdding: .day, value: daysAhead, to: Calendar.current.startOfDay(for: .now))!
            let range = store.predicateForEvents(withStart: day, end: day.addingTimeInterval(86_400), calendars: nil)
            let mine = defaults.string(forKey: "calendar.bedtime.event")
            return store.events(matching: range).filter { $0.calendarItemIdentifier == mine }.count
        }
        func bedtime() -> EKEvent? {
            defaults.string(forKey: "calendar.bedtime.event")
                .flatMap { EKEventStore().calendarItem(withIdentifier: $0) as? EKEvent }
        }

        calendar.syncBedtime(on: true, hour: 22, minute: 30, defaults: defaults)
        let first = try XCTUnwrap(bedtime())
        XCTAssertEqual(first.title, "Bedtime")
        XCTAssertEqual(Calendar.current.component(.hour, from: first.startDate), 22)
        XCTAssertEqual(bedtimes(daysAhead: 1), 1, "tomorrow has one too")
        XCTAssertEqual(bedtimes(daysAhead: 6), 1, "and next week")

        calendar.syncBedtime(on: true, hour: 23, minute: 15, defaults: defaults)
        let moved = try XCTUnwrap(bedtime())
        XCTAssertEqual(moved.calendarItemIdentifier, first.calendarItemIdentifier, "the same event, moved")
        XCTAssertEqual(Calendar.current.component(.minute, from: moved.startDate), 15)

        calendar.syncBedtime(on: false, hour: 23, minute: 15, defaults: defaults)
        XCTAssertNil(bedtime())
    }
}
