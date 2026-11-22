import XCTest
@testable import ClipMaster

final class ClipboardPollPolicyTests: XCTestCase {
    func testPolicyStartsActive() {
        let policy = ClipboardPollPolicy(now: 0)
        XCTAssertEqual(policy.interval, Constants.clipboardPollActiveInterval, accuracy: 0.0001)
    }

    func testNoCopiesDoesNotSlowPollingWhileUserIsActive() {
        var policy = ClipboardPollPolicy(now: 0)
        for second in 0..<3_600 {
            XCTAssertFalse(policy.recordPoll(hasChanges: false, userIdleDuration: 1, now: Double(second)))
        }
        XCTAssertEqual(policy.interval, Constants.clipboardPollActiveInterval, accuracy: 0.0001)
    }

    func testBackoffRequiresBothUserAndClipboardToBeIdle() {
        var policy = ClipboardPollPolicy(now: 0)
        let delay = Constants.clipboardIdleDelay
        XCTAssertFalse(policy.recordPoll(hasChanges: false, userIdleDuration: delay, now: delay - 1))
        XCTAssertFalse(policy.recordPoll(hasChanges: false, userIdleDuration: delay - 1, now: delay))
        XCTAssertTrue(policy.recordPoll(hasChanges: false, userIdleDuration: delay, now: delay))
        XCTAssertEqual(policy.interval, Constants.clipboardPollIdleInterval, accuracy: 0.0001)
    }

    func testCopyReturnsToActiveAndKeepsRapidPollingForSubsequentCopies() {
        var policy = ClipboardPollPolicy(now: 0)
        _ = policy.recordPoll(hasChanges: false, userIdleDuration: 600, now: 600)
        XCTAssertTrue(policy.recordPoll(hasChanges: true, userIdleDuration: 601, now: 601))
        XCTAssertFalse(policy.recordPoll(hasChanges: false, userIdleDuration: 603, now: 603))
        XCTAssertEqual(policy.interval, Constants.clipboardPollActiveInterval, accuracy: 0.0001)
    }

    func testUserActivityReturnsToActiveWithoutAnotherCopy() {
        var policy = ClipboardPollPolicy(now: 0)
        _ = policy.recordPoll(hasChanges: false, userIdleDuration: 600, now: 600)
        XCTAssertTrue(policy.recordPoll(hasChanges: false, userIdleDuration: 0, now: 601))
        XCTAssertEqual(policy.interval, Constants.clipboardPollActiveInterval, accuracy: 0.0001)
    }

    func testInvalidIdleReadingsKeepPollingActive() {
        for idle in [TimeInterval.nan, .infinity, -1] {
            var policy = ClipboardPollPolicy(now: 0)
            _ = policy.recordPoll(hasChanges: false, userIdleDuration: idle, now: 600)
            XCTAssertEqual(policy.interval, Constants.clipboardPollActiveInterval, accuracy: 0.0001)
        }
    }
}
