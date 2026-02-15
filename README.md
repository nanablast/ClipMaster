# ClipMaster

ClipMaster 是一个 macOS 菜单栏剪贴板管理器，定位类似 CleanClip。  
基于 Swift / SwiftUI / SPM，支持文本、链接、文件、图片与 OCR 工作流。

## 功能特性

- 菜单栏常驻（`LSUIElement=true`，无 Dock 图标）
- 剪贴板历史记录（文本 / 链接 / 文件 / 图片）
- 图片 OCR：
  - 复制图片自动 OCR
  - `⌘⇧O` 截图区域 OCR
- 快速粘贴面板（`⌘;`，不抢前台焦点）
- 粘贴队列模式（`⌘'`）
- 搜索过滤、分页加载、去重与历史上限
- 开机启动、提示音、自定义设置

## 系统要求

- macOS 13.0 及以上
- Xcode Command Line Tools（用于 `swift build`）

## 快速开始

```bash
# 1) Debug 构建
swift build

# 2) Release 构建 + 打包 .app
bash build.sh

# 3) 部署（会重置辅助功能与录屏权限）
bash deploy.sh

# 或一条命令：测试 + 构建 + 部署
bash release-check.sh
```

## 权限说明

ClipMaster 涉及以下系统权限：

- 辅助功能（用于全局快捷键/模拟粘贴等）
- 录屏权限（用于截图 OCR）

重新编译后签名变化可能导致权限失效，可执行：

```bash
tccutil reset Accessibility com.clipmaster.app
tccutil reset ScreenCapture com.clipmaster.app
```

然后在「系统设置 → 隐私与安全性」中重新授权。

## 下载版无法打开（“已损坏”）排查

如果从浏览器下载 Release 后出现“`ClipMaster.app` 已损坏，无法打开”，通常是 macOS 隔离属性触发。

执行：

```bash
xattr -dr com.apple.quarantine /Applications/ClipMaster.app
open /Applications/ClipMaster.app
```

## 数据与日志

- 数据库：`~/Library/Application Support/ClipMaster/ClipMaster.sqlite`
- 调试日志：`~/Library/Application Support/ClipMaster/debug.log`

## 快捷键

| 快捷键 | 功能 |
|--------|------|
| `⌘;` | 快速粘贴面板（不失焦） |
| `⌘'` | 粘贴队列模式 |
| `⌘⇧O` | 截图区域 OCR |
| `⏎` | 粘贴选中项（图片类型粘贴图片） |
| `⇧⏎` | 粘贴为纯文本 / OCR 文字 |
| `0-9` | 快速选择粘贴 |
| `⌘⌫` | 删除选中项 |
| 直接打字 | 搜索过滤（`⌘;` 面板中） |

## 开发

```bash
# 运行测试
swift test

# Debug 构建
swift build

# Release 构建
bash build.sh
```

## 贡献

欢迎 Issue 与 PR。请先阅读：

- [CONTRIBUTING.md](./CONTRIBUTING.md)
- [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md)

## 变更记录

见 [CHANGELOG.md](./CHANGELOG.md)。

## 许可证

[MIT](./LICENSE)
