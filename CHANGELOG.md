# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic Versioning.

## [Unreleased]

### Added

- Open-source project docs (`README`, `CONTRIBUTING`, `CODE_OF_CONDUCT`, `LICENSE`)

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

