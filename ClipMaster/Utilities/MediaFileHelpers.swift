import AppKit
import ImageIO

enum MediaFileKind: Equatable {
    case image
    case video
    case audio
    case other

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "webp", "heic", "heif", "avif", "svg"
    ]
    private static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "avi", "webm", "flv", "wmv"
    ]
    private static let audioExtensions: Set<String> = [
        "mp3", "wav", "m4a", "aac", "flac", "ogg", "opus", "aiff", "aif"
    ]

    static func classify(fileExtension: String) -> MediaFileKind {
        let ext = fileExtension
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            .lowercased()
        if imageExtensions.contains(ext) { return .image }
        if videoExtensions.contains(ext) { return .video }
        if audioExtensions.contains(ext) { return .audio }
        return .other
    }

    static func classify(url: URL) -> MediaFileKind {
        classify(fileExtension: url.pathExtension)
    }

    var systemImageName: String {
        switch self {
        case .image: return "photo.on.rectangle"
        case .video: return "film"
        case .audio: return "waveform"
        case .other: return "doc"
        }
    }
}

struct MediaFilePresentation {
    let urls: [URL]
    let primaryKind: MediaFileKind
    let singleImageURL: URL?
    let displayText: String
    let iconSystemName: String

    init(content: String) {
        let parsedURLs = content
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0) }
        self.urls = parsedURLs

        if parsedURLs.count == 1, let first = parsedURLs.first {
            let kind = MediaFileKind.classify(url: first)
            self.primaryKind = kind
            self.singleImageURL = (kind == .image) ? first : nil
            let parentName = first.deletingLastPathComponent().lastPathComponent
            if parentName.isEmpty || parentName == "/" {
                self.displayText = first.lastPathComponent
            } else {
                self.displayText = "\(first.lastPathComponent) — \(parentName)"
            }
            self.iconSystemName = kind.systemImageName
        } else if parsedURLs.count > 1, let first = parsedURLs.first {
            let kinds = Set(parsedURLs.map { MediaFileKind.classify(url: $0) })
            let uniformKind: MediaFileKind = kinds.count == 1 ? (kinds.first ?? .other) : .other
            self.primaryKind = uniformKind
            self.singleImageURL = nil
            self.displayText = "\(first.lastPathComponent) 等 \(parsedURLs.count) 个文件"
            self.iconSystemName = uniformKind == .other ? "doc.on.doc" : uniformKind.systemImageName
        } else {
            self.primaryKind = .other
            self.singleImageURL = nil
            self.displayText = content
            self.iconSystemName = "doc"
        }
    }
}

enum ImageThumbnailLoader {
    static let defaultMaxPixelSize: CGFloat = 96

    static func cacheKey(imagePath: String, maxPixelSize: CGFloat = defaultMaxPixelSize) -> String {
        "stored:\(imagePath):\(Int(maxPixelSize))"
    }

    static func cacheKey(fileURL: URL, maxPixelSize: CGFloat = defaultMaxPixelSize) -> String {
        "file:\(fileURL.path):\(Int(maxPixelSize))"
    }

    static func loadThumbnail(fromFileURL url: URL, maxPixelSize: CGFloat = defaultMaxPixelSize) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return makeThumbnail(from: source, maxPixelSize: maxPixelSize)
    }

    static func loadThumbnail(from data: Data, maxPixelSize: CGFloat = defaultMaxPixelSize) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return makeThumbnail(from: source, maxPixelSize: maxPixelSize)
    }

    private static func makeThumbnail(from source: CGImageSource, maxPixelSize: CGFloat) -> NSImage? {
        guard CGImageSourceGetCount(source) > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(Int(maxPixelSize.rounded(.up)), 1),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

enum ImageFileSaver {
    static func uniqueDestinationURL(
        in directory: URL,
        baseName: String,
        fileExtension: String,
        fileManager: FileManager = .default
    ) -> URL {
        let normalizedExtension = fileExtension
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            .lowercased()
        let ext = normalizedExtension.isEmpty ? "png" : normalizedExtension

        let firstCandidate = directory.appendingPathComponent("\(baseName).\(ext)")
        if !fileManager.fileExists(atPath: firstCandidate.path) {
            return firstCandidate
        }

        var suffix = 2
        while true {
            let candidate = directory.appendingPathComponent("\(baseName) \(suffix).\(ext)")
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            suffix += 1
        }
    }

    static func saveImageToDownloads(_ item: ClipboardItem) {
        guard item.type == .image,
              let data = try? StorageService.shared.fetchImageData(for: item.id) else {
            ToastService.shared.show(
                message: "图片数据不存在",
                systemImage: "xmark.circle.fill",
                tintColor: .systemRed
            )
            return
        }

        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let fileExtension: String
        if let imagePath = item.imagePath {
            let pathExt = URL(fileURLWithPath: imagePath).pathExtension.lowercased()
            fileExtension = pathExt.isEmpty ? "png" : pathExt
        } else {
            fileExtension = "png"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let baseName = "ClipMaster-\(formatter.string(from: Date()))"
        let fileURL = uniqueDestinationURL(
            in: downloadsURL,
            baseName: baseName,
            fileExtension: fileExtension
        )

        do {
            try data.write(to: fileURL, options: .atomic)
            ToastService.shared.show(
                message: "已保存到 Downloads/\(fileURL.lastPathComponent)",
                systemImage: "checkmark.circle.fill",
                tintColor: .systemGreen
            )
        } catch {
            AppLogger.ui.error("Save image failed: \(error.localizedDescription, privacy: .public)")
            ToastService.shared.show(
                message: "保存失败",
                systemImage: "xmark.circle.fill",
                tintColor: .systemRed
            )
        }
    }
}
