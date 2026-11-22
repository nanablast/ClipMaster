import AppKit
import XCTest
@testable import ClipMaster

@MainActor
final class PasteboardSnapshotReaderTests: XCTestCase {
    func testSnapshotRetainsContentSourceAndCaptureTimeAfterClipboardChanges() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("first", forType: .string)
        let date = Date(timeIntervalSince1970: 123)
        let reader = PasteboardSnapshotReader(pasteboard: pasteboard, sourceApplication: { "TestApp" }, now: { date })

        guard case .captured(let snapshot) = reader.readSnapshot(expectedChangeCount: pasteboard.changeCount) else {
            return XCTFail("Expected a text snapshot")
        }
        pasteboard.clearContents()
        pasteboard.setString("second", forType: .string)
        XCTAssertEqual(snapshot.stringContent, "first")
        XCTAssertEqual(snapshot.appSource, "TestApp")
        XCTAssertEqual(snapshot.capturedAt, date)
    }

    func testSensitiveTransientAndReplayTypesAreIgnored() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let reader = PasteboardSnapshotReader(pasteboard: pasteboard)
        for type in ClipboardPasteboardTypes.ignored {
            let item = NSPasteboardItem()
            item.setString("sensitive", forType: .string)
            item.setString("", forType: type)
            pasteboard.clearContents()
            XCTAssertTrue(pasteboard.writeObjects([item]))
            guard case .ignored = reader.readSnapshot(expectedChangeCount: pasteboard.changeCount) else {
                return XCTFail("Unexpectedly captured \(type.rawValue)")
            }
        }
    }

    func testPNGIsPreferredOverTIFF() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let png = Data([1, 2, 3])
        pasteboard.setData(png, forType: .png)
        pasteboard.setData(Data([4, 5, 6]), forType: .tiff)
        let reader = PasteboardSnapshotReader(pasteboard: pasteboard)
        guard case .captured(let snapshot) = reader.readSnapshot(expectedChangeCount: pasteboard.changeCount) else {
            return XCTFail("Expected image data")
        }
        XCTAssertEqual(snapshot.rawImageData, png)
    }

    func testFileCopyDoesNotCaptureFinderIcon() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let urls = [URL(fileURLWithPath: "/tmp/first.png"), URL(fileURLWithPath: "/tmp/second.png")]
        XCTAssertTrue(pasteboard.writeObjects(urls as [NSURL]))
        pasteboard.setData(Data([1, 2, 3]), forType: .tiff)
        let reader = PasteboardSnapshotReader(pasteboard: pasteboard)
        guard case .captured(let snapshot) = reader.readSnapshot(expectedChangeCount: pasteboard.changeCount) else {
            return XCTFail("Expected file URLs")
        }
        XCTAssertEqual(snapshot.fileURLs, urls)
        XCTAssertNil(snapshot.rawImageData)
    }

    func testEmptyPasteboardAndOutdatedChangeCountCanBeRetried() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let reader = PasteboardSnapshotReader(pasteboard: pasteboard)
        guard case .retry = reader.readSnapshot(expectedChangeCount: pasteboard.changeCount) else {
            return XCTFail("An empty declaration should be retried")
        }
        guard case .retry = reader.readSnapshot(expectedChangeCount: pasteboard.changeCount - 1) else {
            return XCTFail("A changed owner should be retried")
        }
    }

    func testGIFIsPreferredOverFallbackTIFF() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        let gifBytes = Data("GIF89a-dummy".utf8)
        let tiffBytes = Data("TIFF-dummy".utf8)
        let item = NSPasteboardItem()
        XCTAssertTrue(item.setData(tiffBytes, forType: .tiff))
        XCTAssertTrue(item.setData(gifBytes, forType: ClipboardPasteboardTypes.gif))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([item]))

        let reader = PasteboardSnapshotReader(pasteboard: pasteboard)
        guard case .captured(let snapshot) = reader.readSnapshot(expectedChangeCount: pasteboard.changeCount) else {
            return XCTFail("Expected GIF snapshot to be captured")
        }

        XCTAssertEqual(snapshot.rawImageData, gifBytes)
    }

    func testJPEGAndWebPAreCaptured() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let reader = PasteboardSnapshotReader(pasteboard: pasteboard)

        for (type, payload) in [
            (ClipboardPasteboardTypes.jpeg, Data("jpeg-bytes".utf8)),
            (ClipboardPasteboardTypes.webp, Data("webp-bytes".utf8))
        ] {
            let item = NSPasteboardItem()
            XCTAssertTrue(item.setData(payload, forType: type))
            pasteboard.clearContents()
            XCTAssertTrue(pasteboard.writeObjects([item]))

            guard case .captured(let snapshot) = reader.readSnapshot(expectedChangeCount: pasteboard.changeCount) else {
                return XCTFail("Expected \(type.rawValue) snapshot to be captured")
            }
            XCTAssertEqual(snapshot.rawImageData, payload)
        }
    }
}
