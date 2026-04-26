import AppKit
import HotKey

enum Constants {
    static let defaultMaxHistoryCount = 500
    static let minMaxHistoryCount = 50
    static let maxMaxHistoryCount = 5_000
    static let clipboardPollActiveInterval: TimeInterval = 0.20
    static let clipboardPollIdleInterval: TimeInterval = 1.00
    static let clipboardIdleThreshold = 8
    static let clipboardPollLeeway: TimeInterval = 0.05
    static let accessibilityPromptMinInterval: TimeInterval = 24 * 60 * 60
    static let databaseFileName = "ClipMaster.sqlite"
    static let defaultSoundName = "Tink"
    static let imagePlaceholderText = "[图片]"
    static let debugLogMaxSizeBytes = 1_048_576 // 1 MB

    static let systemSounds = [
        "Basso", "Blow", "Bottle", "Frog", "Funk",
        "Glass", "Hero", "Morse", "Ping", "Pop",
        "Purr", "Sosumi", "Submarine", "Tink",
    ]

    enum UserDefaultsKeys {
        static let maxHistoryCount = "maxHistoryCount"
        static let launchAtLogin = "launchAtLogin"
        static let soundEnabled = "soundEnabled"
        static let soundName = "soundName"
        static let debugLoggingEnabled = "debugLoggingEnabled"
        static let lastAccessibilityPromptAt = "lastAccessibilityPromptAt"
        static let quickPasteHotKeyCode = "quickPasteHotKeyCode"
        static let quickPasteHotKeyModifiers = "quickPasteHotKeyModifiers"
        static let pasteQueueHotKeyCode = "pasteQueueHotKeyCode"
        static let pasteQueueHotKeyModifiers = "pasteQueueHotKeyModifiers"
        static let screenshotOCRHotKeyCode = "screenshotOCRHotKeyCode"
        static let screenshotOCRHotKeyModifiers = "screenshotOCRHotKeyModifiers"
    }

    enum GlobalHotKeyAction: String, CaseIterable, Identifiable {
        case quickPaste
        case pasteQueue
        case screenshotOCR

        var id: String { rawValue }

        var title: String {
            switch self {
            case .quickPaste:
                "快速粘贴面板（不失焦）"
            case .pasteQueue:
                "粘贴队列模式"
            case .screenshotOCR:
                "截图区域 OCR"
            }
        }

        var keyCodeDefaultsKey: String {
            switch self {
            case .quickPaste:
                UserDefaultsKeys.quickPasteHotKeyCode
            case .pasteQueue:
                UserDefaultsKeys.pasteQueueHotKeyCode
            case .screenshotOCR:
                UserDefaultsKeys.screenshotOCRHotKeyCode
            }
        }

        var modifiersDefaultsKey: String {
            switch self {
            case .quickPaste:
                UserDefaultsKeys.quickPasteHotKeyModifiers
            case .pasteQueue:
                UserDefaultsKeys.pasteQueueHotKeyModifiers
            case .screenshotOCR:
                UserDefaultsKeys.screenshotOCRHotKeyModifiers
            }
        }

        var defaultKeyCombo: KeyCombo {
            switch self {
            case .quickPaste:
                KeyCombo(key: .semicolon, modifiers: .command)
            case .pasteQueue:
                KeyCombo(key: .quote, modifiers: .command)
            case .screenshotOCR:
                KeyCombo(key: .o, modifiers: [.command, .shift])
            }
        }
    }

    static let allowedGlobalHotKeyModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    static let requiredGlobalHotKeyModifiers: NSEvent.ModifierFlags = [.command, .option, .control]
    static let reservedGlobalHotKeyCombos: [KeyCombo] = [
        KeyCombo(key: .return),
        KeyCombo(key: .return, modifiers: .shift),
        KeyCombo(key: .zero),
        KeyCombo(key: .one),
        KeyCombo(key: .two),
        KeyCombo(key: .three),
        KeyCombo(key: .four),
        KeyCombo(key: .five),
        KeyCombo(key: .six),
        KeyCombo(key: .seven),
        KeyCombo(key: .eight),
        KeyCombo(key: .nine),
        KeyCombo(key: .delete, modifiers: .command),
    ]

    static func normalizedMaxHistoryCount(_ value: Int) -> Int {
        min(max(value, minMaxHistoryCount), maxMaxHistoryCount)
    }

    static func normalizedGlobalHotKeyModifiers(_ modifiers: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        modifiers.intersection(allowedGlobalHotKeyModifiers)
    }

    static func normalizedGlobalHotKey(_ keyCombo: KeyCombo) -> KeyCombo {
        KeyCombo(
            carbonKeyCode: keyCombo.carbonKeyCode,
            carbonModifiers: normalizedGlobalHotKeyModifiers(keyCombo.modifiers).carbonFlags
        )
    }

    static func globalHotKey(
        keyCode: Int,
        modifiers: Int,
        fallback: KeyCombo
    ) -> KeyCombo {
        let keyCombo = normalizedGlobalHotKey(
            KeyCombo(
                carbonKeyCode: UInt32(keyCode),
                carbonModifiers: UInt32(modifiers)
            )
        )
        return keyCombo.key == nil ? fallback : keyCombo
    }

    static func storedGlobalHotKey(
        for action: GlobalHotKeyAction,
        defaults: UserDefaults = .standard
    ) -> KeyCombo {
        guard
            let keyCode = defaults.object(forKey: action.keyCodeDefaultsKey) as? Int,
            let modifiers = defaults.object(forKey: action.modifiersDefaultsKey) as? Int
        else {
            return action.defaultKeyCombo
        }

        return globalHotKey(
            keyCode: keyCode,
            modifiers: modifiers,
            fallback: action.defaultKeyCombo
        )
    }
}
