# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic Versioning.

## [Unreleased]

### Added

- Open-source project docs (`README`, `CONTRIBUTING`, `CODE_OF_CONDUCT`, `LICENSE`)

## [0.1.6] - 2026-05-16

### Added

- Save image to ~/Downloads via context menu on image clipboard items

## [0.1.5] - 2026-04-26

### Added

- Configurable global hotkeys in Settings for:
  - quick paste panel
  - paste queue mode
  - screenshot OCR

### Changed

- Global hotkey settings now validate duplicate bindings, reserved in-panel shortcuts, and system shortcut conflicts.
- In-panel shortcuts (`⏎`, `⇧⏎`, `0-9`, `⌘⌫`) remain fixed in this release.

## [0.1.4] - 2026-02-15

### Changed

- OCR text recognition now uses multi-pass fallback for CJK-heavy content:
  - mixed CJK (`zh-Hans`/`zh-Hant`/`ja-JP`/`en-US`)
  - Japanese-priority pass
  - Japanese-only pass
  - auto-language fallback

### Fixed

- Fixed Japanese OCR returning "未找到文字" for some screenshots/images.

### Notes

- `v0.1.2` and `v0.1.3` may still fail on some Japanese inputs.
- Users should upgrade to `v0.1.4` or newer for Japanese OCR.

## [1.0.0] - 2026-02-13

### Added

- Menu bar clipboard manager app (`LSUIElement`)
- Clipboard history for text, link, file and image content
- OCR workflows:
  - automatic OCR for copied images
  - screenshot region OCR via `⌘⇧O`
- Quick paste panel via `⌘;` (non-focus-stealing)
- Paste queue mode via `⌘'`
- Search/filter, pagination and history limit controls
- Startup login option and sound settings

### Changed

- Adaptive clipboard polling strategy (active/idle intervals)
- Database search accelerated with FTS + LIKE fallback compatibility
- Main panel search/load-more request coalescing and cancellation
- Quick panel search switched to async debounce query
- Added permissions status display and quick-open settings actions
- Added structured logging via `os.Logger`

### Fixed

- Selection/refresh behaviors after delete actions in quick panel
- Cursor/scroll behavior edge cases in quick and main panels
- Event tap recovery path for paste queue mode
- Safer database recovery path with backup before destructive reset
