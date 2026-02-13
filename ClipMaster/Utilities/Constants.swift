import Foundation

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
    }

    static func normalizedMaxHistoryCount(_ value: Int) -> Int {
        min(max(value, minMaxHistoryCount), maxMaxHistoryCount)
    }
}
