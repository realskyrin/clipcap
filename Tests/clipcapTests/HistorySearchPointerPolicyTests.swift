import AppKit
import XCTest
@testable import clipcap

final class HistorySearchPointerPolicyTests: XCTestCase {
    func testReportedWarpOffsetDoesNotEndEditingAcrossRepeatedTimerSamples() {
        let requested = NSPoint(x: 900.44, y: 1200)
        let actual = NSPoint(x: 901, y: 1200)
        for _ in 0..<120 {
            XCTAssertFalse(HistorySearchPointerPolicy.shouldLeaveInput(origin: requested, current: actual))
        }
    }

    func testSubpixelRoundingOnBothAxesDoesNotEndEditing() {
        XCTAssertFalse(HistorySearchPointerPolicy.shouldLeaveInput(
            origin: NSPoint(x: -1800.6, y: 920.4), current: NSPoint(x: -1800, y: 921)))
    }

    func testStationaryCursorKeepsEditing() {
        let actual = NSPoint(x: -1800, y: 921)
        XCTAssertFalse(HistorySearchPointerPolicy.shouldLeaveInput(origin: actual, current: actual))
    }

    func testDeliberateMovementStillLeavesInputInEveryDirection() {
        let origin = NSPoint(x: -1800, y: 921)
        for delta in [NSPoint(x: 4, y: 0), NSPoint(x: -4, y: 0),
                      NSPoint(x: 0, y: 4), NSPoint(x: 0, y: -4)] {
            XCTAssertTrue(HistorySearchPointerPolicy.shouldLeaveInput(
                origin: origin, current: NSPoint(x: origin.x + delta.x, y: origin.y + delta.y)))
        }
    }
}
