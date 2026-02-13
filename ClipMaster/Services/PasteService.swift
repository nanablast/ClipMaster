import AppKit

enum PasteService {
    private enum PastePayload {
        case image(Data)
        case files([NSURL])
        case text(String)
    }

    /// Writes the given clipboard item back to the system pasteboard,
    /// then simulates ⌘V to paste into the frontmost application.
    static func paste(_ item: ClipboardItem) {
        guard writeToPasteboard(item) else {
            NSSound.beep()
            return
        }

        // Small delay to ensure pasteboard is ready before simulating keypress
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            simulatePaste()
        }
    }

    /// Paste the current pasteboard content as plain text (strip formatting).
    static func pastePlainText(_ item: ClipboardItem) {
        if item.type == .image && item.content == Constants.imagePlaceholderText {
            NSSound.beep()
            return
        }

        let text = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            NSSound.beep()
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.content, forType: .string)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            simulatePaste()
        }
    }

    /// Writes a clipboard item into the target pasteboard.
    /// Returns false when no usable payload can be produced.
    @discardableResult
    static func writeToPasteboard(_ item: ClipboardItem, pasteboard: NSPasteboard = .general) -> Bool {
        guard let payload = makePayload(from: item) else {
            return false
        }

        pasteboard.clearContents()
        switch payload {
        case .image(let data):
            pasteboard.setData(data, forType: .png)
        case .files(let urls):
            pasteboard.writeObjects(urls)
        case .text(let text):
            pasteboard.setString(text, forType: .string)
        }
        return true
    }

    private static func makePayload(from item: ClipboardItem) -> PastePayload? {
        switch item.type {
        case .image:
            if let path = item.imagePath,
               let imageData = StorageService.shared.loadImageData(filename: path) {
                return .image(imageData)
            }
            let trimmed = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != Constants.imagePlaceholderText {
                return .text(item.content)
            }
            return nil
        case .file:
            let urls = item.content
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { URL(fileURLWithPath: $0) as NSURL }
            return urls.isEmpty ? nil : .files(urls)
        case .text, .link:
            let trimmed = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : .text(item.content)
        }
    }

    private static func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)

        // Virtual key code 0x09 = 'V'
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }
}
