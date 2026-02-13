# ClipMaster

macOS 剪贴板管理器，类似 CleanClip。Swift/SwiftUI Menu Bar App，使用 SPM 构建。

## 构建

```bash
# Debug 构建
swift build

# Release 构建 + 打包 .app
bash build.sh
```

## 部署

```bash
# 先构建，再部署（部署前会重置辅助功能权限）
bash build.sh
bash deploy.sh

# 或一条命令执行：测试 + 构建 + 部署
bash release-check.sh
```

## 注意事项

- 每次重新编译后代码签名变化，macOS 可能撤销辅助功能和录屏权限。需要在 系统设置 → 隐私与安全性 中重新授权 ClipMaster.app，或使用：
  - `tccutil reset Accessibility com.clipmaster.app`
  - `tccutil reset ScreenCapture com.clipmaster.app`
- 应用使用 `LSUIElement=true`（Info.plist），不显示 Dock 图标，仅在菜单栏显示
- 数据库存放在 `~/Library/Application Support/ClipMaster/ClipMaster.sqlite`
- 调试日志写入 `~/Library/Application Support/ClipMaster/debug.log`

## 快捷键

| 快捷键 | 功能 |
|--------|------|
| ⌘; | 快速粘贴面板（不失焦） |
| ⌘' | 粘贴队列模式 |
| ⌘⇧O | 截图区域 OCR |
| ⏎ | 粘贴选中项（图片类型粘贴图片） |
| ⇧⏎ | 粘贴为纯文本 / OCR 文字 |
| 0-9 | 快速选择粘贴 |
| ⌘⌫ | 删除选中项 |
| 直接打字 | 搜索过滤（⌘; 面板中） |

## 依赖

- GRDB.swift 6.24+ — SQLite 数据库
- HotKey 0.2+ — 全局快捷键
- LaunchAtLogin-Modern 1.1+ — 开机启动
