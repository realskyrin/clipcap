import AppKit
import AVFoundation
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum SystemScreenshotAutoOpen {
    static var directoryURL: URL {
        if let selected = Defaults.systemScreenshotDirectory { return selected }
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures", isDirectory: true)
        return pictures.appendingPathComponent("ClipCap Screenshots", isDirectory: true)
    }

    @discardableResult
    static func ensureDirectoryExists() -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            return true
        } catch {
            NSLog("clipcap: failed to create system screenshot directory: \(error)")
            return false
        }
    }

    static func revealDirectory() {
        guard ensureDirectoryExists() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([directoryURL])
    }

    static func openScreenshotTool() {
        let workspace = NSWorkspace.shared
        let fallbackURL = URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app")
        guard let appURL = workspace.urlForApplication(withBundleIdentifier: "com.apple.screenshot.launcher")
                ?? (FileManager.default.fileExists(atPath: fallbackURL.path) ? fallbackURL : nil)
        else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.openApplication(at: appURL, configuration: configuration)
    }

    /// The screenshot preference key is not a public product API, so ClipCap
    /// changes it only after explicit user confirmation. Restarting these
    /// user-owned system processes makes the new value visible immediately.
    static func refreshSystemScreenshotServices() {
        for app in NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.screenshot.launcher"
        ) {
            app.terminate()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["SystemUIServer"]
        do {
            try process.run()
        } catch {
            NSLog("clipcap: failed to refresh SystemUIServer: \(error)")
        }
    }

    /// Removes only a direct child of the dedicated screenshot directory.
    /// The caller must invoke this after the editor has successfully loaded
    /// the image so failed handoffs never destroy the user's only copy.
    @discardableResult
    static func removeImageAfterEditorHandoff(
        at sourceURL: URL,
        monitoredDirectoryURL: URL = directoryURL,
        fileManager: FileManager = .default
    ) -> Bool {
        guard sourceURL.isFileURL, monitoredDirectoryURL.isFileURL else {
            return false
        }

        let standardizedSourceURL = sourceURL.standardizedFileURL
        let sourceDirectoryURL = standardizedSourceURL
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
        let standardizedMonitoredDirectoryURL = monitoredDirectoryURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard sourceDirectoryURL == standardizedMonitoredDirectoryURL else {
            NSLog("clipcap: refused to remove screenshot outside monitored directory: \(standardizedSourceURL.path)")
            return false
        }

        do {
            try fileManager.removeItem(at: standardizedSourceURL)
            return true
        } catch {
            NSLog("clipcap: failed to remove delivered system screenshot: \(error)")
            return false
        }
    }
}

protocol SystemScreenshotLocationPreferenceStoring: AnyObject {
    func readLocation() -> String?
    func readRecordingLocation() -> String?
    func snapshot() -> [String: String]?
    func restoreSnapshot(_ values: [String: String]) -> Bool
    @discardableResult func writeLocation(_ location: String?) -> Bool
}

extension SystemScreenshotLocationPreferenceStoring {
    func readRecordingLocation() -> String? { readLocation() }
    func snapshot() -> [String: String]? { nil }
    func restoreSnapshot(_ values: [String: String]) -> Bool { false }
}

protocol SystemScreenshotLocationBackupStoring: AnyObject {
    var isManaged: Bool { get set }
    var managedLocation: String? { get set }
    var originalPreferences: [String: String]? { get set }
    var originalLocationWasSet: Bool { get set }
    var originalLocation: String? { get set }
    func clear()
}

final class CFPreferencesSystemScreenshotLocationStore: SystemScreenshotLocationPreferenceStoring {
    private let applicationID = "com.apple.screencapture" as CFString
    private let keys = ["location", "location-screenshot", "location-screenrecording",
                        "target", "target-screenshot", "target-screenrecording"]

    private func synchronize() -> Bool {
        CFPreferencesSynchronize(applicationID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    private func value(_ key: String) -> String? {
        CFPreferencesCopyValue(key as CFString, applicationID,
                               kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? String
    }

    private func effectiveLocation(for mode: String) -> String? {
        _ = synchronize()
        // macOS 27 keeps separate screenshot and recording destinations. A
        // legacy location alone does not select that folder in Screenshot UI.
        let usesSeparateDestinations = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
        let target = value("target-" + mode) ?? (usesSeparateDestinations ? "file" : value("target")) ?? "file"
        guard target == "file" else { return nil }
        if let location = value("location-" + mode) { return location }
        if !usesSeparateDestinations, let location = value("location") { return location }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path
    }

    func readLocation() -> String? { effectiveLocation(for: "screenshot") }
    func readRecordingLocation() -> String? { effectiveLocation(for: "screenrecording") }

    func snapshot() -> [String: String]? {
        _ = synchronize()
        return Dictionary(uniqueKeysWithValues: keys.compactMap { key in value(key).map { (key, $0) } })
    }

    @discardableResult
    func writeLocation(_ location: String?) -> Bool {
        for key in ["location", "location-screenshot", "location-screenrecording"] {
            CFPreferencesSetValue(key as CFString, location as CFString?, applicationID,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }
        if location != nil {
            for key in ["target", "target-screenshot", "target-screenrecording"] {
                CFPreferencesSetValue(key as CFString, "file" as CFString, applicationID,
                                      kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            }
        }
        return synchronize()
    }

    func restoreSnapshot(_ values: [String: String]) -> Bool {
        for key in keys {
            CFPreferencesSetValue(key as CFString, values[key] as CFString?, applicationID,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }
        return synchronize() && snapshot() == values
    }
}

final class DefaultsSystemScreenshotLocationBackupStore: SystemScreenshotLocationBackupStoring {
    var originalPreferences: [String: String]? {
        get { Defaults.systemScreenshotOriginalPreferences }
        set { Defaults.systemScreenshotOriginalPreferences = newValue }
    }

    var managedLocation: String? {
        get { Defaults.systemScreenshotManagedLocation }
        set { Defaults.systemScreenshotManagedLocation = newValue }
    }

    var isManaged: Bool {
        get { Defaults.systemScreenshotLocationManaged }
        set { Defaults.systemScreenshotLocationManaged = newValue }
    }

    var originalLocationWasSet: Bool {
        get { Defaults.systemScreenshotOriginalLocationWasSet }
        set { Defaults.systemScreenshotOriginalLocationWasSet = newValue }
    }

    var originalLocation: String? {
        get { Defaults.systemScreenshotOriginalLocation }
        set { Defaults.systemScreenshotOriginalLocation = newValue }
    }

    func clear() {
        Defaults.clearSystemScreenshotLocationBackup()
    }
}

final class SystemScreenshotLocationManager {
    enum RestoreResult: Equatable {
        case restored
        case notManaged
        case changedExternally
        case failed
    }

    static let shared = SystemScreenshotLocationManager()

    private let fixedTargetDirectory: URL?
    var targetDirectory: URL { fixedTargetDirectory ?? SystemScreenshotAutoOpen.directoryURL }
    private let preferenceStore: SystemScreenshotLocationPreferenceStoring
    private let backupStore: SystemScreenshotLocationBackupStoring

    init(
        targetDirectory: URL? = nil,
        preferenceStore: SystemScreenshotLocationPreferenceStoring = CFPreferencesSystemScreenshotLocationStore(),
        backupStore: SystemScreenshotLocationBackupStoring = DefaultsSystemScreenshotLocationBackupStore()
    ) {
        self.fixedTargetDirectory = targetDirectory?.standardizedFileURL
        self.preferenceStore = preferenceStore
        self.backupStore = backupStore
    }

    var isTargetLocationActive: Bool {
        pathsMatch(preferenceStore.readLocation(), targetDirectory.path)
            && pathsMatch(preferenceStore.readRecordingLocation(), targetDirectory.path)
    }

    var isAutomaticallyManaged: Bool {
        backupStore.isManaged
    }

    @discardableResult
    func configureAutomatically() -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: targetDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            NSLog("clipcap: failed to create configured screenshot directory: \(error)")
            return false
        }
        if isTargetLocationActive {
            return true
        }

        let previousLocation = preferenceStore.readLocation()
        let previousPreferences = preferenceStore.snapshot()
        let retainsBackup = backupStore.isManaged
            && pathsMatch(previousLocation, backupStore.managedLocation ?? targetDirectory.path)
        if !retainsBackup {
            backupStore.clear()
            backupStore.originalLocationWasSet = previousLocation != nil
            backupStore.originalLocation = previousLocation
            backupStore.originalPreferences = previousPreferences
        }

        guard preferenceStore.writeLocation(targetDirectory.path), isTargetLocationActive else {
            if let previousPreferences {
                _ = preferenceStore.restoreSnapshot(previousPreferences)
            } else {
                _ = preferenceStore.writeLocation(previousLocation)
            }
            if !retainsBackup { backupStore.clear() }
            return false
        }
        backupStore.managedLocation = targetDirectory.path
        backupStore.isManaged = true
        return true
    }

    func restoreAutomaticallyConfiguredLocation() -> RestoreResult {
        guard backupStore.isManaged else { return .notManaged }
        guard pathsMatch(preferenceStore.readLocation(), backupStore.managedLocation ?? targetDirectory.path),
              pathsMatch(preferenceStore.readRecordingLocation(), backupStore.managedLocation ?? targetDirectory.path) else {
            backupStore.clear()
            return .changedExternally
        }

        let originalLocation = backupStore.originalLocationWasSet
            ? backupStore.originalLocation
            : nil
        let restored: Bool
        if let snapshot = backupStore.originalPreferences {
            restored = preferenceStore.restoreSnapshot(snapshot)
        } else {
            restored = preferenceStore.writeLocation(originalLocation)
                && locationsMatchAfterRestore(originalLocation)
        }
        guard restored else {
            return .failed
        }

        backupStore.clear()
        return .restored
    }

    func relinquishAutomaticallyManagedLocation() {
        backupStore.clear()
    }

    private func locationsMatchAfterRestore(_ originalLocation: String?) -> Bool {
        let current = preferenceStore.readLocation()
        guard let originalLocation else {
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path
            return current == nil || pathsMatch(current, desktop)
        }
        return pathsMatch(current, originalLocation)
    }

    private func pathsMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        normalizedPath(lhs) == normalizedPath(rhs)
    }

    private func normalizedPath(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        if let url = URL(string: value), url.isFileURL {
            return url.standardizedFileURL.resolvingSymlinksInPath().path
        }
        let expanded = NSString(string: value).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL.resolvingSymlinksInPath().path
    }
}

struct SystemScreenshotOpenQueue {
    private(set) var urls: [URL] = []

    var isEmpty: Bool { urls.isEmpty }

    mutating func enqueue(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard !urls.contains(standardized) else { return }
        urls.append(standardized)
    }

    mutating func popFirst() -> URL? {
        guard !urls.isEmpty else { return nil }
        return urls.removeFirst()
    }

    mutating func removeAll() {
        urls.removeAll()
    }
}

enum SystemScreenshotEditorHandoff {
    /// Opens the source first, then removes it from the dedicated monitored
    /// directory only after the editor confirms that it loaded successfully.
    @discardableResult
    static func launch(
        sourceURL: URL,
        monitoredDirectoryURL: URL = SystemScreenshotAutoOpen.directoryURL,
        fileManager: FileManager = .default,
        editorLauncher: (URL) -> Bool
    ) -> Bool {
        let standardizedSourceURL = sourceURL.standardizedFileURL
        guard editorLauncher(standardizedSourceURL) else { return false }
        SystemScreenshotAutoOpen.removeImageAfterEditorHandoff(
            at: standardizedSourceURL,
            monitoredDirectoryURL: monitoredDirectoryURL,
            fileManager: fileManager
        )
        return true
    }
}

final class SystemScreenshotDirectoryMonitor {
    typealias ImageReadyHandler = (URL) -> Void

    private struct FileVersion: Equatable {
        let size: Int
        let modificationTime: TimeInterval
    }

    private struct FileSnapshot {
        let identity: String
        let url: URL
        let version: FileVersion
    }

    private let directoryURL: URL
    private let settleDelay: TimeInterval
    private let reconciliationInterval: TimeInterval
    private let callbackQueue: DispatchQueue
    private let imageReady: ImageReadyHandler
    private let queue = DispatchQueue(label: "cn.skyrin.clipcap.system-screenshot-monitor", qos: .utility)
    private let queueKey = DispatchSpecificKey<UInt8>()

    private var isRunning = false
    private var directorySource: DispatchSourceFileSystemObject?
    private var reconciliationTimer: DispatchSourceTimer?
    private var processedVersions: [String: FileVersion] = [:]
    private var pendingVersions: [String: FileVersion] = [:]
    private var pendingWorkItems: [String: DispatchWorkItem] = [:]
    private var probeAttempts: [String: Int] = [:]

    init(
        directoryURL: URL = SystemScreenshotAutoOpen.directoryURL,
        settleDelay: TimeInterval = 0.25,
        reconciliationInterval: TimeInterval = 1,
        callbackQueue: DispatchQueue = .main,
        imageReady: @escaping ImageReadyHandler
    ) {
        self.directoryURL = directoryURL.standardizedFileURL
        self.settleDelay = settleDelay
        self.reconciliationInterval = reconciliationInterval
        self.callbackQueue = callbackQueue
        self.imageReady = imageReady
        queue.setSpecific(key: queueKey, value: 1)
    }

    deinit {
        stop()
    }

    func start() {
        let requestedAt = Date()
        queue.async { [weak self] in
            self?.startLocked(requestedAt: requestedAt)
        }
    }

    func stop() {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            stopLocked()
        } else {
            queue.sync { [weak self] in
                self?.stopLocked()
            }
        }
    }

    private func startLocked(requestedAt: Date) {
        guard !isRunning else { return }
        isRunning = true
        processedVersions.removeAll()
        pendingVersions.removeAll()
        probeAttempts.removeAll()

        guard ensureDirectoryExists() else {
            startReconciliationTimer()
            return
        }

        installDirectorySource()
        let snapshots = scanSnapshots()
        for snapshot in snapshots {
            if snapshot.version.modificationTime < requestedAt.timeIntervalSince1970 {
                processedVersions[snapshot.identity] = snapshot.version
            } else {
                scheduleProbe(for: snapshot)
            }
        }
        startReconciliationTimer()
    }

    private func stopLocked() {
        guard isRunning || directorySource != nil || reconciliationTimer != nil else { return }
        isRunning = false
        pendingWorkItems.values.forEach { $0.cancel() }
        pendingWorkItems.removeAll()
        pendingVersions.removeAll()
        probeAttempts.removeAll()
        processedVersions.removeAll()
        reconciliationTimer?.cancel()
        reconciliationTimer = nil
        directorySource?.cancel()
        directorySource = nil
    }

    private func ensureDirectoryExists() -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            return true
        } catch {
            NSLog("clipcap: failed to prepare screenshot monitor directory: \(error)")
            return false
        }
    }

    private func installDirectorySource() {
        guard isRunning, directorySource == nil else { return }
        let fileDescriptor = open(directoryURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.handleDirectoryEvent()
        }
        source.setCancelHandler {
            close(fileDescriptor)
        }
        directorySource = source
        source.resume()
    }

    private func handleDirectoryEvent() {
        guard isRunning else { return }
        let events = directorySource?.data ?? []
        if !events.intersection([.rename, .delete, .revoke]).isEmpty {
            directorySource?.cancel()
            directorySource = nil
            queue.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, self.isRunning, self.ensureDirectoryExists() else { return }
                self.installDirectorySource()
                self.reconcileDirectory()
            }
            return
        }
        reconcileDirectory()
    }

    private func startReconciliationTimer() {
        guard isRunning, reconciliationTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + reconciliationInterval,
            repeating: reconciliationInterval,
            leeway: .milliseconds(150)
        )
        timer.setEventHandler { [weak self] in
            guard let self, self.isRunning else { return }
            if self.directorySource == nil, self.ensureDirectoryExists() {
                self.installDirectorySource()
            }
            self.reconcileDirectory()
        }
        reconciliationTimer = timer
        timer.resume()
    }

    private func reconcileDirectory() {
        guard isRunning else { return }
        let snapshots = scanSnapshots()
        let currentIdentities = Set(snapshots.map(\.identity))

        for identity in Array(processedVersions.keys) where !currentIdentities.contains(identity) {
            processedVersions.removeValue(forKey: identity)
        }
        for identity in Array(pendingVersions.keys) where !currentIdentities.contains(identity) {
            pendingWorkItems.removeValue(forKey: identity)?.cancel()
            pendingVersions.removeValue(forKey: identity)
            probeAttempts.removeValue(forKey: identity)
        }

        for snapshot in snapshots where processedVersions[snapshot.identity] != snapshot.version {
            scheduleProbe(for: snapshot)
        }
    }

    private func scheduleProbe(for snapshot: FileSnapshot, force: Bool = false) {
        guard isRunning else { return }
        if !force,
           pendingVersions[snapshot.identity] == snapshot.version,
           pendingWorkItems[snapshot.identity] != nil {
            return
        }

        pendingWorkItems.removeValue(forKey: snapshot.identity)?.cancel()
        if pendingVersions[snapshot.identity] != snapshot.version {
            probeAttempts[snapshot.identity] = 0
        }
        pendingVersions[snapshot.identity] = snapshot.version

        let identity = snapshot.identity
        let expectedVersion = snapshot.version
        let workItem = DispatchWorkItem { [weak self] in
            self?.probe(
                identity: identity,
                url: snapshot.url,
                expectedVersion: expectedVersion
            )
        }
        pendingWorkItems[identity] = workItem
        queue.asyncAfter(deadline: .now() + (RecordingImport.isVideo(snapshot.url) ? max(2, settleDelay) : settleDelay), execute: workItem)
    }

    private func probe(identity: String, url: URL, expectedVersion: FileVersion) {
        guard isRunning,
              pendingVersions[identity] == expectedVersion
        else { return }
        pendingWorkItems.removeValue(forKey: identity)

        guard let current = snapshot(for: url) else {
            pendingVersions.removeValue(forKey: identity)
            probeAttempts.removeValue(forKey: identity)
            return
        }

        if current.identity != identity || current.version != expectedVersion {
            pendingVersions.removeValue(forKey: identity)
            probeAttempts.removeValue(forKey: identity)
            scheduleProbe(for: current)
            return
        }

        if isCompleteImage(at: url) {
            processedVersions[identity] = current.version
            pendingVersions.removeValue(forKey: identity)
            probeAttempts.removeValue(forKey: identity)
            callbackQueue.async { [imageReady] in
                imageReady(url)
            }
            return
        }

        let attempt = (probeAttempts[identity] ?? 0) + 1
        probeAttempts[identity] = attempt
        if attempt < 20 {
            scheduleProbe(for: current, force: true)
        } else {
            // Ignore this unchanged invalid version until the file changes
            // again instead of probing it forever during reconciliation.
            processedVersions[identity] = current.version
            pendingVersions.removeValue(forKey: identity)
            probeAttempts.removeValue(forKey: identity)
        }
    }

    private func scanSnapshots() -> [FileSnapshot] {
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .contentTypeKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .fileResourceIdentifierKey,
        ]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.compactMap(snapshot(for:))
    }

    private func snapshot(for url: URL) -> FileSnapshot? {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .contentTypeKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .fileResourceIdentifierKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isRegularFile == true,
              isSupportedImage(url: url, contentType: values.contentType),
              let size = values.fileSize,
              let modificationDate = values.contentModificationDate
        else { return nil }

        let identity = values.fileResourceIdentifier.map(String.init(describing:))
            ?? url.standardizedFileURL.path
        return FileSnapshot(
            identity: identity,
            url: url.standardizedFileURL,
            version: FileVersion(
                size: size,
                modificationTime: modificationDate.timeIntervalSince1970
            )
        )
    }

    private func isSupportedImage(url: URL, contentType: UTType?) -> Bool {
        if RecordingImport.isVideo(url) || contentType?.conforms(to: .image) == true {
            return true
        }
        let supportedExtensions: Set<String> = [
            "png", "jpg", "jpeg", "tif", "tiff", "gif", "heic", "heif", "webp", "bmp",
        ]
        return supportedExtensions.contains(url.pathExtension.lowercased())
    }

    private func isCompleteImage(at url: URL) -> Bool {
        if RecordingImport.isVideo(url) {
            let asset = AVURLAsset(url: url)
            return asset.isPlayable && asset.duration.seconds.isFinite && asset.duration.seconds > 0
                && !asset.tracks(withMediaType: .video).isEmpty
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete
        else { return false }
        return CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    }
}
