import AppKit
import UniformTypeIdentifiers

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController!
    private var overlayController: OverlayWindowController?
    private var historyPanelController: HistoryPanelController?
    private var suspendedEditDraft: OverlayWindowController.SuspendedEditDraft?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        initializeApp()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        openImageURLs(urls)
    }

    private func initializeApp() {
        ImageEditLauncher.clearTempDir()

        ImageMergeLauncher.shared.onContinueEditing = { [weak self] image in
            self?.continueEditingGeneratedImage(image, source: .merge)
        }

        historyPanelController = HistoryPanelController()
        statusBarController = StatusBarController(
            onEditClipboardImage: { [weak self] in self?.handleClipboardImageEditTrigger() },
            onOpenImage: { [weak self] in self?.openImagePanel() },
            onOpenHistoryPanel: { [weak self] in self?.handleHistoryPanelTrigger(holdOpenUntilMouseEnters: true) },
            onOpenSettings: { [weak self] in self?.openSettings() }
        )
        statusBarController.setMenuBarVisible(Defaults.showMenuBar)
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
            self?.openImageURLs([url])
        }
    }

    private func openImageURLs(_ urls: [URL]) {
        guard overlayController == nil else { return }
        guard let url = urls.first(where: Self.isImageFile) else {
            ToastWindow.show(message: L10n.openImageNoImage)
            return
        }
        launchImageFile(url)
    }

    private func launchImageFile(_ url: URL) {
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
            return
        }
        overlayController = controller
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
            ClipboardManager.copyToClipboard(image: finalImage)
            HistoryManager.shared.add(image: finalImage)
            ToastWindow.show()
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

    private static func isImageFile(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey])
        return values?.contentType?.conforms(to: .image) == true
    }
}
