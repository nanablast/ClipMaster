import Foundation
import os

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.clipmaster.app"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let clipboard = Logger(subsystem: subsystem, category: "clipboard")
    static let queue = Logger(subsystem: subsystem, category: "queue")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let ocr = Logger(subsystem: subsystem, category: "ocr")
}
