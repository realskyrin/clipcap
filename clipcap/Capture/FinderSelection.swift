import AppKit
import UniformTypeIdentifiers

enum FinderSelection {
    static func currentImageFileURL() -> URL? {
        let urls = currentSelectionURLs()
        guard urls.count == 1, let url = urls.first else { return nil }
        return isImage(url) ? url : nil
    }

    static func currentImageFileURLs() -> [URL] {
        currentSelectionURLs().filter(isImage)
    }

    static func clearSelection() {
        let source = """
        tell application "Finder"
            set selection to {}
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
    }

    private static func currentSelectionURLs() -> [URL] {
        let source = """
        tell application "Finder"
            set sel to selection
            set out to {}
            repeat with f in sel
                try
                    set end of out to POSIX path of (f as alias)
                end try
            end repeat
            return out
        end tell
        """

        guard let script = NSAppleScript(source: source) else { return [] }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if error != nil { return [] }

        let count = result.numberOfItems
        guard count > 0 else { return [] }

        var urls: [URL] = []
        for index in 1...count {
            if let path = result.atIndex(index)?.stringValue {
                urls.append(URL(fileURLWithPath: path))
            }
        }
        return urls
    }

    private static func isImage(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey])
        guard let type = values?.contentType else { return false }
        return type.conforms(to: .image)
    }
}
