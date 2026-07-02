import AppKit

enum ScreenCapturer {
    static func capture(
        rect: CGRect,
        screen: NSScreen,
        excludingWindowNumbers: [CGWindowID] = [],
        timeout: TimeInterval? = nil
    ) -> NSImage? {
        nil
    }

    static func capture(windowID: CGWindowID, pointSize: NSSize? = nil) -> NSImage? {
        nil
    }

    static func isEffectivelyTransparent(_ image: NSImage, alphaThreshold: UInt8 = 3) -> Bool {
        false
    }

    static func crop(from snapshot: CGImage, captureRect: CGRect, screen: NSScreen) -> NSImage? {
        let imageWidth = snapshot.width
        let imageHeight = snapshot.height
        guard imageWidth > 0, imageHeight > 0, captureRect.width > 0, captureRect.height > 0 else {
            return nil
        }

        let scaleX = CGFloat(imageWidth) / max(screen.frame.width, 1)
        let scaleY = CGFloat(imageHeight) / max(screen.frame.height, 1)
        let pixelRect = CGRect(
            x: (captureRect.minX - screen.frame.minX) * scaleX,
            y: (captureRect.minY - screen.frame.minY) * scaleY,
            width: captureRect.width * scaleX,
            height: captureRect.height * scaleY
        ).integral

        guard let cropped = snapshot.cropping(to: pixelRect) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: captureRect.width, height: captureRect.height))
    }
}
