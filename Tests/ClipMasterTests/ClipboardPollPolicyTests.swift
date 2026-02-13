import XCTest
@testable import ClipMaster

final class ClipboardPollPolicyTests: XCTestCase {
    func testPolicyStartsActive() {
        let policy = ClipboardPollPolicy()
        XCTAssertEqual(policy.interval, Constants.clipboardPollActiveInterval, accuracy: 0.0001)
        XCTAssertEqual(policy.noChangeStreak, 0)
    }

    func testNoChangeBacksOffToIdleInterval() {
        var policy = ClipboardPollPolicy()
        for _ in 0..<(Constants.clipboardIdleThreshold - 1) {
            XCTAssertFalse(policy.recordNoChange())
        }
        XCTAssertTrue(policy.recordNoChange())
        XCTAssertEqual(policy.interval, Constants.clipboardPollIdleInterval, accuracy: 0.0001)
    }

    func testChangeReturnsToActiveInterval() {
        var policy = ClipboardPollPolicy()
        for _ in 0..<Constants.clipboardIdleThreshold {
            _ = policy.recordNoChange()
        }
        XCTAssertTrue(policy.recordChange())
        XCTAssertEqual(policy.interval, Constants.clipboardPollActiveInterval, accuracy: 0.0001)
        XCTAssertEqual(policy.noChangeStreak, 0)
    }
}
