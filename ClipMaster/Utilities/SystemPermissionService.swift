import ApplicationServices
import AppKit
import CoreGraphics

enum SystemPermissionService {
    struct Snapshot: Equatable {
        let accessibilityGranted: Bool
        let screenCaptureGranted: Bool
    }

    static func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPrompt() {
        AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        )
    }

    static func isScreenCaptureGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestScreenCapturePrompt() {
        CGRequestScreenCaptureAccess()
    }

    static func snapshot(
        accessibilityProvider: () -> Bool = isAccessibilityGranted,
        screenCaptureProvider: () -> Bool = isScreenCaptureGranted
    ) -> Snapshot {
        Snapshot(
            accessibilityGranted: accessibilityProvider(),
            screenCaptureGranted: screenCaptureProvider()
        )
    }

    static func openAccessibilitySettings() {
        openSystemSettings(anchor: "Privacy_Accessibility")
    }

    static func openScreenCaptureSettings() {
        openSystemSettings(anchor: "Privacy_ScreenCapture")
    }

    private static func openSystemSettings(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
            return
        }
        if !NSWorkspace.shared.open(url),
           let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            _ = NSWorkspace.shared.open(fallback)
        }
    }
}
