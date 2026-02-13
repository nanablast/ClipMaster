import AppKit
import SwiftUI
import Carbon.HIToolbox

/// Controls the floating quick-paste panel lifecycle and keyboard input.
/// The panel never steals focus — the user's active app stays in front.
/// Keyboard events are intercepted via CGEvent tap so arrow keys work.
final class FloatingPanelController {
    static let shared = FloatingPanelController()

    private var panel: FloatingPanel?
    private var items: [ClipboardItem] = []
    private var selectedIndex = 0
    private var allItems: [ClipboardItem] = []
    private var searchText = ""
    private var listVersion = 0
    private var clickMonitor: Any?
    private var searchWorkItem: DispatchWorkItem?
    private var searchRequestID = UUID()

    private let maxVisibleItems = 20
    private let searchDebounceDelay: TimeInterval = 0.10
    private let searchQueue = DispatchQueue(label: "com.clipmaster.quickpaste.search", qos: .userInitiated)

    var isVisible: Bool { panel?.isVisible ?? false }

    private init() {}

    func toggle() {
        if isVisible {
            dismiss()
        } else {
            show()
        }
    }

    func show() {
        dismiss()

        guard let loaded = try? StorageService.shared.fetchAll(limit: maxVisibleItems), !loaded.isEmpty else {
            return
        }
        allItems = loaded
        items = loaded
        selectedIndex = 0
        searchText = ""
        listVersion = 0
        searchRequestID = UUID()

        let panel = FloatingPanel()
        self.panel = panel

        // Show at cursor position
        panel.show(with: makeView())

        // Install CGEvent tap for keyboard interception
        let tapInstalled = panel.installEventTap { [weak self] cgEvent in
            guard let self else { return false }
            return self.handleCGEvent(cgEvent)
        }
        if !tapInstalled {
            AppLogger.ui.error("Quick paste event tap install failed; keyboard shortcuts unavailable")
        }

        // Dismiss on click outside
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, let panel = self.panel else { return }
                // Global monitor provides screen coordinates
                let screenPoint = NSEvent.mouseLocation
                if !panel.frame.contains(screenPoint) {
                    self.dismiss()
                }
            }
        }
    }

    func dismiss() {
        searchWorkItem?.cancel()
        searchWorkItem = nil
        searchRequestID = UUID()
        panel?.dismiss()
        panel = nil
        items = []
        allItems = []
        selectedIndex = 0
        searchText = ""
        listVersion = 0
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    // MARK: - CGEvent keyboard handler
    // Event tap is installed on the main run loop; off-main fallback stays non-blocking.

    private func handleCGEvent(_ cgEvent: CGEvent) -> Bool {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                _ = self?.handleCGEventOnMain(cgEvent)
            }
            return false
        }
        return handleCGEventOnMain(cgEvent)
    }

    private func handleCGEventOnMain(_ cgEvent: CGEvent) -> Bool {
        let keyCode = Int(cgEvent.getIntegerValueField(.keyboardEventKeycode))
        let flags = cgEvent.flags

        // Escape — clear search or dismiss
        if keyCode == kVK_Escape {
            if !searchText.isEmpty {
                searchText = ""
                applySearch()
            } else {
                dismiss()
            }
            return true
        }

        // ⌘; — toggle off
        if keyCode == kVK_ANSI_Semicolon && flags.contains(.maskCommand) {
            dismiss()
            return true
        }

        // Enter — paste selected
        if let pasteMode = QuickPasteInteraction.pasteModeForEnter(
            keyCode: keyCode,
            flags: flags,
            selectedIndex: selectedIndex,
            itemCount: items.count
        ) {
            let item = items[selectedIndex]
            dismiss()
            // Delay paste slightly so the panel has time to close
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if pasteMode == .plainText {
                    PasteService.pastePlainText(item)
                } else {
                    PasteService.paste(item)
                }
            }
            return true
        } else if keyCode == kVK_Return {
            return false
        }

        // Arrow Up
        if let movedIndex = QuickPasteInteraction.movedSelectionIndex(
            keyCode: keyCode,
            currentIndex: selectedIndex,
            itemCount: items.count
        ) {
            if movedIndex != selectedIndex {
                selectedIndex = movedIndex
                refreshView()
            }
            return true
        } else if keyCode == kVK_UpArrow || keyCode == kVK_DownArrow {
            return true
        }

        // ⌘+Delete — delete selected
        if keyCode == kVK_Delete && flags.contains(.maskCommand) {
            guard selectedIndex < items.count else { return false }
            let deletedItem = items[selectedIndex]
            do {
                try StorageService.shared.delete(deletedItem)

                let hadSelection = selectedIndex
                reloadItems(preserveSelection: true, preferredIndex: hadSelection)

                let postDeleteAction = QuickPasteInteraction.postDeleteAction(
                    allItemsCount: allItems.count,
                    filteredItemsCount: items.count,
                    searchText: searchText
                )
                if postDeleteAction == .refresh {
                    refreshView(deferred: true)
                } else {
                    dismiss()
                }
            } catch {
                AppLogger.ui.error("Quick paste delete failed: \(error.localizedDescription, privacy: .public)")
                ToastService.shared.show(
                    message: "删除失败",
                    systemImage: "xmark.circle.fill",
                    tintColor: .systemRed
                )
            }
            return true
        }

        // Delete (backspace) — remove last search character
        if keyCode == kVK_Delete && !flags.contains(.maskCommand) {
            if !searchText.isEmpty {
                searchText.removeLast()
                refreshView()
                applySearch(debounced: true)
                return true
            }
            return false
        }

        // Number keys 0-9 — quick paste (only when not searching)
        let noModifiers = flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl]).isEmpty
        if noModifiers && searchText.isEmpty {
            let numberKeyMap: [Int: Int] = [
                kVK_ANSI_0: 0, kVK_ANSI_1: 1, kVK_ANSI_2: 2, kVK_ANSI_3: 3,
                kVK_ANSI_4: 4, kVK_ANSI_5: 5, kVK_ANSI_6: 6, kVK_ANSI_7: 7,
                kVK_ANSI_8: 8, kVK_ANSI_9: 9,
            ]
            if let index = numberKeyMap[keyCode], index < items.count {
                let item = items[index]
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    PasteService.paste(item)
                }
                return true
            }
        }

        // Printable character input — append to search
        let noActionModifiers = flags.intersection([.maskCommand, .maskAlternate, .maskControl]).isEmpty
        if noActionModifiers {
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            cgEvent.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
            if length > 0 {
                let str = String(utf16CodeUnits: chars, count: length)
                if !str.isEmpty && str.rangeOfCharacter(from: .controlCharacters) == nil {
                    searchText += str
                    refreshView()
                    applySearch(debounced: true)
                    return true
                }
            }
        }

        return false
    }

    // MARK: - Search

    private func reloadItems(preserveSelection: Bool = false, preferredIndex: Int? = nil) {
        allItems = (try? StorageService.shared.fetchAll(limit: maxVisibleItems)) ?? []
        applySearch(preserveSelection: preserveSelection, preferredIndex: preferredIndex)
    }

    private func applySearch(
        preserveSelection: Bool = false,
        preferredIndex: Int? = nil,
        debounced: Bool = false
    ) {
        let baseIndex = preferredIndex ?? selectedIndex
        let query = searchText

        if query.isEmpty {
            searchWorkItem?.cancel()
            searchWorkItem = nil
            searchRequestID = UUID()

            items = allItems
            listVersion += 1
            applySelection(preserveSelection: preserveSelection, preferredIndex: baseIndex)
            refreshView()
            return
        }

        let requestID = UUID()
        searchRequestID = requestID
        searchWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let results = (try? StorageService.shared.search(keyword: query, limit: self.maxVisibleItems)) ?? []
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.searchRequestID == requestID else { return }
                guard self.panel != nil else { return }
                guard self.searchText == query else { return }

                self.items = results
                self.listVersion += 1
                self.applySelection(preserveSelection: preserveSelection, preferredIndex: baseIndex)
                self.refreshView()
            }
        }

        searchWorkItem = workItem
        if debounced {
            searchQueue.asyncAfter(deadline: .now() + searchDebounceDelay, execute: workItem)
        } else {
            searchQueue.async(execute: workItem)
        }
    }

    private func applySelection(preserveSelection: Bool, preferredIndex: Int) {
        guard !items.isEmpty else {
            selectedIndex = 0
            return
        }

        if preserveSelection {
            selectedIndex = QuickPasteInteraction.preservedSelectionIndex(
                previousIndex: preferredIndex,
                newItemCount: items.count
            )
        } else {
            selectedIndex = 0
        }
    }

    // MARK: - View

    private func makeView() -> QuickPasteView {
        QuickPasteView(
            items: items,
            selectedIndex: selectedIndex,
            searchText: searchText,
            listVersion: listVersion
        )
    }

    private func refreshView(deferred: Bool = false) {
        let update = { [weak self] in
            guard let self else { return }
            self.panel?.updateContent(with: self.makeView())
        }
        if deferred {
            DispatchQueue.main.async(execute: update)
        } else {
            update()
        }
    }
}
