import AppKit
import XCTest
@testable import clipcap

final class ReminderLayoutTests: XCTestCase {
    @MainActor func testRepeatControlsReflectExactDaySets() throws {
        _ = NSApplication.shared
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        for days: Set<Int> in [Set(1...7), Set(2...6), [1, 7], [4, 5, 7], []] {
            var entry = ReminderEntry()
            entry.settings.selectedWeekdays = days
            let controller = ReminderWindowController(entries: [entry])
            let root = try XCTUnwrap(controller.window?.contentView)
            root.layoutSubtreeIfNeeded()
            let controls = descendants(root)
            let presets = try XCTUnwrap(controls.compactMap { $0 as? NSSegmentedControl }.first)
            for index in 0..<3 {
                XCTAssertEqual(presets.isSelected(forSegment: index), entry.settings.repeatPreset == index)
            }
            let chips = controls.compactMap { $0 as? NSButton }.filter { (1...7).contains($0.tag) }
            XCTAssertEqual(chips.count, 7)
            for chip in chips { XCTAssertEqual(chip.state == .on, days.contains(chip.tag)) }
        }
    }

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
