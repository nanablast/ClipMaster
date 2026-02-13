import AppKit

/// Paste Queue: copy multiple items, then paste them one-by-one in FIFO order.
/// Activate with ⌘' , then each ⌘V pastes the next item in the queue.
final class PasteQueue: ObservableObject {
    static let shared = PasteQueue()

    @Published private(set) var isActive = false
    @Published private(set) var remaining = 0
    var onStateChanged: ((Bool) -> Void)?

    private var queue: [ClipboardItem] = []
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {}

    enum EventTapRecoveryResult: Equatable {
        case noAction
        case reenabled
        case shouldStop
    }

    /// Start paste queue mode with the given items (FIFO order).
    func start(with items: [ClipboardItem]) {
        runOnMainAsync { [self] in
            guard !items.isEmpty else { return }
            self.queue = items
            self.remaining = items.count
            self.isActive = self.installEventTap()
            if !self.isActive {
                self.queue.removeAll()
                self.remaining = 0
            }
            self.notifyStateChanged()
        }
    }

    /// Stop paste queue mode and clean up.
    func stop() {
        runOnMainAsync { [self] in
            self.stopInternal()
        }
    }

    /// Paste the next item in the queue. Returns false if queue is empty.
    @discardableResult
    func pasteNext() -> Bool {
        guard Thread.isMainThread else {
            assertionFailure("[ClipMaster] pasteNext expected main-thread execution")
            return false
        }

        while !queue.isEmpty {
            let item = queue.removeFirst()
            remaining = queue.count

            if PasteService.writeToPasteboard(item) {
                if queue.isEmpty {
                    stopInternal()
                }
                return true
            }
        }

        stopInternal()
        return false
    }

    // MARK: - Event Tap to intercept ⌘V

    @discardableResult
    private func installEventTap() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: pasteQueueEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            AppLogger.queue.error("Failed to create event tap (accessibility permission required)")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func removeEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    static func recoveryResult(isActive: Bool, reenabled: Bool) -> EventTapRecoveryResult {
        guard isActive else { return .noAction }
        return reenabled ? .reenabled : .shouldStop
    }

    private func recoverEventTapIfNeeded() {
        guard isActive, let tap = eventTap else { return }

        CGEvent.tapEnable(tap: tap, enable: true)
        let result = Self.recoveryResult(isActive: isActive, reenabled: CGEvent.tapIsEnabled(tap: tap))
        guard result != .shouldStop else {
            AppLogger.queue.error("PasteQueue event tap recover failed; stopping queue")
            stopInternal()
            ToastService.shared.show(
                message: "粘贴队列已停止，请重新开启",
                systemImage: "exclamationmark.triangle.fill",
                tintColor: .systemOrange
            )
            return
        }
        if result == .reenabled {
            AppLogger.queue.info("PasteQueue event tap recovered")
        }
    }

    fileprivate func handleEventTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            recoverEventTapIfNeeded()
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Intercept ⌘V (keyCode 0x09 = V)
        if keyCode == 0x09 && flags.contains(.maskCommand) {
            // Replace pasteboard content with next queue item
            if PasteQueue.shared.pasteNext() {
                // Let the ⌘V pass through — pasteboard already updated
                return Unmanaged.passUnretained(event)
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func stopInternal() {
        queue.removeAll()
        remaining = 0
        isActive = false
        removeEventTap()
        notifyStateChanged()
    }

    private func notifyStateChanged() {
        onStateChanged?(isActive)
    }

    private func runOnMainAsync(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
            return
        }
        DispatchQueue.main.async(execute: work)
    }
}

func pasteQueueEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let queue = Unmanaged<PasteQueue>.fromOpaque(userInfo).takeUnretainedValue()
    return queue.handleEventTapEvent(type: type, event: event)
}
