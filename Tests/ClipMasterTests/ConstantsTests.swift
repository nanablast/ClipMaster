import AppKit
import HotKey
import XCTest
@testable import ClipMaster

final class ConstantsTests: XCTestCase {
    func testNormalizedMaxHistoryCountClampsRange() {
        XCTAssertEqual(
            Constants.normalizedMaxHistoryCount(Constants.minMaxHistoryCount - 1),
            Constants.minMaxHistoryCount
        )
        XCTAssertEqual(
            Constants.normalizedMaxHistoryCount(Constants.maxMaxHistoryCount + 1),
            Constants.maxMaxHistoryCount
        )
        XCTAssertEqual(
            Constants.normalizedMaxHistoryCount(Constants.defaultMaxHistoryCount),
            Constants.defaultMaxHistoryCount
        )
    }

    func testNormalizedGlobalHotKeyModifiersKeepsAllowedModifiersOnly() {
        let modifiers: NSEvent.ModifierFlags = [.command, .shift, .capsLock, .function]
        XCTAssertEqual(
            Constants.normalizedGlobalHotKeyModifiers(modifiers),
            [.command, .shift]
        )
    }

    func testStoredGlobalHotKeyFallsBackToDefaultForInvalidKey() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }

        defaults.set(Int(UInt32.max), forKey: Constants.UserDefaultsKeys.quickPasteHotKeyCode)
        defaults.set(Int(NSEvent.ModifierFlags.command.carbonFlags), forKey: Constants.UserDefaultsKeys.quickPasteHotKeyModifiers)

        XCTAssertEqual(
            Constants.storedGlobalHotKey(for: .quickPaste, defaults: defaults),
            Constants.GlobalHotKeyAction.quickPaste.defaultKeyCombo
        )
    }

    func testStoredGlobalHotKeyUsesPersistedValidValue() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }

        let expected = KeyCombo(key: .k, modifiers: [.command, .option])
        defaults.set(Int(expected.carbonKeyCode), forKey: Constants.UserDefaultsKeys.pasteQueueHotKeyCode)
        defaults.set(Int(expected.carbonModifiers), forKey: Constants.UserDefaultsKeys.pasteQueueHotKeyModifiers)

        XCTAssertEqual(
            Constants.storedGlobalHotKey(for: .pasteQueue, defaults: defaults),
            expected
        )
    }
}
