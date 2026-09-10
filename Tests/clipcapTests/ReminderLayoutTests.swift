import AppKit
import XCTest
@testable import clipcap

final class ReminderLayoutTests: XCTestCase {
    @MainActor func testEditorGroupsHaveUsableHeightAndFitWindow() throws {
        _ = NSApplication.shared
        var entry = ReminderEntry()
        entry.settings.message = "喝杯水，休息一下"
        let controller = ReminderWindowController(entries: [entry])
        let window = try XCTUnwrap(controller.window)
        let root = try XCTUnwrap(window.contentView)
        window.appearance = NSAppearance(named: .darkAqua)
        root.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let groups = descendants(root).compactMap { $0 as? NSBox }.filter { $0.boxType == .custom }
        XCTAssertEqual(groups.count, 2)
        for group in groups {
            XCTAssertGreaterThan(group.frame.height, 70)
            XCTAssertGreaterThan(group.frame.width, 350)
            XCTAssertTrue(root.bounds.contains(group.convert(group.bounds, to: root)))
        }
        window.setContentSize(NSSize(width: 820, height: 550))
        root.layoutSubtreeIfNeeded()
        for group in groups { XCTAssertTrue(root.bounds.contains(group.convert(group.bounds, to: root))) }
    }
}
