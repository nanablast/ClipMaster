import AppKit
import HotKey

final class HotKeyManager {
    static let shared = HotKeyManager()

    enum ValidationError: LocalizedError, Equatable {
        case unsupportedKey(action: Constants.GlobalHotKeyAction)
        case missingRequiredModifiers(action: Constants.GlobalHotKeyAction)
        case duplicateShortcut(first: Constants.GlobalHotKeyAction, second: Constants.GlobalHotKeyAction)
        case reservedShortcut(action: Constants.GlobalHotKeyAction)
        case systemShortcutConflict(action: Constants.GlobalHotKeyAction)

        var errorDescription: String? {
            switch self {
            case let .unsupportedKey(action):
                "\(action.title) 的快捷键无效。"
            case let .missingRequiredModifiers(action):
                "\(action.title) 需要至少包含 Command、Option 或 Control。"
            case let .duplicateShortcut(first, second):
                "\(first.title) 与 \(second.title) 不能使用相同快捷键。"
            case let .reservedShortcut(action):
                "\(action.title) 不能与面板内固定快捷键冲突。"
            case let .systemShortcutConflict(action):
                "\(action.title) 与系统快捷键冲突。"
            }
        }
    }

    private var hotKeys: [Constants.GlobalHotKeyAction: HotKey] = [:]

    /// ⌘; — toggle the floating quick-paste panel at cursor
    var onQuickPaste: (() -> Void)?
    /// ⌘' — toggle paste queue mode
    var onPasteQueue: (() -> Void)?
    /// ⌘⇧O — screenshot region OCR
    var onScreenshotOCR: (() -> Void)?

    private init() {}

    func reloadFromUserDefaults(defaults: UserDefaults = .standard) throws {
        let keyCombos = storedKeyCombos(defaults: defaults)

        do {
            try validate(keyCombos)
            apply(keyCombos)
        } catch {
            if hotKeys.isEmpty {
                persist(defaultKeyCombos, defaults: defaults)
                apply(defaultKeyCombos)
            }
            throw error
        }
    }

    func restoreDefaults(defaults: UserDefaults = .standard) throws {
        for action in Constants.GlobalHotKeyAction.allCases {
            defaults.set(Int(action.defaultKeyCombo.carbonKeyCode), forKey: action.keyCodeDefaultsKey)
            defaults.set(Int(action.defaultKeyCombo.carbonModifiers), forKey: action.modifiersDefaultsKey)
        }
        try reloadFromUserDefaults(defaults: defaults)
    }

    func validate(_ keyCombos: [Constants.GlobalHotKeyAction: KeyCombo]) throws {
        let normalizedKeyCombos = keyCombos.mapValues(Constants.normalizedGlobalHotKey)
        let systemKeyCombos = KeyCombo.systemKeyCombos()

        for action in Constants.GlobalHotKeyAction.allCases {
            guard let keyCombo = normalizedKeyCombos[action] else { continue }

            guard keyCombo.key != nil else {
                throw ValidationError.unsupportedKey(action: action)
            }

            let requiredModifiers = keyCombo.modifiers.intersection(Constants.requiredGlobalHotKeyModifiers)
            guard !requiredModifiers.isEmpty else {
                throw ValidationError.missingRequiredModifiers(action: action)
            }

            if Constants.reservedGlobalHotKeyCombos.contains(keyCombo) {
                throw ValidationError.reservedShortcut(action: action)
            }

            if systemKeyCombos.contains(keyCombo) {
                throw ValidationError.systemShortcutConflict(action: action)
            }
        }

        let actions = Constants.GlobalHotKeyAction.allCases
        for index in actions.indices {
            let action = actions[index]
            guard let current = normalizedKeyCombos[action] else { continue }

            for otherIndex in actions.index(after: index)..<actions.endIndex {
                let otherAction = actions[otherIndex]
                guard let other = normalizedKeyCombos[otherAction] else { continue }
                if current == other {
                    throw ValidationError.duplicateShortcut(first: action, second: otherAction)
                }
            }
        }
    }

    func unregister() {
        hotKeys.removeAll()
    }

    private var defaultKeyCombos: [Constants.GlobalHotKeyAction: KeyCombo] {
        Dictionary(uniqueKeysWithValues: Constants.GlobalHotKeyAction.allCases.map { action in
            (action, action.defaultKeyCombo)
        })
    }

    private func storedKeyCombos(defaults: UserDefaults) -> [Constants.GlobalHotKeyAction: KeyCombo] {
        Dictionary(uniqueKeysWithValues: Constants.GlobalHotKeyAction.allCases.map { action in
            (action, Constants.storedGlobalHotKey(for: action, defaults: defaults))
        })
    }

    private func apply(_ keyCombos: [Constants.GlobalHotKeyAction: KeyCombo]) {
        hotKeys.removeAll()
        for action in Constants.GlobalHotKeyAction.allCases {
            guard let keyCombo = keyCombos[action] else { continue }
            let hotKey = HotKey(keyCombo: keyCombo)
            hotKey.keyDownHandler = handler(for: action)
            hotKeys[action] = hotKey
        }
    }

    private func persist(
        _ keyCombos: [Constants.GlobalHotKeyAction: KeyCombo],
        defaults: UserDefaults
    ) {
        for action in Constants.GlobalHotKeyAction.allCases {
            guard let keyCombo = keyCombos[action] else { continue }
            defaults.set(Int(keyCombo.carbonKeyCode), forKey: action.keyCodeDefaultsKey)
            defaults.set(Int(keyCombo.carbonModifiers), forKey: action.modifiersDefaultsKey)
        }
    }

    private func handler(for action: Constants.GlobalHotKeyAction) -> (() -> Void)? {
        switch action {
        case .quickPaste:
            onQuickPaste
        case .pasteQueue:
            onPasteQueue
        case .screenshotOCR:
            onScreenshotOCR
        }
    }
}
