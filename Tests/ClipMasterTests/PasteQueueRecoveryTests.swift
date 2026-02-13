import XCTest
@testable import ClipMaster

final class PasteQueueRecoveryTests: XCTestCase {
    func testRecoveryResultWhenInactiveIsNoAction() {
        XCTAssertEqual(
            PasteQueue.recoveryResult(isActive: false, reenabled: false),
            .noAction
        )
        XCTAssertEqual(
            PasteQueue.recoveryResult(isActive: false, reenabled: true),
            .noAction
        )
    }

    func testRecoveryResultWhenActiveAndReenabled() {
        XCTAssertEqual(
            PasteQueue.recoveryResult(isActive: true, reenabled: true),
            .reenabled
        )
    }

    func testRecoveryResultWhenActiveAndReenableFails() {
        XCTAssertEqual(
            PasteQueue.recoveryResult(isActive: true, reenabled: false),
            .shouldStop
        )
    }
}
