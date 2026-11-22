import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ClipMaster

final class ClipboardSnapshotProcessorTests: XCTestCase {
    func testLinkKeepsOriginalContentSourceAndCaptureTime() throws {
        let date = Date(timeIntervalSince1970: 123)
        let snapshot = ClipboardSnapshot(capturedAt: date, appSource: "Safari", stringContent: " https://example.com ")
        let prepared = try XCTUnwrap(ClipboardSnapshotProcessor().prepare(snapshot))
        XCTAssertEqual(prepared.item.content, " https://example.com ")
        XCTAssertEqual(prepared.item.type, .link)
        XCTAssertEqual(prepared.item.appSource, "Safari")
        XCTAssertEqual(prepared.item.createdAt, date)
    }

    func testMultipleImageFilesRemainAnEntireFileSelection() throws {
        let urls = [URL(fileURLWithPath: "/tmp/a.png"), URL(fileURLWithPath: "/tmp/b.jpg")]
        let snapshot = ClipboardSnapshot(fileURLs: urls)
        let processor = ClipboardSnapshotProcessor(recognizeText: { _ in
            XCTFail("A multi-file selection should not become a single OCR image")
            return ""
        })
        let prepared = try XCTUnwrap(processor.prepare(snapshot))
        XCTAssertEqual(prepared.item.type, .file)
        XCTAssertEqual(prepared.item.content, "/tmp/a.png\n/tmp/b.jpg")
        XCTAssertNil(prepared.imageData)
    }

    func testPNGIsRetainedAndOCRKeepsCopyTimestamp() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 8, bitsPerPixel: 32
        ))
        bitmap.bitmapData?.initialize(repeating: 255, count: 16)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let date = Date(timeIntervalSince1970: 456)
        let processor = ClipboardSnapshotProcessor(recognizeText: { data in
            XCTAssertEqual(data, png)
            return "recognized text"
        })
        let prepared = try XCTUnwrap(processor.prepare(ClipboardSnapshot(capturedAt: date, rawImageData: png)))
        XCTAssertEqual(prepared.imageData, png)
        XCTAssertEqual(prepared.item.type, .image)
        XCTAssertEqual(prepared.item.content, "recognized text")
        XCTAssertEqual(prepared.item.createdAt, date)
        XCTAssertNotNil(prepared.item.imageHash)
    }

    func testInvalidImageFallsBackToAvailableText() throws {
        let snapshot = ClipboardSnapshot(rawImageData: Data([1, 2, 3]), stringContent: "fallback")
        let prepared = try XCTUnwrap(ClipboardSnapshotProcessor().prepare(snapshot))
        XCTAssertEqual(prepared.item.type, .text)
        XCTAssertEqual(prepared.item.content, "fallback")
        XCTAssertNil(prepared.imageData)
    }

    func testImageWriteFailureDoesNotCreateBrokenHistoryRow() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let blockedCache = root.appendingPathComponent("images")
        try Data([0]).write(to: blockedCache)
        let storage = try StorageService(databasePath: root.appendingPathComponent("test.sqlite").path, imageCacheDir: blockedCache)
        let prepared = PreparedClipboardItem(
            item: ClipboardItem(content: "ocr", type: .image), imageData: Data([1, 2, 3])
        )
        XCTAssertThrowsError(try prepared.persist(using: storage))
        XCTAssertEqual(try storage.totalCount(), 0)
    }

    func testFailedDatabaseInsertRemovesNewImageFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try StorageService(
            databasePath: root.appendingPathComponent("test.sqlite").path,
            imageCacheDir: root.appendingPathComponent("images", isDirectory: true)
        )
        let existing = ClipboardItem(content: "existing", type: .text)
        try storage.insert(existing)
        let prepared = PreparedClipboardItem(
            item: ClipboardItem(id: existing.id, content: "new image", type: .image),
            imageData: Data([1, 2, 3])
        )
        XCTAssertThrowsError(try prepared.persist(using: storage))
        XCTAssertNil(storage.loadImageData(filename: "\(existing.id.uuidString).png"))
        XCTAssertEqual(try storage.fetchAll().map(\.content), ["existing"])
    }

    func testSingleImageFileRemainsFileItem() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipMasterProcessorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let imageURL = tempDir.appendingPathComponent("photo.png")
        try makePNGData(width: 10, height: 10).write(to: imageURL)

        let processor = ClipboardSnapshotProcessor(recognizeText: { _ in "" })
        let snapshot = ClipboardSnapshot(appSource: "Finder", fileURLs: [imageURL])
        let prepared = try XCTUnwrap(processor.prepare(snapshot))

        XCTAssertEqual(prepared.item.type, .file)
        XCTAssertEqual(prepared.item.content, imageURL.path)
        XCTAssertNil(prepared.imageData)
    }

    func testMultiFrameGIFRemainsAnimatedGIF() throws {
        let gifData = try makeAnimatedGIFData(width: 8, height: 8, frameCount: 2)
        let processor = ClipboardSnapshotProcessor(recognizeText: { _ in "" })
        let snapshot = ClipboardSnapshot(appSource: "Safari", rawImageData: gifData)
        let prepared = try XCTUnwrap(processor.prepare(snapshot))

        XCTAssertEqual(prepared.item.type, .image)
        XCTAssertEqual(prepared.imageFileExtension, "gif")
        XCTAssertEqual(prepared.imageData, gifData)
    }

    func testOrientedImageHasOrientationBakedToUprightPNG() throws {
        // Build a 16x8 landscape buffer tagged EXIF Orientation 6 (90° CW -> portrait 8x16 upright)
        let jpegData = try makeOrientedJPEGData(width: 16, height: 8, exifOrientation: 6)
        let processor = ClipboardSnapshotProcessor(recognizeText: { _ in "" })
        let snapshot = ClipboardSnapshot(appSource: "Preview", rawImageData: jpegData)
        let prepared = try XCTUnwrap(processor.prepare(snapshot))

        XCTAssertEqual(prepared.item.type, .image)
        XCTAssertEqual(prepared.imageFileExtension, "png")
        let normalizedData = try XCTUnwrap(prepared.imageData)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(normalizedData as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.png.identifier)

        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        XCTAssertEqual(props?[kCGImagePropertyPixelWidth as String] as? Int, 8)
        XCTAssertEqual(props?[kCGImagePropertyPixelHeight as String] as? Int, 16)
        let resultingOrientation = props?[kCGImagePropertyOrientation as String] as? Int ?? 1
        XCTAssertEqual(resultingOrientation, 1)
    }

    private func makeSolidCGImage(width: Int, height: Int) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "ClipboardSnapshotProcessorTests", code: 1)
        }
        context.setFillColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func makePNGData(width: Int, height: Int) throws -> Data {
        let cgImage = try makeSolidCGImage(width: width, height: height)
        let output = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(dest, cgImage, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return output as Data
    }

    private func makeAnimatedGIFData(width: Int, height: Int, frameCount: Int) throws -> Data {
        let output = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(
            output, UTType.gif.identifier as CFString, frameCount, nil
        ))
        let gifProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ]
        CGImageDestinationSetProperties(dest, gifProperties as CFDictionary)
        let frameProps: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]
        ]
        let frameImage = try makeSolidCGImage(width: width, height: height)
        for _ in 0..<frameCount {
            CGImageDestinationAddImage(dest, frameImage, frameProps as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return output as Data
    }

    private func makeOrientedJPEGData(width: Int, height: Int, exifOrientation: Int) throws -> Data {
        let cgImage = try makeSolidCGImage(width: width, height: height)
        let output = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ))
        let props: [CFString: Any] = [kCGImagePropertyOrientation: exifOrientation]
        CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return output as Data
    }
}
