import AppKit
import Dispatch

final class ImageThumbnailCache {
    static let shared = ImageThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()
    private let memoryPressureSource: DispatchSourceMemoryPressure

    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 64 * 1024 * 1024 // ~64MB
        memoryPressureSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: DispatchQueue.global(qos: .utility)
        )
        memoryPressureSource.setEventHandler { [weak self] in
            self?.removeAll()
            AppLogger.ui.warning("Image thumbnail cache cleared due to memory pressure")
        }
        memoryPressureSource.resume()
    }

    func image(forKey key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    func setImage(_ image: NSImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString, cost: estimatedCost(of: image))
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    private func estimatedCost(of image: NSImage) -> Int {
        if let rep = image.representations.first {
            let pixels = max(rep.pixelsWide * rep.pixelsHigh, 1)
            return pixels * 4
        }
        let width = max(Int(image.size.width), 1)
        let height = max(Int(image.size.height), 1)
        return width * height * 4
    }
}
