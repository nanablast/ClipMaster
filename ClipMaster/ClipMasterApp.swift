import SwiftUI

@main
struct ClipMasterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var settingsWindow: NSWindow?
    private let clipboardMonitor = ClipboardMonitor()
    private let hotKeyManager = HotKeyManager.shared
    private let pasteQueue = PasteQueue.shared
    private let floatingPanelController = FloatingPanelController.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        requestAccessibilityPermissionIfNeeded()

        // Clear image cache from previous session
        StorageService.shared.clearImageCache()
        StorageService.shared.expireSessionImages()
        ImageThumbnailCache.shared.removeAll()

        setupStatusItem()
        setupPopover()
        setupHotKey()
        pasteQueue.onStateChanged = { [weak self] isActive in
            self?.updateStatusIcon(queueActive: isActive)
        }
        updateStatusIcon(queueActive: pasteQueue.isActive)

        if let warning = StorageService.shared.startupWarningMessage {
            AppLogger.storage.error("Storage startup warning: \(warning, privacy: .public)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                ToastService.shared.show(
                    message: "数据库只读模式：请检查并重新部署",
                    systemImage: "exclamationmark.triangle.fill",
                    tintColor: .systemOrange,
                    duration: 2.0
                )
            }
        }

        if StorageService.shared.mode == .readWrite {
            clipboardMonitor.start()
        } else {
            AppLogger.storage.warning("Clipboard monitor disabled because storage is read-only")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor.stop()
        hotKeyManager.unregister()
        pasteQueue.stop()
        pasteQueue.onStateChanged = nil
        floatingPanelController.dismiss()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "ClipMaster")
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            togglePopover()
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 ClipMaster", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Reset menu so left-click works as toggle again
        statusItem.menu = nil
    }

    @objc private func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "ClipMaster 设置"
        window.styleMask = [.titled, .closable]
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindow = window
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Popover (menu bar, for full history)

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 480)
        popover.behavior = .transient
        popover.animates = true
    }

    private func setupHotKey() {
        hotKeyManager.onQuickPaste = { [weak self] in
            self?.toggleQuickPaste()
        }
        hotKeyManager.onPasteQueue = { [weak self] in
            self?.activatePasteQueue()
        }
        hotKeyManager.onScreenshotOCR = {
            ScreenshotOCRService.captureAndOCR()
        }
        do {
            try hotKeyManager.reloadFromUserDefaults()
        } catch {
            AppLogger.app.error("Hot key setup failed: \(error.localizedDescription, privacy: .public)")
            ToastService.shared.show(
                message: "快捷键配置无效，已恢复默认值",
                systemImage: "exclamationmark.triangle.fill",
                tintColor: .systemOrange,
                duration: 1.8
            )
        }
    }

    // MARK: - Menu Bar Popover

    private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        let historyView = ClipboardHistoryView(
            clipboardMonitor: clipboardMonitor,
            onDismiss: { [weak self] in
                self?.closePopover()
            }
        )
        popover.contentViewController = NSHostingController(rootView: historyView)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closePopover() {
        popover.performClose(nil)
    }

    // MARK: - Quick Paste (⌘; floating panel, no focus steal)

    private func toggleQuickPaste() {
        floatingPanelController.toggle()
    }

    // MARK: - Paste Queue

    private func activatePasteQueue() {
        if pasteQueue.isActive {
            pasteQueue.stop()
            return
        }

        guard let items = try? StorageService.shared.fetchAll(limit: 20) else { return }
        guard !items.isEmpty else { return }

        pasteQueue.start(with: items.reversed())
    }

    private func updateStatusIcon(queueActive: Bool) {
        if let button = statusItem.button {
            let iconName = queueActive ? "clipboard.fill" : "clipboard"
            button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "ClipMaster")
        }
    }

    private func requestAccessibilityPermissionIfNeeded() {
        guard !SystemPermissionService.isAccessibilityGranted() else { return }

        let defaults = UserDefaults.standard
        let key = Constants.UserDefaultsKeys.lastAccessibilityPromptAt
        let lastPromptAt = defaults.object(forKey: key) as? Date
        let now = Date()
        guard PermissionPromptPolicy.shouldPrompt(
            now: now,
            lastPromptAt: lastPromptAt,
            minimumInterval: Constants.accessibilityPromptMinInterval
        ) else {
            return
        }

        SystemPermissionService.requestAccessibilityPrompt()
        defaults.set(now, forKey: key)
    }
}
