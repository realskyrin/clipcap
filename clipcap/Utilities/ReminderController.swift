import AppKit
import UserNotifications

struct ReminderSettings: Codable, Equatable {
    var enabled = false
    var weekdaysOnly = false
    // Missing in older saved reminders, which retain their original repeat mode
    var weekdays: Set<Int>?
    static let repeatPresets: [Set<Int>] = [Set(1...7), Set(2...6), [1, 7]]
    var selectedWeekdays: Set<Int> {
        get { weekdays ?? Self.repeatPresets[weekdaysOnly ? 1 : 0] }
        set { weekdays = newValue.intersection(1...7) }
    }
    var repeatPreset: Int? { Self.repeatPresets.firstIndex(of: selectedWeekdays) }
    var hour = 9
    var minute = 0
    var message = ""
    var sound = "Glass.aiff"
    var soundRepeatCount: Int?
    var playbackCount: Int { min(10, max(0, soundRepeatCount ?? 1)) }

    func isDue(after start: Date, through end: Date, calendar: Calendar = .current) -> Bool {
        enabled && dates.contains { components in
            guard let next = calendar.nextDate(after: start, matching: components, matchingPolicy: .nextTime) else { return false }
            return next <= end
        }
    }

    var dates: [DateComponents] {
        (selectedWeekdays == Self.repeatPresets[0] ? [nil] : selectedWeekdays.sorted().map { Optional($0) }).map { weekday in
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            components.weekday = weekday
            return components
        }
    }
}

struct ReminderEntry: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var settings: ReminderSettings = ReminderSettings()

    func owns(_ identifier: String) -> Bool {
        let prefix = "clipcap.reminder."
        guard identifier.hasPrefix(prefix) else { return false }
        let suffix = identifier.dropFirst(prefix.count)
        return id == "legacy" ? !suffix.contains(".") : suffix.hasPrefix(id + ".")
    }

    static func load(from defaults: UserDefaults) -> [ReminderEntry] {
        if let data = defaults.data(forKey: "scheduledReminders"),
           let entries = try? JSONDecoder().decode([ReminderEntry].self, from: data) { return entries }
        if let data = defaults.data(forKey: "scheduledReminder"),
           let settings = try? JSONDecoder().decode(ReminderSettings.self, from: data) {
            return [ReminderEntry(id: "legacy", settings: settings)]
        }
        return []
    }
}

final class ReminderController: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderController()
    private let center = UNUserNotificationCenter.current()
    private let prefix = "clipcap.reminder."
    private var soundTimer: Timer?
    private var lastSoundCheck = Date()
    private var stoppedThrough: [String: Date] = [:]
    private var ringing: [String: ReminderSoundPlayer] = [:]
    var entries: [ReminderEntry] { ReminderEntry.load(from: .standard) }

    private func persist(_ entries: [ReminderEntry]) throws {
        UserDefaults.standard.set(try JSONEncoder().encode(entries), forKey: "scheduledReminders")
        UserDefaults.standard.removeObject(forKey: "scheduledReminder")
    }

    @MainActor func delete(_ entry: ReminderEntry) async throws {
        let pending = await center.pendingNotificationRequests().filter { entry.owns($0.identifier) }
        try persist(entries.filter { $0.id != entry.id })
        ringing.removeValue(forKey: entry.id)?.stop()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier))
        let delivered = await center.deliveredNotifications().filter { entry.owns($0.request.identifier) }
        center.removeDeliveredNotifications(withIdentifiers: delivered.map { $0.request.identifier })
    }

    static var sounds: [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "/System/Library/Sounds"), includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "aiff" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    @MainActor func start() {
        center.delegate = self
        guard soundTimer == nil else { return }
        lastSoundCheck = Date()
        soundTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkSounds() }
        }
    }

    @MainActor private func checkSounds() {
        let now = Date()
        // Do not replay missed alarms after a long sleep or clock adjustment
        let start = max(lastSoundCheck, now.addingTimeInterval(-60))
        lastSoundCheck = now
        for entry in entries where entry.settings.playbackCount != 1 && !entry.settings.sound.isEmpty {
            guard entry.settings.isDue(after: max(start, stoppedThrough[entry.id] ?? start), through: now) else { continue }
            ringing.removeValue(forKey: entry.id)?.stop()
            let player = ReminderSoundPlayer()
            ringing[entry.id] = player
            player.play(filename: entry.settings.sound, count: entry.settings.playbackCount, message: entry.settings.message)
        }
        ringing = ringing.filter { $0.value.isPlaying }
    }

    @MainActor func save(_ entry: ReminderEntry) async throws {
        let value = entry.settings
        if value.enabled {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                throw ReminderError.permission
            }
        }
        // Stage a complete new generation before removing the previous schedule
        let old = await center.pendingNotificationRequests().filter { entry.owns($0.identifier) }
        var added: [String] = []
        do {
            if value.enabled {
                let content = UNMutableNotificationContent()
                content.title = Localizer.string("reminderTitle")
                content.body = value.message
                if !value.sound.isEmpty && value.playbackCount == 1 {
                    guard let source = Self.sounds.first(where: { $0.lastPathComponent == value.sound }) else { throw ReminderError.sound }
                    let folder = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Sounds")
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let name = "clipcap-reminder-" + source.lastPathComponent
                    let target = folder.appendingPathComponent(name)
                    if !FileManager.default.fileExists(atPath: target.path) { try FileManager.default.copyItem(at: source, to: target) }
                    content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: name))
                }
                for date in value.dates {
                    let id = prefix + (entry.id == "legacy" ? "" : entry.id + ".") + UUID().uuidString
                    try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: true)))
                    added.append(id)
                }
            }
            var updated = entries
            if let index = updated.firstIndex(where: { $0.id == entry.id }) { updated[index] = entry }
            else { updated.append(entry) }
            try persist(updated)
            ringing.removeValue(forKey: entry.id)?.stop()
            center.removePendingNotificationRequests(withIdentifiers: old.map(\.identifier))
        } catch {
            center.removePendingNotificationRequests(withIdentifiers: added)
            throw error
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            for entry in entries where entry.owns(response.notification.request.identifier) {
                stoppedThrough[entry.id] = Date()
                ringing.removeValue(forKey: entry.id)?.stop()
            }
            completionHandler()
        }
    }

    enum ReminderError: LocalizedError {
        case permission, sound
        var errorDescription: String? { Localizer.string(self == .permission ? "reminderPermission" : "reminderSoundError") }
    }
}
