import XCTest
@testable import ClipMaster

final class PermissionPromptPolicyTests: XCTestCase {
    func testShouldPromptWhenNeverPrompted() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(
            PermissionPromptPolicy.shouldPrompt(
                now: now,
                lastPromptAt: nil,
                minimumInterval: 60
            )
        )
    }

    func testShouldNotPromptBeforeIntervalElapsed() {
        let last = Date(timeIntervalSince1970: 1_000)
        let now = Date(timeIntervalSince1970: 1_030)
        XCTAssertFalse(
            PermissionPromptPolicy.shouldPrompt(
                now: now,
                lastPromptAt: last,
                minimumInterval: 60
            )
        )
    }

    func testShouldPromptWhenIntervalElapsed() {
        let last = Date(timeIntervalSince1970: 1_000)
        let now = Date(timeIntervalSince1970: 1_060)
        XCTAssertTrue(
            PermissionPromptPolicy.shouldPrompt(
                now: now,
                lastPromptAt: last,
                minimumInterval: 60
            )
        )
    }
}
