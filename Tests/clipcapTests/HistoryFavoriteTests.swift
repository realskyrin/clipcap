import Foundation
import XCTest
@testable import clipcap

final class HistoryFavoriteTests: XCTestCase {
    private var directoryURL: URL!

    override func setUpWithError() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directoryURL {
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    func testSetFavoritePersists() throws {
        let file = try makeFile(name: "image.png", contents: Data([0x01]))

        XCTAssertTrue(HistoryManager.setFavorite(true, on: file))
        XCTAssertTrue(HistoryManager.isFavorite(url: file))
        XCTAssertTrue(HistoryManager.isFavorite(url: URL(fileURLWithPath: file.path)))
        XCTAssertEqual(try shellFavoriteXattrValue(of: file), "1")
    }

    func testSetFavoriteFailsForMissingPath() {
        let missing = URL(fileURLWithPath: "/nonexistent-clipcap-dir-4f2a/x.png")

        XCTAssertFalse(HistoryManager.setFavorite(true, on: missing))
        XCTAssertFalse(HistoryManager.isFavorite(url: missing))
    }

    func testUnfavoritingAlreadyUnfavoritedFileSucceeds() throws {
        let file = try makeFile(name: "plain.png", contents: Data([0x02]))

        XCTAssertTrue(HistoryManager.setFavorite(false, on: file))
        XCTAssertFalse(HistoryManager.isFavorite(url: file))
    }

    func testFavoriteRoundTrip() throws {
        let file = try makeFile(name: "round-trip.png", contents: Data([0x01]))

        XCTAssertTrue(HistoryManager.setFavorite(true, on: file))
        XCTAssertTrue(HistoryManager.isFavorite(url: file))
        XCTAssertTrue(HistoryManager.setFavorite(false, on: file))
        XCTAssertFalse(HistoryManager.isFavorite(url: file))
        XCTAssertTrue(HistoryManager.setFavorite(true, on: file))
        XCTAssertTrue(HistoryManager.isFavorite(url: file))
    }

    func testDeleteAllPartitionKeepsFavoriteEntries() throws {
        let favorite = try makeFile(name: "favorite.png", contents: Data([0x01]))
        let plain = try makeFile(name: "plain.png", contents: Data([0x02]))
        XCTAssertTrue(HistoryManager.setFavorite(true, on: favorite))

        let decision = HistoryManager.partitionEntriesForRemoval([favorite, plain])

        XCTAssertEqual(decision.kept, [favorite])
        XCTAssertEqual(decision.remove, [plain])
    }

    func testFavoriteFilterIsSecondAfterAll() {
        XCTAssertEqual(Array(HistoryPanelFilter.allCases.prefix(2)), [.all, .favorites])
    }

    func testFavoriteFilterAppearsWithOneFavorite() throws {
        let first = try makeEntry(name: "first.png")
        let second = try makeEntry(name: "second.png")
        let entries = [first, second]

        XCTAssertFalse(HistoryFavoritePolicy.shouldShowFilter(for: entries))
        XCTAssertTrue(HistoryManager.setFavorite(true, on: first.fileURL))
        XCTAssertTrue(HistoryFavoritePolicy.shouldShowFilter(for: entries))
    }

    func testMultiSelectionTargetsAllSelectedEntries() throws {
        let first = try makeEntry(name: "first.png")
        let second = try makeEntry(name: "second.png")
        let clicked = try makeEntry(name: "clicked.png")

        let targets = HistoryFavoritePolicy.toggleTargets(
            clicked: clicked,
            selected: [first, second]
        )

        XCTAssertEqual(targets.map(\.fileURL), [first.fileURL, second.fileURL])
    }

    func testMixedSelectionFavoritesAllBeforeBatchUnfavoriting() throws {
        let first = try makeEntry(name: "first.png")
        let second = try makeEntry(name: "second.png")
        let entries = [first, second]

        XCTAssertTrue(HistoryManager.setFavorite(true, on: first.fileURL))
        XCTAssertTrue(HistoryFavoritePolicy.nextFavoriteState(for: entries))
        XCTAssertTrue(HistoryManager.setFavorite(true, on: second.fileURL))
        XCTAssertFalse(HistoryFavoritePolicy.nextFavoriteState(for: entries))
    }

    func testFavoriteButtonAppearancePolicy() {
        XCTAssertEqual(HistoryFavoriteButton.symbolName(isFavorite: false), "star")
        XCTAssertEqual(HistoryFavoriteButton.symbolName(isFavorite: true), "star.fill")
        XCTAssertEqual(HistoryItemCornerControlMetrics.size, 18)
        XCTAssertEqual(HistoryItemCornerControlMetrics.favoriteSymbolPointSize, 14)
        XCTAssertEqual(HistoryItemCornerControlMetrics.favoritePreviewOverlap, 7)
        XCTAssertFalse(HistoryFavoriteButton.shouldBeVisible(isFavorite: false, isHovered: false))
        XCTAssertTrue(HistoryFavoriteButton.shouldBeVisible(isFavorite: false, isHovered: true))
        XCTAssertTrue(HistoryFavoriteButton.shouldBeVisible(isFavorite: true, isHovered: false))
    }

    private func makeEntry(name: String) throws -> HistoryEntry {
        let url = try makeFile(name: name, contents: Data([0x01]))
        return HistoryEntry(fileURL: url, createdAt: Date(), kind: .image)
    }

    @discardableResult
    private func makeFile(name: String, contents: Data) throws -> URL {
        let url = directoryURL.appendingPathComponent(name)
        try contents.write(to: url)
        return url
    }

    private func shellFavoriteXattrValue(of url: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-p", "com.clipcap.favorite", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
    }
}
