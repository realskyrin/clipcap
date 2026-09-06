import XCTest
@testable import clipcap

final class TranslationToolbarTests: XCTestCase {
    func testExistingLayoutInsertsTranslationAfterOCR() {
        let old = ToolbarLayout(primary: [.rectangle, .ocr, .undo], side: [.save], hidden: [])
        let updated = old.normalized()
        let ocr = updated.primary.firstIndex(of: .ocr)!
        XCTAssertEqual(updated.primary[ocr + 1], .translate)
        XCTAssertEqual((updated.primary + updated.side + updated.hidden).filter { $0 == .translate }.count, 1)
    }

    func testExplicitlyHiddenTranslationStaysHidden() {
        var layout = ToolbarLayout.default
        layout.primary.removeAll { $0 == .translate }
        layout.hidden = [.translate]
        let updated = layout.normalized()
        XCTAssertTrue(updated.hidden.contains(.translate))
        XCTAssertFalse(updated.primary.contains(.translate))
    }
}
