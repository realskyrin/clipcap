import AppKit

final class HotkeyManager {
    static let shared = HotkeyManager()

    private var historyPanelMonitor: Any?
    private var historyPanelCallback: (() -> Void)?

    private init() {}

    func register(callback: @escaping () -> Void) {}
    func unregister() {}
    func registerCountdown(callback: @escaping () -> Void) {}
    func unregisterCountdown() {}
    func registerSelectedImagePin(callback: @escaping () -> Void) {}
    func unregisterSelectedImagePin() {}
    func registerClipboardImagePin(callback: @escaping () -> Void) {}
    func unregisterClipboardImagePin() {}
    func registerClipboardTextPin(callback: @escaping () -> Void) {}
    func unregisterClipboardTextPin() {}
    func registerSelectedImageEdit(callback: @escaping () -> Void) {}
    func unregisterSelectedImageEdit() {}
    func registerClipboardImageEdit(callback: @escaping () -> Void) {}
    func unregisterClipboardImageEdit() {}
    func registerTextRecognition(callback: @escaping () -> Void) {}
    func unregisterTextRecognition() {}
    func registerCopyImageText(callback: @escaping () -> Void) {}
    func unregisterCopyImageText() {}
    func registerImageMerge(callback: @escaping () -> Void) {}
    func unregisterImageMerge() {}
    func registerFullScreenScreenshot(callback: @escaping () -> Void) {}
    func unregisterFullScreenScreenshot() {}
    func registerColorPicker(callback: @escaping () -> Void) {}
    func unregisterColorPicker() {}
    func registerHistoryPanel(callback: @escaping () -> Void) {
        historyPanelCallback = callback
        guard historyPanelMonitor == nil else { return }
        historyPanelMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard HotkeyManager.eventMatchesHistoryPanelHotkey(event) else { return event }
            self?.historyPanelCallback?()
            return nil
        }
    }

    func unregisterHistoryPanel() {
        if let historyPanelMonitor {
            NSEvent.removeMonitor(historyPanelMonitor)
        }
        historyPanelMonitor = nil
        historyPanelCallback = nil
    }

    static func currentClipboardDisplayString() -> String? {
        displayString(keyCode: effectiveClipboardHotkey.keyCode, modifiers: effectiveClipboardHotkey.modifiers)
    }

    static func currentFileSaveDisplayString() -> String {
        displayString(keyCode: effectiveFileSaveHotkey.keyCode, modifiers: effectiveFileSaveHotkey.modifiers)
    }

    static func currentPreviousHistoryImageDisplayString() -> String {
        displayString(
            keyCode: effectivePreviousHistoryImageHotkey.keyCode,
            modifiers: effectivePreviousHistoryImageHotkey.modifiers
        )
    }

    static func currentNextHistoryImageDisplayString() -> String {
        displayString(
            keyCode: effectiveNextHistoryImageHotkey.keyCode,
            modifiers: effectiveNextHistoryImageHotkey.modifiers
        )
    }

    static func currentDisplayString() -> String? { nil }
    static func currentCountdownDisplayString() -> String? { nil }
    static func currentSelectedImagePinDisplayString() -> String? { nil }
    static func currentClipboardImagePinDisplayString() -> String? { nil }
    static func currentClipboardTextPinDisplayString() -> String? { nil }
    static func currentSelectedImageEditDisplayString() -> String? { nil }
    static func currentClipboardImageEditDisplayString() -> String? { nil }
    static func currentTextRecognitionDisplayString() -> String? { nil }
    static func currentCopyImageTextDisplayString() -> String? { nil }
    static func currentImageMergeDisplayString() -> String? { nil }
    static func currentFullScreenScreenshotDisplayString() -> String? { nil }
    static func currentColorPickerDisplayString() -> String? { nil }
    static func currentHistoryPanelDisplayString() -> String? {
        guard Defaults.hasCustomHistoryPanelHotkey else { return nil }
        return displayString(keyCode: Defaults.historyPanelHotkeyKeyCode, modifiers: Defaults.historyPanelHotkeyModifiers)
    }

    static func eventMatchesClipboardHotkey(_ event: NSEvent) -> Bool {
        eventMatches(event, hotkey: effectiveClipboardHotkey)
    }

    static func eventMatchesFileSaveHotkey(_ event: NSEvent) -> Bool {
        eventMatches(event, hotkey: effectiveFileSaveHotkey)
    }

    static func eventMatchesPreviousHistoryImageHotkey(_ event: NSEvent) -> Bool {
        eventMatches(event, hotkey: effectivePreviousHistoryImageHotkey)
    }

    static func eventMatchesNextHistoryImageHotkey(_ event: NSEvent) -> Bool {
        eventMatches(event, hotkey: effectiveNextHistoryImageHotkey)
    }

    static func eventMatchesHistoryPanelHotkey(_ event: NSEvent) -> Bool {
        guard Defaults.hasCustomHistoryPanelHotkey else { return false }
        return eventMatches(
            event,
            hotkey: (Defaults.historyPanelHotkeyKeyCode, Defaults.historyPanelHotkeyModifiers)
        )
    }

    static func displayString(keyCode: Int, modifiers: Int) -> String {
        var pieces: [String] = []
        if modifiers & 4096 != 0 { pieces.append("⌃") }
        if modifiers & 2048 != 0 { pieces.append("⌥") }
        if modifiers & 512 != 0 { pieces.append("⇧") }
        if modifiers & 256 != 0 { pieces.append("⌘") }
        pieces.append(keyName(UInt16(keyCode)))
        return pieces.joined()
    }

    static func legacyModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        let normalized = flags.intersection(.deviceIndependentFlagsMask)
        var modifiers = 0
        if normalized.contains(.control) { modifiers |= 4096 }
        if normalized.contains(.option) { modifiers |= 2048 }
        if normalized.contains(.shift) { modifiers |= 512 }
        if normalized.contains(.command) { modifiers |= 256 }
        return modifiers
    }

    static func isFunctionKey(_ keyCode: UInt16) -> Bool {
        (122...127).contains(Int(keyCode)) || (96...111).contains(Int(keyCode))
    }

    func hotkeyConflictMessage(keyCode: UInt32, modifiers: UInt32, slot: Any? = nil) -> String? {
        nil
    }

    private static var effectiveClipboardHotkey: (keyCode: Int, modifiers: Int) {
        Defaults.hasCustomClipboardHotkey
            ? (Defaults.clipboardHotkeyKeyCode, Defaults.clipboardHotkeyModifiers)
            : (36, 0)
    }

    private static var effectiveFileSaveHotkey: (keyCode: Int, modifiers: Int) {
        Defaults.hasCustomFileSaveHotkey
            ? (Defaults.fileSaveHotkeyKeyCode, Defaults.fileSaveHotkeyModifiers)
            : (1, 256)
    }

    private static var effectivePreviousHistoryImageHotkey: (keyCode: Int, modifiers: Int) {
        Defaults.hasCustomPreviousHistoryImageHotkey
            ? (Defaults.previousHistoryImageHotkeyKeyCode, Defaults.previousHistoryImageHotkeyModifiers)
            : (43, 0)
    }

    private static var effectiveNextHistoryImageHotkey: (keyCode: Int, modifiers: Int) {
        Defaults.hasCustomNextHistoryImageHotkey
            ? (Defaults.nextHistoryImageHotkeyKeyCode, Defaults.nextHistoryImageHotkeyModifiers)
            : (47, 0)
    }

    private static func eventMatches(_ event: NSEvent, hotkey: (keyCode: Int, modifiers: Int)) -> Bool {
        Int(event.keyCode) == hotkey.keyCode
            && legacyModifiers(from: event.modifierFlags) == hotkey.modifiers
    }

    private static func keyName(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "↩"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 49: return "␣"
        case 50: return "`"
        case 53: return "⎋"
        case 76: return "⌤"
        case 117: return "⌦"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "#\(keyCode)"
        }
    }
}
