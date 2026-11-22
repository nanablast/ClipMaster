import XCTest
@testable import ClipMaster

final class ClipboardSnapshotBufferTests: XCTestCase {
    func testPreservesCopyOrderAndReleasesPayloadBudget() {
        var buffer = ClipboardSnapshotBuffer(countLimit: 3, byteLimit: 100)
        _ = buffer.append(ClipboardSnapshot(stringContent: "first"))
        _ = buffer.append(ClipboardSnapshot(stringContent: "second"))
        XCTAssertEqual(buffer.popFirst()?.stringContent, "first")
        XCTAssertEqual(buffer.byteCount, 6)
        XCTAssertEqual(buffer.popFirst()?.stringContent, "second")
        XCTAssertEqual(buffer.byteCount, 0)
        XCTAssertNil(buffer.popFirst())
    }

    func testCountOverflowKeepsNewestPendingCopies() {
        var buffer = ClipboardSnapshotBuffer(countLimit: 2, byteLimit: 100)
        _ = buffer.append(ClipboardSnapshot(stringContent: "A"))
        _ = buffer.append(ClipboardSnapshot(stringContent: "B"))
        let result = buffer.append(ClipboardSnapshot(stringContent: "C"))
        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.droppedCount, 1)
        XCTAssertEqual(buffer.popFirst()?.stringContent, "B")
        XCTAssertEqual(buffer.popFirst()?.stringContent, "C")
    }

    func testByteLimitIncludesUTF8TextAndImageData() {
        var buffer = ClipboardSnapshotBuffer(countLimit: 10, byteLimit: 10)
        _ = buffer.append(ClipboardSnapshot(stringContent: "中文"))
        let result = buffer.append(ClipboardSnapshot(rawImageData: Data(repeating: 1, count: 5)))
        XCTAssertEqual(result.droppedCount, 1)
        XCTAssertEqual(buffer.count, 1)
        XCTAssertEqual(buffer.byteCount, 5)
    }

    func testOversizedSnapshotDoesNotEvictUsableCopies() {
        var buffer = ClipboardSnapshotBuffer(countLimit: 2, byteLimit: 10)
        _ = buffer.append(ClipboardSnapshot(stringContent: "keep"))
        let result = buffer.append(ClipboardSnapshot(rawImageData: Data(repeating: 0, count: 11)))
        XCTAssertFalse(result.accepted)
        XCTAssertEqual(result.droppedCount, 0)
        XCTAssertEqual(buffer.popFirst()?.stringContent, "keep")
    }

    func testClearReleasesAllPendingPayloads() {
        var buffer = ClipboardSnapshotBuffer(countLimit: 2, byteLimit: 100)
        _ = buffer.append(ClipboardSnapshot(stringContent: "pending"))
        buffer.removeAll()
        XCTAssertEqual(buffer.count, 0)
        XCTAssertEqual(buffer.byteCount, 0)
        XCTAssertNil(buffer.popFirst())
    }
}
