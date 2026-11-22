import AppKit
import Combine

struct ClipboardPollPolicy {
    private(set) var interval: TimeInterval = Constants.clipboardPollActiveInterval
    private var lastClipboardActivity: TimeInterval

    init(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        lastClipboardActivity = now
    }

    mutating func reset(now: TimeInterval) {
        interval = Constants.clipboardPollActiveInterval
        lastClipboardActivity = now
    }

    @discardableResult
    mutating func recordPoll(hasChanges: Bool, userIdleDuration: TimeInterval, now: TimeInterval) -> Bool {
        if hasChanges { lastClipboardActivity = now }
        let isIdle = userIdleDuration.isFinite
            && userIdleDuration >= Constants.clipboardIdleDelay
            && now - lastClipboardActivity >= Constants.clipboardIdleDelay
        let next = isIdle ? Constants.clipboardPollIdleInterval : Constants.clipboardPollActiveInterval
        guard next != interval else { return false }
        interval = next
        return true
    }

    static func userIdleDuration() -> TimeInterval {
        // Reads an elapsed duration, without installing a keyboard/event monitor.
        CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: UInt32.max)!
        )
    }
}

private final class ClipboardProcessingSession {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
    }

    // Serialize the final storage commit with stop(). Expensive OCR runs outside this lock.
    func commitIfActive<T>(_ work: () throws -> T) rethrows -> T? {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return nil }
        return try work()
    }
}

/// Polling, lifecycle state, buffering and publication are confined to the main queue.
/// Only immutable snapshots and a cancellable session cross to the processing queue.
final class ClipboardMonitor: ObservableObject {
    @Published private(set) var latestItem: ClipboardItem?

    private enum SuspensionReason: Hashable {
        case systemSleep, screenSleep, inactiveSession
    }

    private let reader: ClipboardSnapshotReading
    private let notificationCenter: NotificationCenter
    private let automaticallyPoll: Bool
    private let userIdleDuration: () -> TimeInterval
    private let uptime: () -> TimeInterval
    private let prepare: (ClipboardSnapshot) -> PreparedClipboardItem?
    private let persist: (PreparedClipboardItem) throws -> ClipboardItem
    private let didCopy: () -> Void
    private let onOversizedCopy: () -> Void
    private let processingQueue = DispatchQueue(label: "com.clipmaster.clipboard.processing", qos: .userInitiated)

    private var pollTimer: DispatchSourceTimer?
    private var pollPolicy: ClipboardPollPolicy
    private var lastChangeCount: Int
    private var lastObservedChangeCount: Int
    private var retryChangeCount: Int?
    private var readAttempts = 0
    private var snapshots = ClipboardSnapshotBuffer()
    private var session: ClipboardProcessingSession?
    private var isProcessing = false
    private var suspensionReasons: Set<SuspensionReason> = []
    private var observers: [NSObjectProtocol] = []

    init(
        reader: ClipboardSnapshotReading = PasteboardSnapshotReader(),
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        automaticallyPoll: Bool = true,
        userIdleDuration: @escaping () -> TimeInterval = ClipboardPollPolicy.userIdleDuration,
        uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        prepare: @escaping (ClipboardSnapshot) -> PreparedClipboardItem? = ClipboardSnapshotProcessor().prepare,
        persist: @escaping (PreparedClipboardItem) throws -> ClipboardItem = { try $0.persist(using: .shared) },
        didCopy: (() -> Void)? = nil,
        onOversizedCopy: (() -> Void)? = nil
    ) {
        self.reader = reader
        self.notificationCenter = notificationCenter
        self.automaticallyPoll = automaticallyPoll
        self.userIdleDuration = userIdleDuration
        self.uptime = uptime
        self.prepare = prepare
        self.persist = persist
        self.didCopy = didCopy ?? Self.playCopySoundIfNeeded
        self.onOversizedCopy = onOversizedCopy ?? {}
        self.lastChangeCount = reader.changeCount
        self.lastObservedChangeCount = reader.changeCount
        self.pollPolicy = ClipboardPollPolicy(now: uptime())
    }

    deinit {
        pollTimer?.cancel()
        session?.cancel()
        observers.forEach(notificationCenter.removeObserver)
    }

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        stop()
        lastChangeCount = reader.changeCount
        lastObservedChangeCount = lastChangeCount
        session = ClipboardProcessingSession()
        observeWorkspace()
        configurePollTimer()
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        cancelPollTimer()
        session?.cancel()
        session = nil
        snapshots.removeAll()
        retryChangeCount = nil
        readAttempts = 0
        pollPolicy.reset(now: uptime())
        suspensionReasons.removeAll()
        observers.forEach(notificationCenter.removeObserver)
        observers.removeAll()
        // An old worker may still be finishing OCR. It retains the processing slot until
        // its completion, so repeated stop/start cannot accumulate background jobs.
    }

    private func cancelPollTimer() {
        pollTimer?.setEventHandler {}
        pollTimer?.cancel()
        pollTimer = nil
    }

    private func configurePollTimer() {
        cancelPollTimer()
        guard automaticallyPoll, let session, suspensionReasons.isEmpty else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + pollPolicy.interval,
            repeating: pollPolicy.interval,
            leeway: .milliseconds(Int(Constants.clipboardPollLeeway * 1_000))
        )
        timer.setEventHandler { [weak self, weak session] in
            guard let self, let session, self.session === session else { return }
            self.checkForChanges()
        }
        timer.resume()
        pollTimer = timer
    }

    // Also used for an immediate check on wake and for deterministic integration tests.
    func checkForChanges() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard session != nil, suspensionReasons.isEmpty else { return }

        let observedCount = reader.changeCount
        if pollPolicy.recordPoll(
            hasChanges: observedCount != lastObservedChangeCount,
            userIdleDuration: userIdleDuration(),
            now: uptime()
        ) {
            configurePollTimer()
        }
        lastObservedChangeCount = observedCount

        // Retry a racing writer once immediately, then yield to the next timer tick.
        for _ in 0..<2 {
            let currentCount = reader.changeCount
            guard currentCount != lastChangeCount else { return }
            if retryChangeCount != currentCount {
                retryChangeCount = currentCount
                readAttempts = 0
            }

            switch reader.readSnapshot(expectedChangeCount: currentCount) {
            case .captured(let snapshot):
                lastChangeCount = currentCount
                retryChangeCount = nil
                let result = snapshots.append(snapshot)
                if !result.accepted {
                    AppLogger.clipboard.warning("Clipboard snapshot exceeds the payload byte limit; skipped")
                    onOversizedCopy()
                } else if result.droppedCount > 0 {
                    AppLogger.clipboard.warning("Clipboard backlog full; discarded \(result.droppedCount) oldest pending snapshots")
                }
                processNextSnapshot()
                return
            case .ignored:
                lastChangeCount = currentCount
                retryChangeCount = nil
                return
            case .retry:
                if reader.changeCount != currentCount { continue }
                readAttempts += 1
                if readAttempts >= Constants.clipboardReadAttemptLimit {
                    lastChangeCount = currentCount
                    retryChangeCount = nil
                    AppLogger.clipboard.debug("Clipboard data unavailable after bounded retries; skipped")
                }
                return
            }
        }
    }

    private func processNextSnapshot() {
        guard let session, !isProcessing, suspensionReasons.isEmpty,
              let snapshot = snapshots.popFirst() else { return }
        isProcessing = true
        let prepare = self.prepare
        let persist = self.persist

        processingQueue.async { [weak self] in
            let savedItem: ClipboardItem? = autoreleasepool {
                guard !session.isCancelled, let prepared = prepare(snapshot) else { return nil }
                do {
                    return try session.commitIfActive { try persist(prepared) }
                } catch {
                    AppLogger.clipboard.error("Failed to save clipboard item: \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isProcessing = false
                if self.session === session, let savedItem {
                    self.latestItem = savedItem
                    self.didCopy()
                }
                self.processNextSnapshot()
            }
        }
    }

    private func observeWorkspace() {
        guard let session else { return }
        let notifications: [(Notification.Name, Notification.Name, SuspensionReason)] = [
            (NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, .systemSleep),
            (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, .screenSleep),
            (NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification, .inactiveSession)
        ]
        for (suspend, resume, reason) in notifications {
            observers.append(notificationCenter.addObserver(forName: suspend, object: nil, queue: .main) { [weak self, weak session] _ in
                guard let self, let session, self.session === session else { return }
                self.suspensionReasons.insert(reason)
                self.cancelPollTimer()
            })
            observers.append(notificationCenter.addObserver(forName: resume, object: nil, queue: .main) { [weak self, weak session] _ in
                guard let self, let session, self.session === session,
                      self.suspensionReasons.remove(reason) != nil, self.suspensionReasons.isEmpty else { return }
                self.pollPolicy.reset(now: self.uptime())
                self.configurePollTimer()
                // Preserve the previous change count so copies made during suspension
                // are checked immediately, instead of being silently acknowledged.
                self.checkForChanges()
                self.processNextSnapshot()
            })
        }
    }

    private static func playCopySoundIfNeeded() {
        let defaults = UserDefaults.standard
        let soundOff = defaults.object(forKey: Constants.UserDefaultsKeys.soundEnabled) != nil
            && !defaults.bool(forKey: Constants.UserDefaultsKeys.soundEnabled)
        if !soundOff {
            let name = defaults.string(forKey: Constants.UserDefaultsKeys.soundName) ?? Constants.defaultSoundName
            NSSound(named: name)?.play()
        }
    }
}
