import AppKit

final class ColorPickerRunner {
    static let shared = ColorPickerRunner()

    private init() {}

    func cancel() {}

    @discardableResult
    func run(
        on screen: NSScreen? = nil,
        onPicked: ((NSColor, String) -> Void)? = nil,
        onFinished: (() -> Void)? = nil
    ) -> Bool {
        onFinished?()
        return false
    }
}
