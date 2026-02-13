import XCTest
import CoreGraphics
import Carbon.HIToolbox
@testable import ClipMaster

final class QuickPasteInteractionTests: XCTestCase {
    func testSelectionMovesWithinBounds() {
        XCTAssertEqual(
            QuickPasteInteraction.movedSelectionIndex(
                keyCode: kVK_DownArrow,
                currentIndex: 0,
                itemCount: 5
            ),
            1
        )

        XCTAssertEqual(
            QuickPasteInteraction.movedSelectionIndex(
                keyCode: kVK_UpArrow,
                currentIndex: 0,
                itemCount: 5
            ),
            0
        )

        XCTAssertEqual(
            QuickPasteInteraction.movedSelectionIndex(
                keyCode: kVK_DownArrow,
                currentIndex: 4,
                itemCount: 5
            ),
            4
        )
    }

    func testEnterPastePathResolvesNormalAndPlainText() {
        XCTAssertEqual(
            QuickPasteInteraction.pasteModeForEnter(
                keyCode: kVK_Return,
                flags: [],
                selectedIndex: 1,
                itemCount: 3
            ),
            .normal
        )

        XCTAssertEqual(
            QuickPasteInteraction.pasteModeForEnter(
                keyCode: kVK_Return,
                flags: [.maskShift],
                selectedIndex: 1,
                itemCount: 3
            ),
            .plainText
        )

        XCTAssertNil(
            QuickPasteInteraction.pasteModeForEnter(
                keyCode: kVK_Return,
                flags: [],
                selectedIndex: 3,
                itemCount: 3
            )
        )
    }

    func testDeletePostActionResolvesRefreshOrDismiss() {
        XCTAssertEqual(
            QuickPasteInteraction.postDeleteAction(
                allItemsCount: 0,
                filteredItemsCount: 0,
                searchText: ""
            ),
            .dismiss
        )

        XCTAssertEqual(
            QuickPasteInteraction.postDeleteAction(
                allItemsCount: 3,
                filteredItemsCount: 2,
                searchText: ""
            ),
            .refresh
        )

        XCTAssertEqual(
            QuickPasteInteraction.postDeleteAction(
                allItemsCount: 3,
                filteredItemsCount: 0,
                searchText: "query"
            ),
            .refresh
        )

        XCTAssertEqual(
            QuickPasteInteraction.postDeleteAction(
                allItemsCount: 3,
                filteredItemsCount: 0,
                searchText: ""
            ),
            .dismiss
        )
    }

    func testPreservedSelectionIndexKeepsClosestValidPosition() {
        XCTAssertEqual(
            QuickPasteInteraction.preservedSelectionIndex(
                previousIndex: 4,
                newItemCount: 2
            ),
            1
        )

        XCTAssertEqual(
            QuickPasteInteraction.preservedSelectionIndex(
                previousIndex: 0,
                newItemCount: 0
            ),
            0
        )
    }
}
