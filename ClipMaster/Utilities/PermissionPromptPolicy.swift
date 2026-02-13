import Foundation

enum PermissionPromptPolicy {
    static func shouldPrompt(
        now: Date,
        lastPromptAt: Date?,
        minimumInterval: TimeInterval
    ) -> Bool {
        guard let lastPromptAt else { return true }
        return now.timeIntervalSince(lastPromptAt) >= minimumInterval
    }
}
