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

    func testImagePathsTextFiltersNonImagesAndUsesOnePathPerLine() {
        let entries = [
            HistoryEntry(
                fileURL: URL(fileURLWithPath: "/tmp/folder/../first.png"),
                createdAt: Date(),
                kind: .image
            ),
            HistoryEntry(
                fileURL: URL(fileURLWithPath: "/tmp/color.color"),
                createdAt: Date(),
                kind: .color(hex: "#112233")
            ),
            HistoryEntry(
                fileURL: URL(fileURLWithPath: "/tmp/second.gif"),
                createdAt: Date(),
                kind: .image
            )
        ]

        XCTAssertEqual(
            HistoryPanelEntryCopyPolicy.imagePathsText(for: entries),
            "/tmp/first.png\n/tmp/second.gif"
        )
    }

    func testImagePathsTextReturnsNilWithoutImages() {
        let entry = HistoryEntry(
            fileURL: URL(fileURLWithPath: "/tmp/color.color"),
            createdAt: Date(),
            kind: .color(hex: "#112233")
        )

        XCTAssertNil(HistoryPanelEntryCopyPolicy.imagePathsText(for: [entry]))
    }
}
