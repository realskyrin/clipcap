import AppKit
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum SystemScreenshotAutoOpen {
    static var directoryURL: URL {
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
    @discardableResult func writeLocation(_ location: String?) -> Bool
}

protocol SystemScreenshotLocationBackupStoring: AnyObject {
    var isManaged: Bool { get set }
    var originalLocationWasSet: Bool { get set }
    var originalLocation: String? { get set }
    func clear()
}

final class CFPreferencesSystemScreenshotLocationStore: SystemScreenshotLocationPreferenceStoring {
    private let key = "location" as CFString
    private let applicationID = "com.apple.screencapture" as CFString

    func readLocation() -> String? {
        CFPreferencesSynchronize(
            applicationID,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        return CFPreferencesCopyValue(
            key,
            applicationID,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? String
    }

    @discardableResult
    func writeLocation(_ location: String?) -> Bool {
        if let location {
            CFPreferencesSetValue(
                key,
                location as CFString,
                applicationID,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            )
        } else {
            CFPreferencesSetValue(
                key,
                nil,
                applicationID,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            )
        }
        return CFPreferencesSynchronize(
            applicationID,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
    }
}

final class DefaultsSystemScreenshotLocationBackupStore: SystemScreenshotLocationBackupStoring {
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

    let targetDirectory: URL
    private let preferenceStore: SystemScreenshotLocationPreferenceStoring
    private let backupStore: SystemScreenshotLocationBackupStoring

    init(
        targetDirectory: URL = SystemScreenshotAutoOpen.directoryURL,
        preferenceStore: SystemScreenshotLocationPreferenceStoring = CFPreferencesSystemScreenshotLocationStore(),
        backupStore: SystemScreenshotLocationBackupStoring = DefaultsSystemScreenshotLocationBackupStore()
    ) {
        self.targetDirectory = targetDirectory.standardizedFileURL
        self.preferenceStore = preferenceStore
        self.backupStore = backupStore
    }

    var isTargetLocationActive: Bool {
        pathsMatch(preferenceStore.readLocation(), targetDirectory.path)
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

        if backupStore.isManaged {
            // The user changed the screenshot location after ClipCap configured
            // it. Treat that newer choice as the value to restore next time.
            backupStore.clear()
        }

        let originalLocation = preferenceStore.readLocation()
        backupStore.originalLocationWasSet = originalLocation != nil
        backupStore.originalLocation = originalLocation
        backupStore.isManaged = false

        guard preferenceStore.writeLocation(targetDirectory.path),
              isTargetLocationActive
        else {
            _ = preferenceStore.writeLocation(originalLocation)
            backupStore.clear()
            return false
        }

        backupStore.isManaged = true
        return true
    }

    func restoreAutomaticallyConfiguredLocation() -> RestoreResult {
        guard backupStore.isManaged else { return .notManaged }
        guard isTargetLocationActive else {
            backupStore.clear()
            return .changedExternally
        }

        let originalLocation = backupStore.originalLocationWasSet
            ? backupStore.originalLocation
            : nil
        guard preferenceStore.writeLocation(originalLocation),
              locationsMatchAfterRestore(originalLocation)
        else {
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
        guard let originalLocation else { return current == nil }
        return pathsMatch(current, originalLocation)
    }

    private func pathsMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        normalizedPath(lhs) == normalizedPath(rhs)
    }

    private func normalizedPath(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        if let url = URL(string: value), url.isFileURL {
            return url.standardizedFileURL.path
        }
        let expanded = NSString(string: value).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
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
        queue.asyncAfter(deadline: .now() + settleDelay, execute: workItem)
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
        if contentType?.conforms(to: .image) == true {
            return true
        }
        let supportedExtensions: Set<String> = [
            "png", "jpg", "jpeg", "tif", "tiff", "gif", "heic", "heif", "webp", "bmp",
        ]
        return supportedExtensions.contains(url.pathExtension.lowercased())
    }

    private func isCompleteImage(at url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete
        else { return false }
        return CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    }
}
