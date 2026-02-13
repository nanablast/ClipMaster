import XCTest
@testable import ClipMaster

final class SystemPermissionServiceTests: XCTestCase {
    func testSnapshotReflectsInjectedProviders() {
        let snapshot = SystemPermissionService.snapshot(
            accessibilityProvider: { true },
            screenCaptureProvider: { false }
        )
        XCTAssertEqual(snapshot.accessibilityGranted, true)
        XCTAssertEqual(snapshot.screenCaptureGranted, false)
    }

    func testSnapshotReflectsAllGranted() {
        let snapshot = SystemPermissionService.snapshot(
            accessibilityProvider: { true },
            screenCaptureProvider: { true }
        )
        XCTAssertEqual(snapshot, .init(accessibilityGranted: true, screenCaptureGranted: true))
    }
}
