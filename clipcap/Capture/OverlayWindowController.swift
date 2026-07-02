import AppKit

final class OverlayWindowController {
    enum PresetSource {
        case file
        case clipboard
        case pin
        case merge
        case fullScreen
    }

    struct SuspendedEditDraft {
        let captureRect: CGRect
        let screenDisplayID: CGDirectDisplayID?
        let screenFrame: NSRect
        let selectionRect: NSRect
        let selectionViewRect: NSRect
        let selectionSizeLabelOverride: String?
        let selectionLocked: Bool
        let selectionInteractionEnabled: Bool
        let preSnapshot: CGImage?
        let overrideBaseImage: NSImage?
        let windowBaseImage: NSImage?
        let isWindowCapture: Bool
        let editorState: EditWindowController.RestorableState
        let keepsEditorAcrossSpaces: Bool
    }

    private var window: NSPanel?
    private var selectionView: SelectionView?
    private var editController: EditWindowController?
    private var keyMonitor: Any?
    private var presentationScheduled = false

    private let presetImage: NSImage?
    private let suspendedDraft: SuspendedEditDraft?
    private let keepsEditorAcrossSpaces: Bool
    private let onRequestFocusReturn: (() -> Void)?
    private let onComplete: (NSImage?) -> Void

    init(
        presetImage: NSImage,
        presetSource: PresetSource,
        keepsEditorAcrossSpaces: Bool = false,
        onRequestFocusReturn: (() -> Void)? = nil,
        onSuspend: ((SuspendedEditDraft) -> Void)? = nil,
        onComplete: @escaping (NSImage?) -> Void
    ) {
        self.presetImage = presetImage
        self.suspendedDraft = nil
        self.keepsEditorAcrossSpaces = keepsEditorAcrossSpaces
        self.onRequestFocusReturn = onRequestFocusReturn
        self.onComplete = onComplete
    }

    init(
        suspendedDraft: SuspendedEditDraft,
        onRequestFocusReturn: (() -> Void)? = nil,
        onSuspend: ((SuspendedEditDraft) -> Void)? = nil,
        onComplete: @escaping (NSImage?) -> Void
    ) {
        self.presetImage = nil
        self.suspendedDraft = suspendedDraft
        self.keepsEditorAcrossSpaces = suspendedDraft.keepsEditorAcrossSpaces
        self.onRequestFocusReturn = onRequestFocusReturn
        self.onComplete = onComplete
    }

    func activate() {
        guard !presentationScheduled else { return }
        presentationScheduled = true
        presentEditor()
    }

    func confirmFromKeyboard() {
        editController?.confirmFromKeyboard()
    }

    private func presentEditor() {
        guard window == nil else { return }
        guard let image = presetImage ?? suspendedDraft?.overrideBaseImage else {
            onComplete(nil)
            return
        }

        let screen = screenForPresentation()
        let panel = makePanel(on: screen)
        let host = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        host.autoresizingMask = [.width, .height]
        host.selectionLocked = true
        host.selectionInteractionEnabled = false
        panel.contentView = host
        panel.orderFrontRegardless()
        panel.makeKey()
        NSApp.activate(ignoringOtherApps: true)

        let selectionRect = suspendedDraft?.selectionRect ?? Self.fittedRect(
            imageSize: image.size,
            in: host.bounds
        )
        host.updateSelectionRect(selectionRect)

        let captureRect = suspendedDraft?.captureRect ?? Self.captureRect(
            selectionRect: selectionRect,
            screen: screen
        )
        let editor = EditWindowController(
            captureRect: captureRect,
            screen: screen,
            selectionRect: selectionRect,
            selectionViewRect: selectionRect,
            hostSelectionView: host,
            preSnapshot: nil,
            overrideBaseImage: image,
            windowBaseImage: nil,
            isWindowCapture: false,
            onRequestFocusReturn: onRequestFocusReturn,
            keepsHostWindowAcrossSpaces: keepsEditorAcrossSpaces,
            onComplete: { [weak self] finalImage in
                self?.complete(finalImage)
            }
        )
        editController = editor
        selectionView = host
        window = panel
        installKeyMonitor()
        editor.show()
        if let state = suspendedDraft?.editorState {
            editor.restoreState(state)
        }
    }

    private func makePanel(on screen: NSScreen) -> NSPanel {
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = keepsEditorAcrossSpaces
            ? [.canJoinAllSpaces, .fullScreenAuxiliary]
            : [.fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.animationBehavior = .none
        return panel
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.editController?.isTextEditing == true {
                return event
            }
            if self.editController?.confirmCropFromKeyboard(for: event) == true { return nil }
            if self.editController?.undoFromKeyboard(for: event) == true { return nil }
            if self.editController?.redoFromKeyboard(for: event) == true { return nil }
            if self.editController?.handleAnnotationClipboardShortcutFromKeyboard(for: event) == true { return nil }
            if self.editController?.nudgeSelectedAnnotationFromKeyboard(for: event) == true { return nil }
            if self.editController?.deleteSelectedAnnotationFromKeyboard(for: event) == true { return nil }
            if event.keyCode == 53 {
                self.cancel()
                return nil
            }
            if HotkeyManager.eventMatchesClipboardHotkey(event) {
                self.editController?.confirmFromKeyboard()
                return nil
            }
            if HotkeyManager.eventMatchesFileSaveHotkey(event) {
                self.editController?.saveFromKeyboard()
                return nil
            }
            if self.editController?.handleEditorShortcutFromKeyboard(for: event) == true { return nil }
            return event
        }
    }

    private func complete(_ image: NSImage?) {
        tearDown()
        onComplete(image)
    }

    private func cancel() {
        tearDown()
        onComplete(nil)
    }

    private func tearDown() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        editController?.tearDown()
        editController = nil
        selectionView = nil
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
    }

    private func screenForPresentation() -> NSScreen {
        if let draft = suspendedDraft {
            if let displayID = draft.screenDisplayID,
               let screen = NSScreen.screens.first(where: {
                   ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
               }) {
                return screen
            }
            if let screen = NSScreen.screens.first(where: { $0.frame == draft.screenFrame }) {
                return screen
            }
        }
        return NSScreen.main ?? NSScreen.screens.first!
    }

    private static func fittedRect(imageSize: NSSize, in bounds: NSRect) -> NSRect {
        let maxSize = NSSize(
            width: max(bounds.width - 160, 320),
            height: max(bounds.height - 160, 240)
        )
        let scale = min(maxSize.width / max(imageSize.width, 1), maxSize.height / max(imageSize.height, 1), 1)
        let size = NSSize(
            width: max(1, imageSize.width * scale),
            height: max(1, imageSize.height * scale)
        )
        return NSRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func captureRect(selectionRect: NSRect, screen: NSScreen) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let screenPoint = NSPoint(
            x: screen.frame.minX + selectionRect.minX,
            y: screen.frame.minY + selectionRect.minY
        )
        return CGRect(
            x: screenPoint.x,
            y: primaryHeight - (screenPoint.y + selectionRect.height),
            width: selectionRect.width,
            height: selectionRect.height
        )
    }
}
