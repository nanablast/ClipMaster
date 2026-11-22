import AppKit
import Combine
import XCTest
@testable import ClipMaster

private final class StubClipboardReader: ClipboardSnapshotReading {
    var changeCount = 0
    var result: ClipboardSnapshotReadResult = .ignored
    var readCounts: [Int] = []
    var onRead: ((Int) -> ClipboardSnapshotReadResult)?

    func copy(_ content: String, at date: Date = Date()) {
        changeCount += 1
        result = .captured(ClipboardSnapshot(capturedAt: date, stringContent: content))
    }

    func readSnapshot(expectedChangeCount: Int) -> ClipboardSnapshotReadResult {
        readCounts.append(expectedChangeCount)
        return onRead?(expectedChangeCount) ?? result
    }
}

private final class ClipboardTestStore {
    private let lock = NSLock()
    private var items: [ClipboardItem] = []

    func save(_ prepared: PreparedClipboardItem) -> ClipboardItem {
        lock.lock()
        defer { lock.unlock() }
        items.append(prepared.item)
        return prepared.item
    }

    var savedItems: [ClipboardItem] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}

private func prepareTestCopy(_ snapshot: ClipboardSnapshot) -> PreparedClipboardItem? {
    guard let text = snapshot.stringContent else { return nil }
    return PreparedClipboardItem(item: ClipboardItem(
        content: text, type: .text, appSource: snapshot.appSource, createdAt: snapshot.capturedAt
    ))
}

@MainActor
final class ClipboardMonitorTests: XCTestCase {
    private func makeMonitor(
        reader: StubClipboardReader,
        store: ClipboardTestStore,
        center: NotificationCenter = NotificationCenter(),
        automaticallyPoll: Bool = false,
        prepare: @escaping (ClipboardSnapshot) -> PreparedClipboardItem? = prepareTestCopy,
        persist: ((PreparedClipboardItem) throws -> ClipboardItem)? = nil
    ) -> ClipboardMonitor {
        ClipboardMonitor(
            reader: reader,
            notificationCenter: center,
            automaticallyPoll: automaticallyPoll,
            userIdleDuration: { 0 },
            prepare: prepare,
            persist: persist ?? store.save,
            didCopy: {}
        )
    }

    func testCopiesDuringSlowProcessingKeepEveryCapturedSnapshotInOrder() async {
        let reader = StubClipboardReader()
        let store = ClipboardTestStore()
        let started = expectation(description: "Slow image processing started")
        let release = DispatchSemaphore(value: 0)
        let monitor = makeMonitor(reader: reader, store: store, prepare: { snapshot in
            if snapshot.stringContent == "A" {
                started.fulfill()
                XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
            }
            return prepareTestCopy(snapshot)
        })
        defer { release.signal(); monitor.stop() }
        let published = expectation(description: "All copies published")
        published.expectedFulfillmentCount = 3
        let subscription = monitor.$latestItem.compactMap { $0 }.sink { _ in published.fulfill() }
        defer { subscription.cancel() }

        monitor.start()
        reader.copy("A", at: Date(timeIntervalSince1970: 1))
        monitor.checkForChanges()
        await fulfillment(of: [started], timeout: 2)
        reader.copy("B", at: Date(timeIntervalSince1970: 2))
        monitor.checkForChanges()
        reader.copy("C", at: Date(timeIntervalSince1970: 3))
        monitor.checkForChanges()
        XCTAssertEqual(reader.readCounts.count, 3)
        release.signal()
        await fulfillment(of: [published], timeout: 3)

        XCTAssertEqual(store.savedItems.map(\.content), ["A", "B", "C"])
        XCTAssertEqual(store.savedItems.map(\.createdAt), [1, 2, 3].map { Date(timeIntervalSince1970: Double($0)) })
        XCTAssertEqual(monitor.latestItem?.content, "C")
    }

    func testStopAndRestartDiscardOldWorkWithoutLosingNewSessionCopies() async {
        let reader = StubClipboardReader()
        let store = ClipboardTestStore()
        let started = expectation(description: "Old processing started")
        let release = DispatchSemaphore(value: 0)
        let monitor = makeMonitor(reader: reader, store: store, prepare: { snapshot in
            if snapshot.stringContent == "old in flight" {
                started.fulfill()
                XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
            }
            return prepareTestCopy(snapshot)
        })
        defer { release.signal(); monitor.stop() }
        let published = expectation(description: "New session published")
        let subscription = monitor.$latestItem.compactMap { $0 }.sink { item in
            XCTAssertEqual(item.content, "new session")
            published.fulfill()
        }
        defer { subscription.cancel() }

        monitor.start()
        reader.copy("old in flight")
        monitor.checkForChanges()
        await fulfillment(of: [started], timeout: 2)
        reader.copy("old queued")
        monitor.checkForChanges()
        monitor.stop()
        monitor.start()
        reader.copy("new session")
        monitor.checkForChanges()
        release.signal()
        await fulfillment(of: [published], timeout: 3)
        XCTAssertEqual(store.savedItems.map(\.content), ["new session"])
    }

    func testUnavailableDataIsRetriedWithoutRequiringAnotherChangeCount() async {
        let reader = StubClipboardReader()
        let store = ClipboardTestStore()
        let monitor = makeMonitor(reader: reader, store: store)
        defer { monitor.stop() }
        let published = expectation(description: "Delayed data published")
        let subscription = monitor.$latestItem.compactMap { $0 }.sink { _ in published.fulfill() }
        defer { subscription.cancel() }
        monitor.start()

        reader.changeCount = 1
        reader.result = .retry
        monitor.checkForChanges()
        reader.result = .captured(ClipboardSnapshot(stringContent: "delayed"))
        monitor.checkForChanges()
        await fulfillment(of: [published], timeout: 2)
        XCTAssertEqual(store.savedItems.map(\.content), ["delayed"])
        XCTAssertEqual(reader.readCounts, [1, 1])
    }

    func testUnreadableDataHasBoundedRetriesAndDoesNotBlockNextCopy() async {
        let reader = StubClipboardReader()
        let store = ClipboardTestStore()
        let monitor = makeMonitor(reader: reader, store: store)
        defer { monitor.stop() }
        let published = expectation(description: "Next copy published")
        let subscription = monitor.$latestItem.compactMap { $0 }.sink { _ in published.fulfill() }
        defer { subscription.cancel() }
        monitor.start()
        reader.changeCount = 1
        reader.result = .retry
        for _ in 0..<(Constants.clipboardReadAttemptLimit + 3) { monitor.checkForChanges() }
        XCTAssertEqual(reader.readCounts.count, Constants.clipboardReadAttemptLimit)
        reader.copy("next")
        monitor.checkForChanges()
        await fulfillment(of: [published], timeout: 2)
        XCTAssertEqual(store.savedItems.map(\.content), ["next"])
    }

    func testClipboardChangingDuringReadRetriesLatestVersion() async {
        let reader = StubClipboardReader()
        let store = ClipboardTestStore()
        let monitor = makeMonitor(reader: reader, store: store)
        defer { monitor.stop() }
        let published = expectation(description: "Stable version published")
        let subscription = monitor.$latestItem.compactMap { $0 }.sink { _ in published.fulfill() }
        defer { subscription.cancel() }
        monitor.start()
        reader.copy("racing")
        reader.onRead = { count in
            if count == 1 {
                reader.copy("stable")
                return .retry
            }
            return reader.result
        }
        monitor.checkForChanges()
        await fulfillment(of: [published], timeout: 2)
        reader.onRead = nil
        XCTAssertEqual(store.savedItems.map(\.content), ["stable"])
        XCTAssertEqual(reader.readCounts, [1, 2])
    }

    func testIgnoredCopyIsNotRetriedOnEveryTick() {
        let reader = StubClipboardReader()
        let store = ClipboardTestStore()
        let monitor = makeMonitor(reader: reader, store: store)
        defer { monitor.stop() }
        monitor.start()
        reader.changeCount = 1
        reader.result = .ignored
        for _ in 0..<10 { monitor.checkForChanges() }
        XCTAssertEqual(reader.readCounts, [1])
        XCTAssertTrue(store.savedItems.isEmpty)
    }

    func testWakeWaitsForAllSuspensionReasonsAndChecksMissedChangeImmediately() async {
        let reader = StubClipboardReader()
        let store = ClipboardTestStore()
        let center = NotificationCenter()
        let monitor = makeMonitor(reader: reader, store: store, center: center)
        defer { monitor.stop() }
        let published = expectation(description: "Copy made during suspension published")
        let subscription = monitor.$latestItem.compactMap { $0 }.sink { _ in published.fulfill() }
        defer { subscription.cancel() }
        monitor.start()
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        center.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        reader.copy("while suspended")
        monitor.checkForChanges()
        XCTAssertTrue(reader.readCounts.isEmpty)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        monitor.checkForChanges()
        XCTAssertTrue(reader.readCounts.isEmpty)
        center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        await fulfillment(of: [published], timeout: 2)
        XCTAssertEqual(store.savedItems.map(\.content), ["while suspended"])

        monitor.stop()
        reader.copy("after stop")
        center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        monitor.checkForChanges()
        XCTAssertEqual(reader.readCounts.count, 1)
    }

    func testPersistenceFailureDoesNotStallFollowingCopies() async {
        enum TestError: Error { case failedWrite }
        let reader = StubClipboardReader()
        let store = ClipboardTestStore()
        let monitor = makeMonitor(reader: reader, store: store, persist: { prepared in
            if prepared.item.content == "bad" { throw TestError.failedWrite }
            return store.save(prepared)
        })
        defer { monitor.stop() }
        let published = expectation(description: "Following copy published")
        let subscription = monitor.$latestItem.compactMap { $0 }.sink { _ in published.fulfill() }
        defer { subscription.cancel() }
        monitor.start()
        reader.copy("bad")
        monitor.checkForChanges()
        reader.copy("good")
        monitor.checkForChanges()
        await fulfillment(of: [published], timeout: 2)
        XCTAssertEqual(store.savedItems.map(\.content), ["good"])
    }

    func testTimerCapturesWithoutManualPolling() async {
        let reader = StubClipboardReader()
        let store = ClipboardTestStore()
        let monitor = makeMonitor(reader: reader, store: store, automaticallyPoll: true)
        defer { monitor.stop() }
        let published = expectation(description: "Timer captured copy")
        let subscription = monitor.$latestItem.compactMap { $0 }.sink { _ in published.fulfill() }
        defer { subscription.cancel() }
        monitor.start()
        reader.copy("timer")
        await fulfillment(of: [published], timeout: 2)
        XCTAssertEqual(store.savedItems.map(\.content), ["timer"])
    }
}
