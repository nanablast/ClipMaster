import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ClipMaster

final class MediaFileHelpersTests: XCTestCase {
    func testMediaFileKindClassification() {
        XCTAssertEqual(MediaFileKind.classify(fileExtension: "HEIC"), .image)
        XCTAssertEqual(MediaFileKind.classify(fileExtension: ".gif"), .image)
        XCTAssertEqual(MediaFileKind.classify(fileExtension: "mp4"), .video)
        XCTAssertEqual(MediaFileKind.classify(fileExtension: "mov"), .video)
        XCTAssertEqual(MediaFileKind.classify(fileExtension: "flac"), .audio)
        XCTAssertEqual(MediaFileKind.classify(fileExtension: "pdf"), .other)
    }

    func testMediaFilePresentationSingleAndMultiFileFormats() {
        let singleImage = MediaFilePresentation(content: "/Users/demo/Pictures/cat.png")
        XCTAssertEqual(singleImage.primaryKind, .image)
        XCTAssertEqual(singleImage.singleImageURL?.path, "/Users/demo/Pictures/cat.png")
        XCTAssertEqual(singleImage.displayText, "cat.png — Pictures")
        XCTAssertEqual(singleImage.iconSystemName, "photo.on.rectangle")

        let singleVideo = MediaFilePresentation(content: "/Users/demo/Movies/clip.mov")
        XCTAssertEqual(singleVideo.primaryKind, .video)
        XCTAssertNil(singleVideo.singleImageURL)
        XCTAssertEqual(singleVideo.iconSystemName, "film")

        let multiMedia = MediaFilePresentation(content: "/tmp/a.jpg\n/tmp/b.png")
        XCTAssertNil(multiMedia.singleImageURL)
        XCTAssertEqual(multiMedia.displayText, "a.jpg 等 2 个文件")
        XCTAssertEqual(multiMedia.iconSystemName, "photo.on.rectangle")
    }

    func testThumbnailLoaderDownsamplesLargeImageToRequestedBounds() throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 400,
            height: 200,
            bitsPerComponent: 8,
            bytesPerRow: 400 * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0.9, green: 0.3, blue: 0.1, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        let cgImage = try XCTUnwrap(context.makeImage())

        let output = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(dest, cgImage, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))

        let thumbnail = try XCTUnwrap(ImageThumbnailLoader.loadThumbnail(from: output as Data, maxPixelSize: 96))
        XCTAssertEqual(Int(thumbnail.size.width), 96)
        XCTAssertEqual(Int(thumbnail.size.height), 48)
    }

    func testUniqueDestinationURLPreservesExtensionAndHandlesCollisions() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageSaver-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let first = ImageFileSaver.uniqueDestinationURL(in: tempDir, baseName: "ClipMaster-1", fileExtension: "gif")
        XCTAssertEqual(first.lastPathComponent, "ClipMaster-1.gif")
        try Data([1]).write(to: first)

        let second = ImageFileSaver.uniqueDestinationURL(in: tempDir, baseName: "ClipMaster-1", fileExtension: "gif")
        XCTAssertEqual(second.lastPathComponent, "ClipMaster-1 2.gif")
        try Data([2]).write(to: second)

        let third = ImageFileSaver.uniqueDestinationURL(in: tempDir, baseName: "ClipMaster-1", fileExtension: "gif")
        XCTAssertEqual(third.lastPathComponent, "ClipMaster-1 3.gif")
    }
}
