import AppKit
import SwiftUI

final class ToastService {
    static let shared = ToastService()

    private var panel: ToastPanel?
    private var dismissWorkItem: DispatchWorkItem?

    private init() {}

    func show(
        message: String,
        systemImage: String,
        tintColor: NSColor,
        duration: TimeInterval = 1.2
    ) {
        DispatchQueue.main.async {
            self.present(
                message: message,
                systemImage: systemImage,
                tintColor: tintColor,
                duration: duration
            )
        }
    }

    private func present(
        message: String,
        systemImage: String,
        tintColor: NSColor,
        duration: TimeInterval
    ) {
        dismiss(animated: false)

        let rootView = ToastView(
            message: message,
            systemImage: systemImage,
            tintColor: Color(nsColor: tintColor)
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize

        let panel = ToastPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = hostingView
        panel.alphaValue = 0
        panel.setFrameOrigin(panelOrigin(for: size))
        panel.orderFrontRegardless()
        self.panel = panel

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.dismiss(animated: true)
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func panelOrigin(for size: NSSize) -> NSPoint {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let screen else { return NSPoint(x: 40, y: 40) }
        let frame = screen.visibleFrame
        let x = frame.maxX - size.width - 20
        let y = frame.maxY - size.height - 20
        return NSPoint(x: x, y: y)
    }

    private func dismiss(animated: Bool) {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        guard let panel else { return }
        self.panel = nil

        guard animated else {
            panel.orderOut(nil)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }
}

private final class ToastPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct ToastView: View {
    let message: String
    let systemImage: String
    let tintColor: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tintColor)

            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
        .frame(maxWidth: 320)
    }
}
