import AppKit

struct DetectedWindow {
    let name: String
    let windowID: CGWindowID
    let layer: Int
    let frame: CGRect

    var usesCompositedScreenBackdrop: Bool { false }
}

final class WindowDetector {
    func refresh() {}

    func usesCompositedScreenBackdrop(forWindowID windowID: CGWindowID) -> Bool {
        false
    }

    func windowAt(cgPoint: CGPoint) -> DetectedWindow? {
        nil
    }
}
