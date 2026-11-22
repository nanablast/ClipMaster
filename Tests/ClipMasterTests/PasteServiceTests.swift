import XCTest
import AppKit
@testable import ClipMaster

@MainActor
final class PasteServiceTests: XCTestCase {
    func testImageWithoutFileFallsBackToOCRText() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let item = ClipboardItem(
            content: "OCR 内容",
            type: .image,
            imagePath: "missing-file.png"
        )

        let ok = PasteService.writeToPasteboard(item, pasteboard: pasteboard)
        XCTAssertTrue(ok)
        XCTAssertEqual(pasteboard.string(forType: .string), "OCR 内容")
        XCTAssertTrue(pasteboard.types?.contains(ClipboardPasteboardTypes.historyReplay) == true)
    }

    func testImagePlaceholderWithoutFileDoesNotOverwritePasteboard() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
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

    func testHistoryReplayIsIgnoredByClipboardReader() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(PasteService.writeToPasteboard(ClipboardItem(content: "history", type: .text), pasteboard: pasteboard))
        let reader = PasteboardSnapshotReader(pasteboard: pasteboard)
        guard case .ignored = reader.readSnapshot(expectedChangeCount: pasteboard.changeCount) else {
            return XCTFail("Replayed history should not be collected again")
        }
    }

    func testPlainTextReplayAlsoCarriesMarkerAndPreservesWhitespace() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let item = ClipboardItem(content: "  OCR text\n", type: .image)
        XCTAssertTrue(PasteService.writePlainTextToPasteboard(item, pasteboard: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), item.content)
        XCTAssertTrue(pasteboard.types?.contains(ClipboardPasteboardTypes.historyReplay) == true)
    }

    func testAllFilesAreWrittenAndEveryItemIsMarked() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let item = ClipboardItem(content: "/tmp/first image.png\n/tmp/second.png", type: .file)
        XCTAssertTrue(PasteService.writeToPasteboard(item, pasteboard: pasteboard))
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL]
        XCTAssertEqual(urls?.map(\.path), ["/tmp/first image.png", "/tmp/second.png"])
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 2)
        XCTAssertTrue(pasteboard.pasteboardItems?.allSatisfy {
            $0.types.contains(ClipboardPasteboardTypes.historyReplay)
        } == true)
    }

    func testValidateFileExistenceRejectsMissingFileAndAcceptsExistingFile() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteServiceExists-\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: tempFile)

        let item = ClipboardItem(content: tempFile.path, type: .file)
        XCTAssertTrue(PasteService.writeToPasteboard(item, pasteboard: pasteboard, validateFileExistence: true))

        try FileManager.default.removeItem(at: tempFile)
        XCTAssertFalse(PasteService.writeToPasteboard(item, pasteboard: pasteboard, validateFileExistence: true))
        XCTAssertTrue(PasteService.writeToPasteboard(item, pasteboard: pasteboard, validateFileExistence: false))
    }

    func testGIFAndPNGImageReplayIncludeTIFFFallback() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteServiceStorage-\(UUID().uuidString)", isDirectory: true)
        let imageDir = tempDir.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: imageDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storage = try StorageService(
            databasePath: tempDir.appendingPathComponent("test.sqlite").path,
            imageCacheDir: imageDir
        )

        let gifImage = NSImage(size: NSSize(width: 4, height: 4))
        gifImage.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        gifImage.unlockFocus()
        let rep = try XCTUnwrap(gifImage.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) })
        let gifData = try XCTUnwrap(rep.representation(using: .gif, properties: [:]))
        let pngData = try XCTUnwrap(rep.representation(using: .png, properties: [:]))

        let gifID = UUID()
        let gifPath = try XCTUnwrap(storage.saveImageFile(gifData, id: gifID, fileExtension: "gif"))
        let gifItem = ClipboardItem(id: gifID, content: "GIF", type: .image, imagePath: gifPath)

        let pngID = UUID()
        let pngPath = try XCTUnwrap(storage.saveImageFile(pngData, id: pngID, fileExtension: "png"))
        let pngItem = ClipboardItem(id: pngID, content: "PNG", type: .image, imagePath: pngPath)

        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        XCTAssertTrue(PasteService.writeToPasteboard(gifItem, pasteboard: pasteboard, storage: storage))
        let gifPBItem = try XCTUnwrap(pasteboard.pasteboardItems?.first)
        XCTAssertEqual(gifPBItem.data(forType: ClipboardPasteboardTypes.gif), gifData)
        XCTAssertNotNil(gifPBItem.data(forType: .tiff))
        XCTAssertTrue(gifPBItem.types.contains(ClipboardPasteboardTypes.historyReplay))

        XCTAssertTrue(PasteService.writeToPasteboard(pngItem, pasteboard: pasteboard, storage: storage))
        let pngPBItem = try XCTUnwrap(pasteboard.pasteboardItems?.first)
        XCTAssertEqual(pngPBItem.data(forType: .png), pngData)
        XCTAssertNotNil(pngPBItem.data(forType: .tiff))
        XCTAssertTrue(pngPBItem.types.contains(ClipboardPasteboardTypes.historyReplay))
    }
}
