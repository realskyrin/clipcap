import AppKit
import UniformTypeIdentifiers

class AppDelegate: NSObject, NSApplicationDelegate {
    private static let shareHandoffNotificationName = Notification.Name("cn.skyrin.clipcap.share-handoff")

    private var statusBarController: StatusBarController!
    private var overlayController: OverlayWindowController?
    private var historyPanelController: HistoryPanelController?
    private var suspendedEditDraft: OverlayWindowController.SuspendedEditDraft?
    private var pendingReopenSettingsWorkItem: DispatchWorkItem?
    private var didInitializeApp = false
    private var pendingOpenImageURLs: [URL] = []

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        initializeApp()
        didInitializeApp = true
        flushPendingOpenImageURLs()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        scheduleSettingsOpenFromReopen()
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        _ = requestOpenImageURLs(urls)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        requestOpenImageURLs([URL(fileURLWithPath: filename)])
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let handled = requestOpenImageURLs(filenames.map { URL(fileURLWithPath: $0) })
        sender.reply(toOpenOrPrint: handled ? .success : .failure)
    }

    private func initializeApp() {
        ImageEditLauncher.clearTempDir()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleShareHandoffNotification(_:)),
            name: Self.shareHandoffNotificationName,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        ImageMergeLauncher.shared.onContinueEditing = { [weak self] image in
            self?.continueEditingGeneratedImage(image, source: .merge)
        }

        historyPanelController = HistoryPanelController { [weak self] entry in
            _ = self?.launchImageFile(entry.fileURL)
        }
        statusBarController = StatusBarController(
            onEditClipboardImage: { [weak self] in self?.handleClipboardImageEditTrigger() },
            onOpenImage: { [weak self] in self?.openImagePanel() },
            onMergeImages: { [weak self] in self?.handleImageMergeMenuTrigger() },
            onOpenHistoryPanel: { [weak self] in self?.handleHistoryPanelTrigger(holdOpenUntilMouseEnters: true) },
            onOpenSettings: { [weak self] in self?.openSettings() }
        )
        statusBarController.setMenuBarVisible(Defaults.showMenuBar)

        NotificationCenter.default.addObserver(
            forName: .hotkeyDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyHotkeyState()
        }
        applyHotkeyState()
    }

    private func configuredSettingsController() -> SettingsWindowController {
        let settingsController = SettingsWindowController.shared
        settingsController.onMenuBarToggle = { [weak self] visible in
            self?.statusBarController?.setMenuBarVisible(visible)
        }
        settingsController.onLaunch = nil
        return settingsController
    }

    private func handleHistoryPanelTrigger(holdOpenUntilMouseEnters: Bool = false) {
        historyPanelController?.toggleFromUserRequest(holdOpenUntilMouseEnters: holdOpenUntilMouseEnters)
    }

    func handleImageMergeMenuTrigger() {
        guard overlayController == nil else { return }
        ImageMergeLauncher.shared.openEmpty()
    }

    @objc func handleImageMergeShortcutTrigger(_ sender: Any?) {
        guard overlayController == nil,
              !ImageMergeLauncher.shared.isWorkbenchActive
        else { return }
        ImageMergeLauncher.shared.openFromShortcutSources()
    }

    private func applyHotkeyState() {
        if Defaults.hasCustomSelectedImageEditHotkey {
            HotkeyManager.shared.registerSelectedImageEdit { [weak self] in
                self?.handleSelectedImageEditTrigger()
            }
        } else {
            HotkeyManager.shared.unregisterSelectedImageEdit()
        }

        if Defaults.hasCustomClipboardImageEditHotkey {
            HotkeyManager.shared.registerClipboardImageEdit { [weak self] in
                self?.handleClipboardImageEditTrigger()
            }
        } else {
            HotkeyManager.shared.unregisterClipboardImageEdit()
        }

        if Defaults.hasCustomSelectedImagePinHotkey {
            HotkeyManager.shared.registerSelectedImagePin { [weak self] in
                self?.handleSelectedImagePinTrigger()
            }
        } else {
            HotkeyManager.shared.unregisterSelectedImagePin()
        }

        if Defaults.hasCustomClipboardImagePinHotkey {
            HotkeyManager.shared.registerClipboardImagePin { [weak self] in
                self?.handleClipboardImagePinTrigger()
            }
        } else {
            HotkeyManager.shared.unregisterClipboardImagePin()
        }

        if Defaults.hasCustomHistoryPanelHotkey {
            HotkeyManager.shared.registerHistoryPanel { [weak self] in
                self?.handleHistoryPanelTrigger(holdOpenUntilMouseEnters: true)
            }
        } else {
            HotkeyManager.shared.unregisterHistoryPanel()
        }

        if Defaults.hasCustomImageMergeHotkey {
            HotkeyManager.shared.registerImageMerge { [weak self] in
                self?.handleImageMergeShortcutTrigger(nil)
            }
        } else {
            HotkeyManager.shared.unregisterImageMerge()
        }
    }

    func handleSelectedImageEditTrigger() {
        guard overlayController == nil else { return }
        if resumeSuspendedEditIfAvailable() {
            return
        }
        guard let controller = launchSelectedImageEdit() else {
            ToastWindow.show(message: L10n.selectedImageEditNoImage)
            return
        }
        overlayController = controller
    }

    func handleClipboardImageEditTrigger() {
        guard overlayController == nil else { return }
        if resumeSuspendedEditIfAvailable() {
            return
        }
        guard let controller = launchClipboardImageEdit() else {
            ToastWindow.show(message: L10n.clipboardImageEditNoImage)
            return
        }
        overlayController = controller
    }

    func handleSelectedImagePinTrigger() {
        guard overlayController == nil else { return }
        PinLauncher.pinSelectedImagesIfAvailable()
    }

    func handleClipboardImagePinTrigger() {
        guard overlayController == nil else { return }
        PinLauncher.pinClipboardImageIfAvailable()
    }

    private func openImagePanel() {
        guard overlayController == nil else { return }
        if resumeSuspendedEditIfAvailable() {
            return
        }

        let panel = NSOpenPanel()
        panel.title = L10n.openImage
        panel.prompt = L10n.openImage
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .gif, .heic, .image]

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.requestOpenImageURLs([url])
        }
    }

    @discardableResult
    private func requestOpenImageURLs(_ urls: [URL]) -> Bool {
        guard didInitializeApp else {
            guard Self.containsImageFile(in: urls) else { return false }
            pendingOpenImageURLs.append(contentsOf: urls)
            return true
        }

        return openImageURLs(urls)
    }

    private func flushPendingOpenImageURLs() {
        guard !pendingOpenImageURLs.isEmpty else { return }
        let urls = pendingOpenImageURLs
        pendingOpenImageURLs.removeAll()
        _ = openImageURLs(urls)
    }

    @discardableResult
    private func openImageURLs(_ urls: [URL]) -> Bool {
        guard overlayController == nil else { return true }
        guard let url = urls.lazy.compactMap(Self.resolvedImageFileURL).first(where: Self.isImageFile) else {
            ToastWindow.show(message: L10n.openImageNoImage)
            return false
        }

        let didLaunch = launchImageFile(url)
        if didLaunch {
            cancelPendingReopenSettings()
        }
        return didLaunch
    }

    @discardableResult
    private func launchImageFile(_ url: URL) -> Bool {
        guard let controller = ImageEditLauncher.launch(
            sourceURL: url,
            onSuspend: { [weak self] draft in
                self?.handleEditSuspension(draft)
            },
            onComplete: { [weak self] finalImage in
                self?.handleEditCompletion(finalImage)
            }
        ) else {
            ToastWindow.show(message: L10n.openImageNoImage)
            return false
        }
        overlayController = controller
        return true
    }

    private func launchSelectedImageEdit() -> OverlayWindowController? {
        let focusRestorer = SourceAppFocusRestorer.captureFrontmostApplication()
        guard let url = FinderSelection.currentImageFileURL() else { return nil }
        return ImageEditLauncher.launch(
            sourceURL: url,
            onRequestFocusReturn: {
                focusRestorer.restore()
            },
            onSuspend: { [weak self] draft in
                self?.handleEditSuspension(draft)
            },
            onComplete: { [weak self] finalImage in
                self?.handleEditCompletion(finalImage)
            }
        )
    }

    private func launchClipboardImageEdit() -> OverlayWindowController? {
        guard let image = ClipboardImageSource.currentImage() else { return nil }
        return ImageEditLauncher.launch(
            clipboardImage: image,
            onSuspend: { [weak self] draft in
                self?.handleEditSuspension(draft)
            },
            onComplete: { [weak self] finalImage in
                self?.handleEditCompletion(finalImage)
            }
        )
    }

    @discardableResult
    func handlePinnedImageEditRequest(_ image: NSImage, beforePresent: () -> Void) -> Bool {
        guard overlayController == nil else { return false }
        beforePresent()
        guard let controller = ImageEditLauncher.launch(
            generatedImage: image,
            source: .pin,
            keepsEditorAcrossSpaces: Defaults.pinAcrossSpaces,
            onSuspend: { [weak self] draft in
                self?.handleEditSuspension(draft)
            },
            onComplete: { [weak self] finalImage in
                self?.handleEditCompletion(finalImage)
            }
        ) else {
            return false
        }
        overlayController = controller
        return true
    }

    private func continueEditingGeneratedImage(_ image: NSImage, source: OverlayWindowController.PresetSource) {
        guard overlayController == nil else { return }
        guard let controller = ImageEditLauncher.launch(
            generatedImage: image,
            source: source,
            onSuspend: { [weak self] draft in
                self?.handleEditSuspension(draft)
            },
            onComplete: { [weak self] finalImage in
                self?.handleEditCompletion(finalImage)
            }
        ) else {
            ToastWindow.show(message: L10n.imageMergeFailed)
            return
        }
        overlayController = controller
    }

    private func handleEditCompletion(_ finalImage: NSImage?) {
        if let finalImage {
            let quality = Defaults.screenshotClipboardQuality
            if quality.usesLossyCompression {
                ToastWindow.show(message: L10n.screenshotQualityCompressingClipboard, duration: 600)
            }
            ImageOutputEncoder.encodeClipboardAsync(image: finalImage, quality: quality) { result in
                if quality.usesLossyCompression {
                    ToastWindow.dismiss()
                }
                switch result {
                case .failure:
                    HistoryManager.shared.add(image: finalImage)
                    ToastWindow.show(message: L10n.screenshotCompressionFailed, duration: 3.0)
                case .success(let output):
                    ClipboardManager.copyToClipboard(imageOutput: output)
                    HistoryManager.shared.add(image: finalImage)
                    ToastWindow.show()
                }
            }
        }
        overlayController = nil
    }

    private func handleEditSuspension(_ draft: OverlayWindowController.SuspendedEditDraft) {
        suspendedEditDraft = draft
        overlayController = nil
        ToastWindow.show(
            message: L10n.editSuspendedToast,
            on: screen(for: draft),
            duration: 3.0
        )
    }

    private func resumeSuspendedEditIfAvailable() -> Bool {
        guard let draft = suspendedEditDraft else { return false }
        let controller = OverlayWindowController(
            suspendedDraft: draft,
            onSuspend: { [weak self] draft in
                self?.handleEditSuspension(draft)
            },
            onComplete: { [weak self] finalImage in
                self?.handleEditCompletion(finalImage)
            }
        )
        suspendedEditDraft = nil
        overlayController = controller
        controller.activate()
        return true
    }

    private func screen(for draft: OverlayWindowController.SuspendedEditDraft) -> NSScreen? {
        if let displayID = draft.screenDisplayID,
           let screen = NSScreen.screens.first(where: {
               ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
           }) {
            return screen
        }
        return NSScreen.screens.first(where: { $0.frame == draft.screenFrame }) ?? NSScreen.main
    }

    private func openSettings() {
        configuredSettingsController().showAsSettings()
    }

    private func scheduleSettingsOpenFromReopen() {
        cancelPendingReopenSettings()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.overlayController == nil else { return }
            self.openSettings()
        }
        pendingReopenSettingsWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: workItem)
    }

    private func cancelPendingReopenSettings() {
        pendingReopenSettingsWorkItem?.cancel()
        pendingReopenSettingsWorkItem = nil
    }

    @objc private func handleShareHandoffNotification(_ notification: Notification) {
        guard let filePath = notification.userInfo?["file"] as? String,
              !filePath.isEmpty
        else {
            return
        }

        cancelPendingReopenSettings()
        requestOpenImageURLs([URL(fileURLWithPath: filePath)])
    }

    private static func containsImageFile(in urls: [URL]) -> Bool {
        urls.lazy.compactMap(resolvedImageFileURL).contains(where: isImageFile)
    }

    private static func isImageFile(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey])
        return values?.contentType?.conforms(to: .image) == true
    }

    private static func resolvedImageFileURL(from url: URL) -> URL? {
        if url.isFileURL {
            return url
        }

        guard url.scheme?.caseInsensitiveCompare("clipcap") == .orderedSame,
              url.host?.caseInsensitiveCompare("edit") == .orderedSame,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let filePath = components.queryItems?.first(where: { $0.name == "file" })?.value,
              !filePath.isEmpty
        else {
            return nil
        }

        return URL(fileURLWithPath: filePath)
    }
}
