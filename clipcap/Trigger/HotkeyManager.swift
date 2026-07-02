import AppKit

final class HotkeyManager {
    static let shared = HotkeyManager()

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
    func registerScreenshotTranslation(callback: @escaping () -> Void) {}
    func unregisterScreenshotTranslation() {}
    func registerImageMerge(callback: @escaping () -> Void) {}
    func unregisterImageMerge() {}
    func registerFullScreenScreenshot(callback: @escaping () -> Void) {}
    func unregisterFullScreenScreenshot() {}
    func registerColorPicker(callback: @escaping () -> Void) {}
    func unregisterColorPicker() {}
    func registerHistoryPanel(callback: @escaping () -> Void) {}
    func unregisterHistoryPanel() {}

    static func currentClipboardDisplayString() -> String? {
        "⌘+Return"
    }

    static func currentFileSaveDisplayString() -> String {
        "⌘+S"
    }

    static func currentPreviousHistoryImageDisplayString() -> String {
        ","
    }

    static func currentNextHistoryImageDisplayString() -> String {
        "."
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
    static func currentScreenshotTranslationDisplayString() -> String? { nil }
    static func currentImageMergeDisplayString() -> String? { nil }
    static func currentFullScreenScreenshotDisplayString() -> String? { nil }
    static func currentColorPickerDisplayString() -> String? { nil }
    static func currentHistoryPanelDisplayString() -> String? { nil }

    static func eventMatchesClipboardHotkey(_ event: NSEvent) -> Bool {
        event.keyCode == 36 && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
    }

    static func eventMatchesFileSaveHotkey(_ event: NSEvent) -> Bool {
        event.charactersIgnoringModifiers?.lowercased() == "s"
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
    }

    static func eventMatchesPreviousHistoryImageHotkey(_ event: NSEvent) -> Bool {
        event.charactersIgnoringModifiers == ","
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
    }

    static func eventMatchesNextHistoryImageHotkey(_ event: NSEvent) -> Bool {
        event.charactersIgnoringModifiers == "."
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
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

    static func isFunctionKey(_ keyCode: UInt16) -> Bool {
        (122...127).contains(Int(keyCode)) || (96...111).contains(Int(keyCode))
    }

    func hotkeyConflictMessage(keyCode: UInt32, modifiers: UInt32, slot: Any? = nil) -> String? {
        nil
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
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 45: return "N"
        case 46: return "M"
        case 36: return "Return"
        case 49: return "Space"
        case 53: return "Esc"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "#\(keyCode)"
        }
    }
}
