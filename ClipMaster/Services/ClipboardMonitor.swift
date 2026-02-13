import AppKit
import Combine
import CryptoKit

struct ClipboardPollPolicy {
    private(set) var interval: TimeInterval = Constants.clipboardPollActiveInterval
    private(set) var noChangeStreak = 0

    mutating func reset() {
        interval = Constants.clipboardPollActiveInterval
        noChangeStreak = 0
    }

    @discardableResult
    mutating func recordNoChange() -> Bool {
        noChangeStreak += 1
        guard interval != Constants.clipboardPollIdleInterval else { return false }
        guard noChangeStreak >= Constants.clipboardIdleThreshold else { return false }
        interval = Constants.clipboardPollIdleInterval
        return true
    }

    @discardableResult
    mutating func recordChange() -> Bool {
        noChangeStreak = 0
        guard interval != Constants.clipboardPollActiveInterval else { return false }
        interval = Constants.clipboardPollActiveInterval
        return true
    }
}

final class ClipboardMonitor: ObservableObject {
    @Published var latestItem: ClipboardItem?

    private struct ClipboardSnapshot {
        let appSource: String?
        let rawImageData: Data?
        let fileURLs: [URL]?
        let stringContent: String?
        let hasFileURL: Bool
    }

    private var pollTimer: DispatchSourceTimer?
    private var pollPolicy = ClipboardPollPolicy()
    private var lastChangeCount: Int
    private var pendingChangeCount: Int?
    private var isProcessing = false

    private let pollQueue = DispatchQueue(label: "com.clipmaster.clipboard.poll", qos: .utility)
    private let processingQueue = DispatchQueue(label: "com.clipmaster.clipboard.processing", qos: .userInitiated)
    private let pasteboard = NSPasteboard.general
    private let storageService = StorageService.shared

    init() {
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        stop()
        lastChangeCount = pasteboard.changeCount
        pendingChangeCount = nil
        isProcessing = false
        pollPolicy.reset()
        configurePollTimer(interval: pollPolicy.interval)
    }

    func stop() {
        pollTimer?.setEventHandler {}
        pollTimer?.cancel()
        pollTimer = nil
        pendingChangeCount = nil
        isProcessing = false
        pollPolicy.reset()
    }

    private func configurePollTimer(interval: TimeInterval) {
        pollTimer?.setEventHandler {}
        pollTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: pollQueue)
        timer.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(Int(Constants.clipboardPollLeeway * 1_000))
        )
        timer.setEventHandler { [weak self] in
            self?.handlePollTick()
        }
        timer.resume()
        pollTimer = timer
    }

    private func handlePollTick() {
        DispatchQueue.main.async { [weak self] in
            self?.checkForChanges()
        }
    }

    private func checkForChanges() {
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else {
            if pollPolicy.recordNoChange() {
                configurePollTimer(interval: pollPolicy.interval)
            }
            return
        }

        if pollPolicy.recordChange() {
            configurePollTimer(interval: pollPolicy.interval)
        }

        lastChangeCount = currentCount
        if isProcessing {
            pendingChangeCount = currentCount
            return
        }

        processChange(changeCount: currentCount)
    }

    private func processChange(changeCount: Int) {
        guard !isProcessing else {
            pendingChangeCount = changeCount
            return
        }

        guard let snapshot = captureSnapshot(expectedChangeCount: changeCount) else {
            let latestCount = pasteboard.changeCount
            if latestCount != lastChangeCount {
                lastChangeCount = latestCount
                pendingChangeCount = latestCount
            }
            if let pending = pendingChangeCount, pending == lastChangeCount {
                pendingChangeCount = nil
                DispatchQueue.main.async { [weak self] in
                    self?.processChange(changeCount: pending)
                }
            }
            return
        }

        isProcessing = true
        processingQueue.async { [weak self] in
            guard let self else { return }
            let item = self.buildClipboardItem(
                appSource: snapshot.appSource,
                rawImageData: snapshot.rawImageData,
                fileURLs: snapshot.fileURLs,
                stringContent: snapshot.stringContent,
                hasFileURL: snapshot.hasFileURL
            )

            if let item {
                do {
                    try self.storageService.insert(item)
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.latestItem = item
                        self.playCopySoundIfNeeded()
                    }
                } catch {
                    AppLogger.clipboard.error("Failed to save clipboard item: \(error.localizedDescription, privacy: .public)")
                }
            }

            DispatchQueue.main.async { [weak self] in
                self?.finishProcessingCycle()
            }
        }
    }

    private func finishProcessingCycle() {
        isProcessing = false
        guard let pending = pendingChangeCount else { return }
        pendingChangeCount = nil
        processChange(changeCount: pending)
    }

    private func captureSnapshot(expectedChangeCount: Int) -> ClipboardSnapshot? {
        guard pasteboard.changeCount == expectedChangeCount else { return nil }

        let appSource = NSWorkspace.shared.frontmostApplication?.localizedName
        let rawImageData = readRawImageData()
        let hasFileURL = pasteboard.types?.contains(.fileURL) ?? false
        let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL]
        let stringContent = pasteboard.string(forType: .string)

        if shouldWriteDebugLog {
            let types = pasteboard.types?.map { $0.rawValue } ?? []
            let debugMsg = """
            [\(Date())] 剪贴板变化
            types: \(types.joined(separator: ", "))
            imageData: \(rawImageData.map { "\($0.count) bytes" } ?? "nil")
            hasString: \(stringContent != nil)
            appSource: \(appSource ?? "nil")
            ---
            """
            appendDebugLog(debugMsg)
        }

        guard pasteboard.changeCount == expectedChangeCount else { return nil }
        return ClipboardSnapshot(
            appSource: appSource,
            rawImageData: rawImageData,
            fileURLs: fileURLs,
            stringContent: stringContent,
            hasFileURL: hasFileURL
        )
    }

    private func playCopySoundIfNeeded() {
        let defaults = UserDefaults.standard
        let soundOff = defaults.object(forKey: Constants.UserDefaultsKeys.soundEnabled) != nil
            && !defaults.bool(forKey: Constants.UserDefaultsKeys.soundEnabled)
        if !soundOff {
            let name = defaults.string(forKey: Constants.UserDefaultsKeys.soundName) ?? Constants.defaultSoundName
            NSSound(named: name)?.play()
        }
    }

    private func buildClipboardItem(
        appSource: String?,
        rawImageData: Data?,
        fileURLs: [URL]?,
        stringContent: String?,
        hasFileURL: Bool
    ) -> ClipboardItem? {
        // If clipboard contains file URLs, it's a file copy (e.g. from Finder).
        // Finder also puts the file icon as tiff, so we must check files first.
        if hasFileURL, let fileURLs, !fileURLs.isEmpty {
            let paths = fileURLs.map { $0.path }.joined(separator: "\n")

            // If all files are images, treat as image copy and run OCR on the first one
            let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "webp", "heic"]
            let allImages = fileURLs.allSatisfy { imageExtensions.contains($0.pathExtension.lowercased()) }

            if allImages, let firstURL = fileURLs.first,
               let fileImageData = try? Data(contentsOf: firstURL) {
                let normalizedImageData = normalizeImageData(fileImageData) ?? fileImageData
                let ocrText = OCRService.recognizeText(from: normalizedImageData)
                let content = ocrText.isEmpty ? paths : ocrText
                let itemId = UUID()
                let imagePath = storageService.saveImageFile(normalizedImageData, id: itemId)
                let imageHash = sha256Hex(normalizedImageData)
                return ClipboardItem(
                    id: itemId,
                    content: content,
                    type: .image,
                    appSource: appSource,
                    imagePath: imagePath,
                    imageHash: imageHash
                )
            }

            return ClipboardItem(
                content: paths,
                type: .file,
                appSource: appSource
            )
        }

        // Pure image copy (screenshot, copy image from browser, etc.)
        if let normalizedImageData = normalizeImageData(rawImageData) {
            let ocrText = OCRService.recognizeText(from: normalizedImageData)
            let content = ocrText.isEmpty ? Constants.imagePlaceholderText : ocrText
            let itemId = UUID()
            let imagePath = storageService.saveImageFile(normalizedImageData, id: itemId)
            let imageHash = sha256Hex(normalizedImageData)
            return ClipboardItem(
                id: itemId,
                content: content,
                type: .image,
                appSource: appSource,
                imagePath: imagePath,
                imageHash: imageHash
            )
        }

        // Check for string content
        if let string = stringContent, !string.isEmpty {
            let type: ContentType = isURL(string) ? .link : .text
            return ClipboardItem(
                content: string,
                type: type,
                appSource: appSource
            )
        }

        return nil
    }

    private func readRawImageData() -> Data? {
        if let data = pasteboard.data(forType: .tiff) {
            return data
        }
        if let data = pasteboard.data(forType: .png) {
            return data
        }
        return nil
    }

    private func normalizeImageData(_ rawData: Data?) -> Data? {
        guard let rawData else { return nil }
        guard let image = NSImage(data: rawData),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return rawData
        }
        return pngData
    }

    private func isURL(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }

    private func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private var shouldWriteDebugLog: Bool {
#if DEBUG
        UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.debugLoggingEnabled)
#else
        false
#endif
    }

    private func appendDebugLog(_ message: String) {
        guard let data = message.data(using: .utf8) else { return }

        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let appSupportURL else { return }

        let dirURL = appSupportURL.appendingPathComponent("ClipMaster", isDirectory: true)
        let logURL = dirURL.appendingPathComponent("debug.log")
        let backupURL = dirURL.appendingPathComponent("debug.log.1")

        do {
            try fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: logURL.path) {
                let attributes = try fileManager.attributesOfItem(atPath: logURL.path)
                let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
                if size + data.count > Constants.debugLogMaxSizeBytes {
                    try? fileManager.removeItem(at: backupURL)
                    try fileManager.moveItem(at: logURL, to: backupURL)
                }
            }
        } catch {
            return
        }

        if let handle = FileHandle(forWritingAtPath: logURL.path) {
            defer { handle.closeFile() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: logURL)
        }
    }
}
