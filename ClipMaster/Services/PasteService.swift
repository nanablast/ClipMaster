import AppKit

enum PasteService {
    private enum PastePayload {
        case image(data: Data, isGIF: Bool)
        case files([URL])
        case text(String)
    }

    /// Writes the given clipboard item back to the system pasteboard,
    /// then simulates ⌘V to paste into the frontmost application.
    static func paste(_ item: ClipboardItem) {
        guard writeToPasteboard(item, validateFileExistence: true) else {
            if item.type == .file {
                ToastService.shared.show(
                    message: "原文件已移动或删除",
                    systemImage: "exclamationmark.triangle.fill",
                    tintColor: .systemOrange
                )
            }
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
        guard writePlainTextToPasteboard(item) else {
            NSSound.beep()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            simulatePaste()
        }
    }

    /// Writes a clipboard item into the target pasteboard.
    /// Returns false when no usable payload can be produced.
    @discardableResult
    static func writeToPasteboard(
        _ item: ClipboardItem,
        pasteboard: NSPasteboard = .general,
        storage: StorageService = .shared,
        validateFileExistence: Bool = false
    ) -> Bool {
        guard let payload = makePayload(
            from: item,
            storage: storage,
            validateFileExistence: validateFileExistence
        ) else {
            return false
        }
        return write(payload, to: pasteboard)
    }

    @discardableResult
    static func writePlainTextToPasteboard(_ item: ClipboardItem, pasteboard: NSPasteboard = .general) -> Bool {
        guard !(item.type == .image && item.content == Constants.imagePlaceholderText),
              !item.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return write(.text(item.content), to: pasteboard)
    }

    private static func write(_ payload: PastePayload, to pasteboard: NSPasteboard) -> Bool {
        let items: [NSPasteboardItem]
        switch payload {
        case .image(let data, let isGIF):
            let item = NSPasteboardItem()
            if isGIF {
                guard item.setData(data, forType: ClipboardPasteboardTypes.gif) else { return false }
            } else {
                guard item.setData(data, forType: .png) else { return false }
            }
            if let tiffData = NSImage(data: data)?.tiffRepresentation {
                _ = item.setData(tiffData, forType: .tiff)
            }
            items = [item]
        case .files(let urls):
            var fileItems: [NSPasteboardItem] = []
            for url in urls {
                let item = NSPasteboardItem()
                guard item.setString(url.absoluteString, forType: .fileURL) else { return false }
                fileItems.append(item)
            }
            items = fileItems
        case .text(let text):
            let item = NSPasteboardItem()
            guard item.setString(text, forType: .string) else { return false }
            items = [item]
        }
        for item in items {
            guard item.setString("", forType: ClipboardPasteboardTypes.historyReplay) else { return false }
        }
        // Publish the payload and replay marker together, including every file item.
        pasteboard.clearContents()
        return pasteboard.writeObjects(items)
    }

    private static func makePayload(
        from item: ClipboardItem,
        storage: StorageService,
        validateFileExistence: Bool
    ) -> PastePayload? {
        switch item.type {
        case .image:
            if let path = item.imagePath,
               let imageData = storage.loadImageData(filename: path) {
                let isGIF = URL(fileURLWithPath: path).pathExtension.lowercased() == "gif"
                return .image(data: imageData, isGIF: isGIF)
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
                .map { URL(fileURLWithPath: $0) }
            guard !urls.isEmpty else { return nil }
            if validateFileExistence {
                let allExist = urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
                guard allExist else { return nil }
            }
            return .files(urls)
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
