import XCTest
import AppKit
@testable import ClipMaster

@MainActor
final class PasteServiceTests: XCTestCase {
    func testImageWithoutFileFallsBackToOCRText() {
        let pasteboard = NSPasteboard.withUniqueName()
        let item = ClipboardItem(
            content: "OCR 内容",
            type: .image,
            imagePath: "missing-file.png"
        )

        let ok = PasteService.writeToPasteboard(item, pasteboard: pasteboard)
        XCTAssertTrue(ok)
        XCTAssertEqual(pasteboard.string(forType: .string), "OCR 内容")
    }

    func testImagePlaceholderWithoutFileDoesNotOverwritePasteboard() {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        pasteboard.setString("sentinel", forType: .string)

        let item = ClipboardItem(
            content: Constants.imagePlaceholderText,
            type: .image,
            imagePath: "missing-file.png"
        )

        let ok = PasteService.writeToPasteboard(item, pasteboard: pasteboard)
        XCTAssertFalse(ok)
        XCTAssertEqual(pasteboard.string(forType: .string), "sentinel")
    }
}
