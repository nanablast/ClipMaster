import AppKit
import SwiftUI

/// A floating panel that appears at the cursor position without stealing focus.
/// Uses CGEvent tap to intercept keyboard input before it reaches the frontmost app.
final class FloatingPanel: NSPanel {
    private var hostingView: NSHostingView<AnyView>?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyHandler: ((CGEvent) -> Bool)?
    private var initialOrigin: NSPoint?
    private var retainedSelf: Unmanaged<FloatingPanel>?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: true
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    func show<Content: View>(with content: Content) {
        let hosting = NSHostingView(rootView: AnyView(content))
        hosting.frame.size = hosting.fittingSize
        contentView = hosting
        self.hostingView = hosting

        let panelSize = hosting.fittingSize
        let cursorPos = NSEvent.mouseLocation

        // Position to the right of the cursor, vertically centered on cursor
        var origin = NSPoint(
            x: cursorPos.x + 20,
            y: cursorPos.y - panelSize.height / 2
        )

        let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(cursorPos) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        if let screen = targetScreen {
            let frame = screen.visibleFrame

            // If panel would go off the right edge, show it to the left of cursor instead
            if origin.x + panelSize.width > frame.maxX - 8 {
                origin.x = cursorPos.x - panelSize.width - 20
            }

            origin.x = max(frame.minX + 8, min(origin.x, frame.maxX - panelSize.width - 8))
            origin.y = max(frame.minY + 8, min(origin.y, frame.maxY - panelSize.height - 8))
        }

        initialOrigin = origin
        setFrame(NSRect(origin: origin, size: panelSize), display: true)
        orderFrontRegardless()
    }

    func updateContent<Content: View>(with content: Content) {
        guard isVisible else { return }
        guard let hosting = hostingView else { return }

        // Reuse the same NSHostingView to avoid visible flashes while navigating.
        hosting.rootView = AnyView(content)
        hosting.layoutSubtreeIfNeeded()

        guard let origin = initialOrigin else { return }
        let newSize = hosting.fittingSize
        let currentSize = frame.size
        let sizeChanged = abs(currentSize.width - newSize.width) > 0.5
            || abs(currentSize.height - newSize.height) > 0.5

        if sizeChanged {
            setFrame(NSRect(origin: origin, size: newSize), display: true)
        }
    }

    func dismiss() {
        orderOut(nil)
        removeEventTap()
        initialOrigin = nil
    }

    // MARK: - CGEvent Tap

    /// Returns true if event tap was installed successfully.
    @discardableResult
    func installEventTap(handler: @escaping (CGEvent) -> Bool) -> Bool {
        self.keyHandler = handler

        // Listen for keyDown and flagsChanged (for tap-disabled-by-timeout recovery)
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        // Retain self so the panel stays alive while event tap is active
        let retained = Unmanaged.passRetained(self)
        self.retainedSelf = retained

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: floatingPanelEventCallback,
            userInfo: retained.toOpaque()
        ) else {
            AppLogger.ui.error("Failed to create floating panel event tap; check accessibility permission")
            // Release since tap failed
            retained.release()
            self.retainedSelf = nil
            return false
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// Called from the C callback to handle the event.
    func handleEvent(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // If the tap was disabled by timeout, re-enable it
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Only process keyDown
        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        if let handler = keyHandler, handler(event) {
            // Consumed — swallow the event
            return nil
        }

        // Not handled — pass through
        return Unmanaged.passUnretained(event)
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
        keyHandler = nil
        // Release the retained reference
        retainedSelf?.release()
        retainedSelf = nil
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - C callback (must be a free function, not a closure)

// NOTE: This must NOT be `private` — it needs C calling convention compatibility.
func floatingPanelEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let panel = Unmanaged<FloatingPanel>.fromOpaque(userInfo).takeUnretainedValue()
    return panel.handleEvent(type, event: event)
}
