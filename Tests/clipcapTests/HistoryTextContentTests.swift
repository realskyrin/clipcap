import Foundation
import XCTest
@testable import clipcap

final class HistoryTextContentTests: XCTestCase {
    func testSaveWritesFileAndRefreshesCachedValue() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let fileURL = directoryURL.appendingPathComponent("history.txt")
        try "Before".write(to: fileURL, atomically: true, encoding: .utf8)
        let content = HistoryTextContent(fileURL: fileURL)
        XCTAssertEqual(content.value, "Before")

        try content.save("After")

        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "After")
        XCTAssertEqual(content.loadedValue, "After")
        XCTAssertEqual(content.value, "After")
    }
}
