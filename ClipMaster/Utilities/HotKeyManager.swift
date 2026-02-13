import AppKit
import HotKey

final class HotKeyManager {
    static let shared = HotKeyManager()

    private var quickPasteHotKey: HotKey?
    private var pasteQueueHotKey: HotKey?
    private var ocrHotKey: HotKey?

    /// ⌘; — toggle the floating quick-paste panel at cursor
    var onQuickPaste: (() -> Void)?
    /// ⌘' — toggle paste queue mode
    var onPasteQueue: (() -> Void)?
    /// ⌘⇧O — screenshot region OCR
    var onScreenshotOCR: (() -> Void)?

    private init() {}

    func register() {
        quickPasteHotKey = HotKey(key: .semicolon, modifiers: [.command])
        quickPasteHotKey?.keyDownHandler = { [weak self] in
            self?.onQuickPaste?()
        }

        pasteQueueHotKey = HotKey(key: .quote, modifiers: [.command])
        pasteQueueHotKey?.keyDownHandler = { [weak self] in
            self?.onPasteQueue?()
        }

        ocrHotKey = HotKey(key: .o, modifiers: [.command, .shift])
        ocrHotKey?.keyDownHandler = { [weak self] in
            self?.onScreenshotOCR?()
        }
    }

    func unregister() {
        quickPasteHotKey = nil
        pasteQueueHotKey = nil
        ocrHotKey = nil
    }
}
