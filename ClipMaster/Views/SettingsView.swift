import AppKit
import HotKey
import LaunchAtLogin
import SwiftUI

struct SettingsView: View {
    @AppStorage(Constants.UserDefaultsKeys.maxHistoryCount)
    private var maxHistoryCount: Int = Constants.defaultMaxHistoryCount

    @AppStorage(Constants.UserDefaultsKeys.soundEnabled)
    private var soundEnabled: Bool = true

    @AppStorage(Constants.UserDefaultsKeys.soundName)
    private var soundName: String = Constants.defaultSoundName

    @AppStorage(Constants.UserDefaultsKeys.quickPasteHotKeyCode)
    private var quickPasteHotKeyCode: Int = Int(Constants.GlobalHotKeyAction.quickPaste.defaultKeyCombo.carbonKeyCode)

    @AppStorage(Constants.UserDefaultsKeys.quickPasteHotKeyModifiers)
    private var quickPasteHotKeyModifiers: Int = Int(Constants.GlobalHotKeyAction.quickPaste.defaultKeyCombo.carbonModifiers)

    @AppStorage(Constants.UserDefaultsKeys.pasteQueueHotKeyCode)
    private var pasteQueueHotKeyCode: Int = Int(Constants.GlobalHotKeyAction.pasteQueue.defaultKeyCombo.carbonKeyCode)

    @AppStorage(Constants.UserDefaultsKeys.pasteQueueHotKeyModifiers)
    private var pasteQueueHotKeyModifiers: Int = Int(Constants.GlobalHotKeyAction.pasteQueue.defaultKeyCombo.carbonModifiers)

    @AppStorage(Constants.UserDefaultsKeys.screenshotOCRHotKeyCode)
    private var screenshotOCRHotKeyCode: Int = Int(Constants.GlobalHotKeyAction.screenshotOCR.defaultKeyCombo.carbonKeyCode)

    @AppStorage(Constants.UserDefaultsKeys.screenshotOCRHotKeyModifiers)
    private var screenshotOCRHotKeyModifiers: Int = Int(Constants.GlobalHotKeyAction.screenshotOCR.defaultKeyCombo.carbonModifiers)

    @State private var showClearAllConfirmation = false
    @State private var accessibilityGranted = false
    @State private var screenCaptureGranted = false
    @State private var hotKeyErrorMessage: String?

    var body: some View {
        Form {
            Section("通用") {
                LaunchAtLogin.Toggle("开机自动启动")

                Toggle("复制时播放提示音", isOn: $soundEnabled)

                if soundEnabled {
                    Picker("提示音效", selection: $soundName) {
                        ForEach(Constants.systemSounds, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .onChange(of: soundName) { newValue in
                        NSSound(named: newValue)?.play()
                    }
                }

                HStack {
                    Text("最大历史条数")
                    Spacer()
                    TextField("", value: $maxHistoryCount, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: maxHistoryCount) { newValue in
                            let normalized = Constants.normalizedMaxHistoryCount(newValue)
                            if normalized != newValue {
                                maxHistoryCount = normalized
                            }
                        }
                }
                Text("范围：\(Constants.minMaxHistoryCount)-\(Constants.maxMaxHistoryCount)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Section("全局快捷键") {
                hotKeyRecorderRow(for: .quickPaste)
                hotKeyRecorderRow(for: .pasteQueue)
                hotKeyRecorderRow(for: .screenshotOCR)

                HStack {
                    Spacer()
                    Button("恢复全部默认") {
                        restoreAllHotKeys()
                    }
                    .buttonStyle(.plain)
                }

                if let hotKeyErrorMessage {
                    Text(hotKeyErrorMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            }

            Section("面板内快捷键（暂不支持修改）") {
                shortcutRow("粘贴选中项", shortcut: "⏎")
                shortcutRow("粘贴为纯文本 / OCR文字", shortcut: "⇧ ⏎")
                shortcutRow("快速选择粘贴", shortcut: "0-9")
                shortcutRow("删除选中项", shortcut: "⌘ ⌫")
            }

            Section("权限状态") {
                permissionStatusRow("辅助功能", granted: accessibilityGranted)
                permissionStatusRow("录屏权限", granted: screenCaptureGranted)

                HStack {
                    Button("刷新状态") {
                        refreshPermissionStatus()
                    }
                    Spacer()
                    if !accessibilityGranted {
                        Button("请求辅助功能") {
                            SystemPermissionService.requestAccessibilityPrompt()
                            refreshPermissionStatus(after: 0.25)
                        }
                    }
                    if !screenCaptureGranted {
                        Button("请求录屏权限") {
                            SystemPermissionService.requestScreenCapturePrompt()
                            refreshPermissionStatus(after: 0.25)
                        }
                    }
                }
                .buttonStyle(.plain)

                HStack {
                    Button("打开辅助功能设置") {
                        SystemPermissionService.openAccessibilitySettings()
                    }
                    Spacer()
                    Button("打开录屏设置") {
                        SystemPermissionService.openScreenCaptureSettings()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))

                Text("如权限异常，可先执行 deploy 脚本重置，再在此刷新。")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Section("数据") {
                Button("清空所有历史记录") {
                    showClearAllConfirmation = true
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 520)
        .alert("确认清空所有历史记录？", isPresented: $showClearAllConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                clearAllHistory()
            }
        } message: {
            Text("此操作不可撤销。")
        }
        .onAppear {
            maxHistoryCount = Constants.normalizedMaxHistoryCount(maxHistoryCount)
            refreshPermissionStatus()
            normalizeStoredHotKeys()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionStatus()
        }
    }

    private func shortcutRow(_ label: String, shortcut: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(shortcut)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .font(.system(size: 12, design: .monospaced))
        }
    }

    private func hotKeyRecorderRow(for action: Constants.GlobalHotKeyAction) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(action.title)
            Spacer()
            ShortcutRecorderField(
                keyCombo: binding(for: action),
                onRecord: { newValue in
                    saveHotKey(newValue, for: action)
                }
            )
            .frame(width: 130)

            Button("恢复默认") {
                saveHotKey(action.defaultKeyCombo, for: action)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
        }
    }

    private func binding(for action: Constants.GlobalHotKeyAction) -> Binding<KeyCombo> {
        Binding(
            get: { currentKeyCombo(for: action) },
            set: { saveHotKey($0, for: action) }
        )
    }

    private func currentKeyCombo(for action: Constants.GlobalHotKeyAction) -> KeyCombo {
        switch action {
        case .quickPaste:
            Constants.globalHotKey(
                keyCode: quickPasteHotKeyCode,
                modifiers: quickPasteHotKeyModifiers,
                fallback: action.defaultKeyCombo
            )
        case .pasteQueue:
            Constants.globalHotKey(
                keyCode: pasteQueueHotKeyCode,
                modifiers: pasteQueueHotKeyModifiers,
                fallback: action.defaultKeyCombo
            )
        case .screenshotOCR:
            Constants.globalHotKey(
                keyCode: screenshotOCRHotKeyCode,
                modifiers: screenshotOCRHotKeyModifiers,
                fallback: action.defaultKeyCombo
            )
        }
    }

    private func setCurrentKeyCombo(_ keyCombo: KeyCombo, for action: Constants.GlobalHotKeyAction) {
        let normalized = Constants.normalizedGlobalHotKey(keyCombo)
        switch action {
        case .quickPaste:
            quickPasteHotKeyCode = Int(normalized.carbonKeyCode)
            quickPasteHotKeyModifiers = Int(normalized.carbonModifiers)
        case .pasteQueue:
            pasteQueueHotKeyCode = Int(normalized.carbonKeyCode)
            pasteQueueHotKeyModifiers = Int(normalized.carbonModifiers)
        case .screenshotOCR:
            screenshotOCRHotKeyCode = Int(normalized.carbonKeyCode)
            screenshotOCRHotKeyModifiers = Int(normalized.carbonModifiers)
        }
    }

    private func saveHotKey(_ keyCombo: KeyCombo, for action: Constants.GlobalHotKeyAction) {
        let normalized = Constants.normalizedGlobalHotKey(keyCombo)
        let previous = snapshotHotKeyStorage()
        var candidate = allCurrentKeyCombos()
        candidate[action] = normalized

        do {
            try HotKeyManager.shared.validate(candidate)
            setCurrentKeyCombo(normalized, for: action)
            try HotKeyManager.shared.reloadFromUserDefaults()
            hotKeyErrorMessage = nil
        } catch {
            restoreHotKeyStorage(previous)
            try? HotKeyManager.shared.reloadFromUserDefaults()
            hotKeyErrorMessage = error.localizedDescription
            NSSound.beep()
        }
    }

    private func restoreAllHotKeys() {
        let previous = snapshotHotKeyStorage()
        do {
            try HotKeyManager.shared.restoreDefaults()
            syncHotKeyStorageFromDefaults()
            hotKeyErrorMessage = nil
        } catch {
            restoreHotKeyStorage(previous)
            try? HotKeyManager.shared.reloadFromUserDefaults()
            hotKeyErrorMessage = error.localizedDescription
            NSSound.beep()
        }
    }

    private func allCurrentKeyCombos() -> [Constants.GlobalHotKeyAction: KeyCombo] {
        Dictionary(uniqueKeysWithValues: Constants.GlobalHotKeyAction.allCases.map { action in
            (action, currentKeyCombo(for: action))
        })
    }

    private func snapshotHotKeyStorage() -> [Constants.GlobalHotKeyAction: KeyCombo] {
        allCurrentKeyCombos()
    }

    private func restoreHotKeyStorage(_ snapshot: [Constants.GlobalHotKeyAction: KeyCombo]) {
        for action in Constants.GlobalHotKeyAction.allCases {
            guard let keyCombo = snapshot[action] else { continue }
            setCurrentKeyCombo(keyCombo, for: action)
        }
    }

    private func syncHotKeyStorageFromDefaults() {
        for action in Constants.GlobalHotKeyAction.allCases {
            setCurrentKeyCombo(Constants.storedGlobalHotKey(for: action), for: action)
        }
    }

    private func normalizeStoredHotKeys() {
        syncHotKeyStorageFromDefaults()
    }

    private func permissionStatusRow(_ label: String, granted: Bool) -> some View {
        HStack {
            Text(label)
            Spacer()
            Label(
                granted ? "已授权" : "未授权",
                systemImage: granted ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(granted ? .green : .orange)
        }
    }

    private func refreshPermissionStatus(after delay: TimeInterval = 0) {
        let update = {
            let snapshot = SystemPermissionService.snapshot()
            accessibilityGranted = snapshot.accessibilityGranted
            screenCaptureGranted = snapshot.screenCaptureGranted
        }
        if delay <= 0 {
            update()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: update)
        }
    }

    private func clearAllHistory() {
        do {
            try StorageService.shared.deleteAll()
            ToastService.shared.show(
                message: "已清空所有历史记录",
                systemImage: "checkmark.circle.fill",
                tintColor: .systemGreen
            )
        } catch {
            ToastService.shared.show(
                message: "清空失败",
                systemImage: "xmark.circle.fill",
                tintColor: .systemRed
            )
        }
    }
}
