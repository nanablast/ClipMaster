import AppKit
import SwiftUI
import Carbon.HIToolbox
import ApplicationServices

/// Controls the floating quick-paste panel lifecycle and keyboard input.
/// The panel normally does not steal focus — the user's active app stays in front.
/// When secure input is enabled, it falls back to focused keyboard mode.
final class FloatingPanelController {
    static let shared = FloatingPanelController()

    private var panel: FloatingPanel?
    private var items: [ClipboardItem] = []
    private var selectedIndex = 0
    private var allItems: [ClipboardItem] = []
    private var searchText = ""
    private var listVersion = 0
    private var keyboardInputAvailable = true
    private var protectedInputRestricted = false
    private var clickMonitor: Any?
    private var localKeyMonitor: Any?
    private var secureInputMode = false
    private var frontmostAppBeforePanel: NSRunningApplication?
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
        dismiss(restoreFocus: false)

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

        let frontmostBeforePanel = NSWorkspace.shared.frontmostApplication
        let restrictedMode = isRestrictedProtectedInputMode(frontmostApp: frontmostBeforePanel)
        protectedInputRestricted = restrictedMode

        let focusedKeyboardMode = !restrictedMode && shouldUseFocusedKeyboardMode(frontmostApp: frontmostBeforePanel)
        secureInputMode = focusedKeyboardMode
        frontmostAppBeforePanel = focusedKeyboardMode ? frontmostBeforePanel : nil
        panel.setKeyboardCaptureEnabled(focusedKeyboardMode)

        if restrictedMode {
            keyboardInputAvailable = false
            AppLogger.ui.notice("Quick paste restricted in protected password input; click-to-copy fallback active")
        } else if focusedKeyboardMode {
            AppLogger.ui.notice("Quick paste switched to focused keyboard mode for protected input compatibility")
        }

        // Show at cursor position
        panel.show(with: makeView(), activateApp: focusedKeyboardMode)

        if restrictedMode {
            panel.setLocalKeyHandler(nil)
        } else if focusedKeyboardMode {
            panel.setLocalKeyHandler { [weak self] event in
                guard let self else { return false }
                return self.handleNSEvent(event)
            }
            keyboardInputAvailable = installLocalKeyboardMonitor()
            if !keyboardInputAvailable {
                AppLogger.ui.error("Quick paste local keyboard monitor install failed in secure input mode")
                panel.updateContent(with: makeView())
            }
        } else {
            panel.setLocalKeyHandler(nil)
            // Install CGEvent tap for keyboard interception
            let tapInstalled = panel.installEventTap { [weak self] cgEvent in
                guard let self else { return false }
                return self.handleCGEvent(cgEvent)
            }
            keyboardInputAvailable = tapInstalled
            if !tapInstalled {
                AppLogger.ui.error("Quick paste event tap install failed; keyboard shortcuts unavailable")
                panel.updateContent(with: makeView())
            }
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

    func dismiss(restoreFocus: Bool = true) {
        if restoreFocus,
           secureInputMode,
           let targetApp = frontmostAppBeforePanel,
           !targetApp.isTerminated {
            targetApp.activate(options: [.activateIgnoringOtherApps])
        }

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
        keyboardInputAvailable = true
        protectedInputRestricted = false
        secureInputMode = false
        frontmostAppBeforePanel = nil
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
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
        return handleKeyInput(keyCode: keyCode, flags: flags, printableInput: unicodeInput(from: cgEvent))
    }

    private func handleNSEvent(_ event: NSEvent) -> Bool {
        let keyCode = Int(event.keyCode)
        let flags = cgEventFlags(from: event.modifierFlags)
        if keyCode == kVK_UpArrow || keyCode == kVK_DownArrow || keyCode == kVK_Return {
            AppLogger.ui.debug("Focused mode keyDown keyCode=\(keyCode) flags=\(String(describing: flags), privacy: .public)")
        }
        return handleKeyInput(keyCode: keyCode, flags: flags, printableInput: event.characters)
    }

    private func handleKeyInput(keyCode: Int, flags: CGEventFlags, printableInput: String?) -> Bool {
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
            if protectedInputRestricted {
                copyForRestrictedInput(item)
            } else {
                performPaste(item, plainText: pasteMode == .plainText)
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
                if protectedInputRestricted {
                    copyForRestrictedInput(item)
                } else {
                    performPaste(item)
                }
                return true
            }
        }

        // Printable character input — append to search
        let noActionModifiers = flags.intersection([.maskCommand, .maskAlternate, .maskControl]).isEmpty
        if noActionModifiers {
            if let str = printableInput,
               !str.isEmpty,
               str.rangeOfCharacter(from: .controlCharacters) == nil {
                searchText += str
                refreshView()
                applySearch(debounced: true)
                return true
            }
        }

        return false
    }

    private func unicodeInput(from event: CGEvent) -> String? {
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        guard length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }

    private func cgEventFlags(from flags: NSEvent.ModifierFlags) -> CGEventFlags {
        var result: CGEventFlags = []
        if flags.contains(.command) { result.insert(.maskCommand) }
        if flags.contains(.shift) { result.insert(.maskShift) }
        if flags.contains(.option) { result.insert(.maskAlternate) }
        if flags.contains(.control) { result.insert(.maskControl) }
        return result
    }

    private func installLocalKeyboardMonitor() -> Bool {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleNSEvent(event) ? nil : event
        }
        return localKeyMonitor != nil
    }

    private func shouldUseFocusedKeyboardMode(frontmostApp: NSRunningApplication?) -> Bool {
        if isKnownProtectedInputApp(frontmostApp) { return false }
        if IsSecureEventInputEnabled() { return true }
        return isFocusedElementSecureTextInput(frontmostApp)
    }

    private func isRestrictedProtectedInputMode(frontmostApp: NSRunningApplication?) -> Bool {
        guard isKnownProtectedInputApp(frontmostApp) else { return false }
        if IsSecureEventInputEnabled() { return true }
        return isFocusedElementSecureTextInput(frontmostApp)
    }

    private func isKnownProtectedInputApp(_ app: NSRunningApplication?) -> Bool {
        let bundle = app?.bundleIdentifier?.lowercased() ?? ""
        let name = app?.localizedName?.lowercased() ?? ""
        return bundle.contains("chatbox") || name.contains("chatbox")
    }

    private func isFocusedElementSecureTextInput(_ app: NSRunningApplication?) -> Bool {
        guard let app else { return false }
        guard SystemPermissionService.isAccessibilityGranted() else { return false }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedValue: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard focusedResult == .success, let focusedValue else { return false }
        guard CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else { return false }

        let focusedElement = unsafeBitCast(focusedValue, to: AXUIElement.self)

        var subroleValue: CFTypeRef?
        let subroleResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSubroleAttribute as CFString,
            &subroleValue
        )
        if subroleResult == .success,
           let subrole = subroleValue as? String,
           subrole == (kAXSecureTextFieldSubrole as String) {
            return true
        }

        var roleValue: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXRoleAttribute as CFString,
            &roleValue
        )
        if roleResult == .success,
           let role = roleValue as? String,
           role.lowercased().contains("secure") {
            return true
        }

        return false
    }

    private func performPaste(_ item: ClipboardItem, plainText: Bool = false) {
        let targetApp = secureInputMode ? frontmostAppBeforePanel : nil
        dismiss(restoreFocus: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            if let targetApp, !targetApp.isTerminated {
                targetApp.activate(options: [.activateIgnoringOtherApps])
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                if plainText {
                    PasteService.pastePlainText(item)
                } else {
                    PasteService.paste(item)
                }
            }
        }
    }

    private func copyForRestrictedInput(_ item: ClipboardItem) {
        let copied = PasteService.writeToPasteboard(item)
        dismiss(restoreFocus: false)
        if copied {
            ToastService.shared.show(
                message: "已复制：密码隐藏模式请切到可见后粘贴",
                systemImage: "eye.slash.fill",
                tintColor: .systemOrange,
                duration: 1.6
            )
        } else {
            NSSound.beep()
            ToastService.shared.show(
                message: "复制失败",
                systemImage: "xmark.circle.fill",
                tintColor: .systemRed
            )
        }
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
            listVersion: listVersion,
            keyboardInputAvailable: keyboardInputAvailable,
            protectedInputRestricted: protectedInputRestricted,
            onItemSelect: { [weak self] index in
                guard let self else { return }
                guard index >= 0, index < self.items.count else { return }
                self.selectedIndex = index
                let item = self.items[index]
                if self.protectedInputRestricted {
                    self.copyForRestrictedInput(item)
                } else {
                    self.performPaste(item)
                }
            }
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
