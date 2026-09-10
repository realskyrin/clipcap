import XCTest
import UserNotifications
@testable import clipcap

final class ReminderSettingsTests: XCTestCase {
    func testSoundRepeatCountCompatibilityAndRoundTrip() throws {
        var settings = ReminderSettings()
        XCTAssertEqual(settings.playbackCount, 1)
        for count in 0...10 {
            settings.soundRepeatCount = count
            let decoded = try JSONDecoder().decode(ReminderSettings.self, from: JSONEncoder().encode(settings))
            XCTAssertEqual(decoded.playbackCount, count)
        }
        settings.soundRepeatCount = 99
        XCTAssertEqual(settings.playbackCount, 10)
    }

    func testSoundDueWindowDoesNotReplayOrIgnoreWeekdaySelection() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let due = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 9)))
        var settings = ReminderSettings()
        settings.enabled = true
        settings.selectedWeekdays = [5]
        XCTAssertTrue(settings.isDue(after: due.addingTimeInterval(-1), through: due, calendar: calendar))
        XCTAssertFalse(settings.isDue(after: due, through: due.addingTimeInterval(1), calendar: calendar))
        settings.selectedWeekdays = [6]
        XCTAssertFalse(settings.isDue(after: due.addingTimeInterval(-1), through: due, calendar: calendar))
        settings.selectedWeekdays = [5]
        settings.enabled = false
        XCTAssertFalse(settings.isDue(after: due.addingTimeInterval(-1), through: due, calendar: calendar))
    }

    func testCustomDaysPresetsAndEmptySchedule() throws {
        var settings = ReminderSettings()
        for (index, days) in ReminderSettings.repeatPresets.enumerated() {
            settings.selectedWeekdays = days
            XCTAssertEqual(settings.repeatPreset, index)
        }
        settings.selectedWeekdays = [4, 5, 7]
        XCTAssertNil(settings.repeatPreset)
        XCTAssertEqual(settings.dates.compactMap(\.weekday), [4, 5, 7])
        XCTAssertEqual(try JSONDecoder().decode(ReminderSettings.self, from: JSONEncoder().encode(settings)), settings)
        settings.selectedWeekdays = []
        XCTAssertNil(settings.repeatPreset)
        XCTAssertTrue(settings.dates.isEmpty)
    }

    func testOldJSONRetainsOriginalDays() throws {
        for weekdaysOnly in [true, false] {
            let json = """
            {"enabled":false,"weekdaysOnly":\(weekdaysOnly),"hour":9,"minute":0,"message":"","sound":"Glass.aiff"}
            """
            let settings = try JSONDecoder().decode(ReminderSettings.self, from: Data(json.utf8))
            XCTAssertEqual(settings.selectedWeekdays, ReminderSettings.repeatPresets[weekdaysOnly ? 1 : 0])
        }
    }

    func testNotificationOwnershipIsIsolatedIncludingLegacyRequests() {
        let first = ReminderEntry(id: "first")
        let second = ReminderEntry(id: "second")
        let legacy = ReminderEntry(id: "legacy")
        XCTAssertTrue(first.owns("clipcap.reminder.first.generation"))
        XCTAssertFalse(second.owns("clipcap.reminder.first.generation"))
        XCTAssertFalse(legacy.owns("clipcap.reminder.first.generation"))
        XCTAssertTrue(legacy.owns("clipcap.reminder.old-uuid"))
        XCTAssertFalse(first.owns("clipcap.reminder.old-uuid"))
        XCTAssertFalse(legacy.owns("another.notification"))
    }

    func testLegacyMigrationAndEmptyCollectionDoesNotResurrectDeletedReminder() throws {
        let suite = "ReminderTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = ReminderSettings()
        settings.enabled = true
        settings.message = "Legacy reminder"
        defaults.set(try JSONEncoder().encode(settings), forKey: "scheduledReminder")
        let migrated = ReminderEntry.load(from: defaults)
        XCTAssertEqual(migrated, [ReminderEntry(id: "legacy", settings: settings)])
        defaults.set(try JSONEncoder().encode([ReminderEntry]()), forKey: "scheduledReminders")
        XCTAssertTrue(ReminderEntry.load(from: defaults).isEmpty)
    }

    func testMultipleRemindersRetainIndependentSettings() throws {
        let suite = "ReminderTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var first = ReminderEntry()
        first.settings.message = "Drink water"
        var second = ReminderEntry()
        second.settings.weekdaysOnly = true
        second.settings.hour = 18
        second.settings.message = "Go home"
        defaults.set(try JSONEncoder().encode([first, second]), forKey: "scheduledReminders")
        XCTAssertEqual(ReminderEntry.load(from: defaults), [first, second])
        XCTAssertNotEqual(first.id, second.id)
    }

    func testDailyTriggerHasNoDateOrWeekdayRestriction() {
        var settings = ReminderSettings()
        settings.hour = 23
        settings.minute = 59
        XCTAssertEqual(settings.dates.count, 1)
        let date = settings.dates[0]
        XCTAssertNil(date.weekday)
        XCTAssertNil(date.day)
        XCTAssertNil(date.timeZone)
        XCTAssertEqual(date.hour, 23)
        XCTAssertEqual(date.minute, 59)
        XCTAssertNotNil(UNCalendarNotificationTrigger(dateMatching: date, repeats: true).nextTriggerDate())
    }

    func testWeekdaysExcludeWeekendAndPreserveTime() {
        var settings = ReminderSettings()
        settings.weekdaysOnly = true
        settings.hour = 8
        settings.minute = 30
        XCTAssertEqual(settings.dates.compactMap(\.weekday), [2, 3, 4, 5, 6])
        for date in settings.dates {
            XCTAssertEqual(date.hour, 8)
            XCTAssertEqual(date.minute, 30)
            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
            XCTAssertTrue(trigger.repeats)
            XCTAssertNotNil(trigger.nextTriggerDate())
        }
    }

    func testSettingsRoundTripRetainsDisabledScheduleAndCustomContent() throws {
        var settings = ReminderSettings()
        settings.message = "喝水 💧"
        settings.sound = "Ping.aiff"
        settings.weekdaysOnly = true
        XCTAssertEqual(try JSONDecoder().decode(ReminderSettings.self, from: JSONEncoder().encode(settings)), settings)
    }
}
