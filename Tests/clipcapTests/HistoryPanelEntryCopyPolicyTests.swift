import Foundation
import XCTest
@testable import clipcap

final class HistoryPanelEntryCopyPolicyTests: XCTestCase {
    func testOptionClickOnImageCopiesStandardizedAbsolutePath() {
        let entry = HistoryEntry(
            fileURL: URL(fileURLWithPath: "/tmp/history/../image.png"),
            createdAt: Date(),
            kind: .image
        )

        XCTAssertEqual(
            HistoryPanelEntryCopyPolicy.mode(for: entry, optionPressed: true),
            .imageAbsolutePath("/tmp/image.png")
        )
    }

    func testImageClickWithoutOptionKeepsContentCopyMode() {
        let entry = HistoryEntry(
            fileURL: URL(fileURLWithPath: "/tmp/image.png"),
            createdAt: Date(),
            kind: .image
        )

        XCTAssertEqual(
            HistoryPanelEntryCopyPolicy.mode(for: entry, optionPressed: false),
            .content
        )
    }

    func testOptionClickOnNonImageKeepsContentCopyMode() {
        let entry = HistoryEntry(
            fileURL: URL(fileURLWithPath: "/tmp/color.color"),
            createdAt: Date(),
            kind: .color(hex: "#112233")
        )

        XCTAssertEqual(
            HistoryPanelEntryCopyPolicy.mode(for: entry, optionPressed: true),
            .content
        )
    }
}
