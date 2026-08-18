import AppKit
import XCTest
@testable import clipcap

final class ClipboardManagerTests: XCTestCase {
    func testCopyFilePathWritesStandardizedAbsolutePathWithoutTextHistoryEntry() {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("cn.skyrin.clipcap.tests.\(UUID().uuidString)")
        )
        defer { pasteboard.releaseGlobally() }

        ClipboardManager.copyFilePathToClipboard(
            URL(fileURLWithPath: "/tmp/history/../image.png"),
            pasteboard: pasteboard
        )

        XCTAssertEqual(pasteboard.string(forType: .string), "/tmp/image.png")
        XCTAssertEqual(
            pasteboard.string(
                forType: NSPasteboard.PasteboardType(
                    "cn.skyrin.clipcap.skip-clipboard-text-history"
                )
            ),
            "1"
        )
    }
}
