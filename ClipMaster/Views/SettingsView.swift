import AppKit
import SwiftUI
import LaunchAtLogin

struct SettingsView: View {
    @AppStorage(Constants.UserDefaultsKeys.maxHistoryCount)
    private var maxHistoryCount: Int = Constants.defaultMaxHistoryCount

    @AppStorage(Constants.UserDefaultsKeys.soundEnabled)
    private var soundEnabled: Bool = true

    @AppStorage(Constants.UserDefaultsKeys.soundName)
    private var soundName: String = Constants.defaultSoundName
    @State private var showClearAllConfirmation = false
    @State private var accessibilityGranted = false
    @State private var screenCaptureGranted = false

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

            Section("快捷键") {
                shortcutRow("快速粘贴面板（不失焦）", shortcut: "⌘ ;")
                shortcutRow("粘贴队列模式", shortcut: "⌘ '")
                shortcutRow("截图区域 OCR", shortcut: "⌘ ⇧ O")
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
        .frame(width: 400, height: 440)
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
