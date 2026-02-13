import Carbon.HIToolbox
import CoreGraphics

enum QuickPastePasteMode: Equatable {
    case normal
    case plainText
}

enum QuickPastePostDeleteAction: Equatable {
    case refresh
    case dismiss
}

enum QuickPasteInteraction {
    static func movedSelectionIndex(
        keyCode: Int,
        currentIndex: Int,
        itemCount: Int
    ) -> Int? {
        guard itemCount > 0 else { return nil }

        if keyCode == kVK_UpArrow {
            return max(0, currentIndex - 1)
        }

        if keyCode == kVK_DownArrow {
            return min(itemCount - 1, currentIndex + 1)
        }

        return nil
    }

    static func pasteModeForEnter(
        keyCode: Int,
        flags: CGEventFlags,
        selectedIndex: Int,
        itemCount: Int
    ) -> QuickPastePasteMode? {
        guard keyCode == kVK_Return else { return nil }
        guard selectedIndex >= 0, selectedIndex < itemCount else { return nil }
        return flags.contains(.maskShift) ? .plainText : .normal
    }

    static func preservedSelectionIndex(
        previousIndex: Int,
        newItemCount: Int
    ) -> Int {
        guard newItemCount > 0 else { return 0 }
        return min(max(previousIndex, 0), newItemCount - 1)
    }

    static func postDeleteAction(
        allItemsCount: Int,
        filteredItemsCount: Int,
        searchText: String
    ) -> QuickPastePostDeleteAction {
        if allItemsCount == 0 {
            return .dismiss
        }
        if filteredItemsCount > 0 || !searchText.isEmpty {
            return .refresh
        }
        return .dismiss
    }
}
