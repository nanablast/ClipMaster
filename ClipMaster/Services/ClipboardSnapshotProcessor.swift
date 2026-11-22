import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

struct PreparedClipboardItem {
    let item: ClipboardItem
    let imageData: Data?
    let imageFileExtension: String

    init(item: ClipboardItem, imageData: Data? = nil, imageFileExtension: String = "png") {
        self.item = item
        self.imageData = imageData
        self.imageFileExtension = imageFileExtension
    }

    enum PersistenceError: LocalizedError {
        case imageWriteFailed

        var errorDescription: String? { "Failed to save the clipboard image." }
    }

    func persist(using storage: StorageService) throws -> ClipboardItem {
        var savedItem = item
        if let imageData {
            guard let path = storage.saveImageFile(
                imageData,
                id: item.id,
                fileExtension: imageFileExtension
            ) else {
                throw PersistenceError.imageWriteFailed
            }
            savedItem.imagePath = path
        }
        do {
            try storage.insert(savedItem)
            return savedItem
        } catch {
            // A failed insert must not leave an orphaned image in the cache.
            if imageData != nil, let path = savedItem.imagePath {
                storage.removeImageFile(filename: path)
            }
            throw error
        }
    }
}

struct ClipboardSnapshotProcessor {
    var recognizeText: (Data) -> String = OCRService.recognizeText

    func prepare(_ snapshot: ClipboardSnapshot) -> PreparedClipboardItem? {
        Self.writeDebugLog(snapshot)

        if !snapshot.fileURLs.isEmpty {
            let paths = snapshot.fileURLs.map(\.path).joined(separator: "\n")
            return PreparedClipboardItem(item: makeItem(
                content: paths, type: .file, snapshot: snapshot
            ))
        }

        if let data = snapshot.rawImageData,
           let image = prepareImage(data, snapshot: snapshot, fallbackText: Constants.imagePlaceholderText) {
            return image
        }

        if let string = snapshot.stringContent, !string.isEmpty {
            let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
            let type: ContentType = url?.scheme == "http" || url?.scheme == "https" ? .link : .text
            return PreparedClipboardItem(item: makeItem(content: string, type: type, snapshot: snapshot))
        }
        return nil
    }

    private func prepareImage(
        _ data: Data,
        snapshot: ClipboardSnapshot,
        fallbackText: String
    ) -> PreparedClipboardItem? {
        guard let normalized = Self.normalizeImageData(data) else { return nil }
        let text = recognizeText(normalized.data)
        var item = makeItem(
            content: text.isEmpty ? fallbackText : text,
            type: .image,
            snapshot: snapshot
        )
        item.imageHash = SHA256.hash(data: normalized.data).map { String(format: "%02x", $0) }.joined()
        return PreparedClipboardItem(
            item: item,
            imageData: normalized.data,
            imageFileExtension: normalized.fileExtension
        )
    }

    private func makeItem(content: String, type: ContentType, snapshot: ClipboardSnapshot) -> ClipboardItem {
        ClipboardItem(
            content: content,
            type: type,
            appSource: snapshot.appSource,
            createdAt: snapshot.capturedAt
        )
    }

    private static func normalizeImageData(_ data: Data) -> (data: Data, fileExtension: String)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { return nil }

        let sourceType = CGImageSourceGetType(source) as String?
        if sourceType == UTType.gif.identifier, frameCount > 1 {
            return (data, "gif")
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if sourceType == UTType.png.identifier, orientation == 1 {
            return (data, "png")
        }

        let image: CGImage?
        if orientation == 1 {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        } else {
            let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
            let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
            let maxDimension = max(width, height)
            if maxDimension > 0 {
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxDimension
                ]
                image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            } else {
                image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            }
        }
        guard let image else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        let destinationProperties: [CFString: Any] = [kCGImagePropertyOrientation: 1]
        CGImageDestinationAddImage(destination, image, destinationProperties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? (output as Data, "png") : nil
    }

    private static func writeDebugLog(_ snapshot: ClipboardSnapshot) {
#if DEBUG
        guard UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.debugLoggingEnabled) else { return }
        let message = """
        [\(snapshot.capturedAt)] 剪贴板变化
        types: \(snapshot.typeNames.joined(separator: ", "))
        imageData: \(snapshot.rawImageData.map { "\($0.count) bytes" } ?? "nil")
        hasString: \(snapshot.stringContent != nil)
        appSource: \(snapshot.appSource ?? "nil")
        ---

        """
        guard let data = message.data(using: .utf8),
              let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }
        let directory = appSupport.appendingPathComponent("ClipMaster", isDirectory: true)
        let log = directory.appendingPathComponent("debug.log")
        let backup = directory.appendingPathComponent("debug.log.1")
        let fileManager = FileManager.default

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: log.path) {
                let attributes = try fileManager.attributesOfItem(atPath: log.path)
                let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
                if size + data.count > Constants.debugLogMaxSizeBytes {
                    try? fileManager.removeItem(at: backup)
                    try fileManager.moveItem(at: log, to: backup)
                }
            }
            if let handle = FileHandle(forWritingAtPath: log.path) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: log)
            }
        } catch {
            AppLogger.clipboard.debug("Could not write clipboard debug log: \(error.localizedDescription, privacy: .public)")
        }
#endif
    }
}
