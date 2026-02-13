import XCTest
@testable import ClipMaster

final class ConstantsTests: XCTestCase {
    func testNormalizedMaxHistoryCountClampsRange() {
        XCTAssertEqual(
            Constants.normalizedMaxHistoryCount(Constants.minMaxHistoryCount - 1),
            Constants.minMaxHistoryCount
        )
        XCTAssertEqual(
            Constants.normalizedMaxHistoryCount(Constants.maxMaxHistoryCount + 1),
            Constants.maxMaxHistoryCount
        )
        XCTAssertEqual(
            Constants.normalizedMaxHistoryCount(Constants.defaultMaxHistoryCount),
            Constants.defaultMaxHistoryCount
        )
    }
}
