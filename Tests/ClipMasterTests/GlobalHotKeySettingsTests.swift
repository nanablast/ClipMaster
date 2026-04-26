import AppKit
import HotKey
import XCTest
@testable import ClipMaster

final class GlobalHotKeySettingsTests: XCTestCase {
    func testValidateRejectsMissingPrimaryModifier() {
        let manager = HotKeyManager.shared

        XCTAssertThrowsError(
            try manager.validate([
                .quickPaste: KeyCombo(key: .k, modifiers: .shift),
                .pasteQueue: KeyCombo(key: .l, modifiers: .command),
                .screenshotOCR: KeyCombo(key: .o, modifiers: [.command, .shift]),
            ])
        ) { error in
            XCTAssertEqual(
                error as? HotKeyManager.ValidationError,
                .missingRequiredModifiers(action: .quickPaste)
            )
        }
    }

    func testValidateRejectsDuplicateShortcut() {
        let manager = HotKeyManager.shared
        let shared = KeyCombo(key: .k, modifiers: .command)

        XCTAssertThrowsError(
            try manager.validate([
                .quickPaste: shared,
                .pasteQueue: shared,
                .screenshotOCR: KeyCombo(key: .o, modifiers: [.command, .shift]),
            ])
        ) { error in
            XCTAssertEqual(
                error as? HotKeyManager.ValidationError,
                .duplicateShortcut(first: .quickPaste, second: .pasteQueue)
            )
        }
    }

    func testValidateRejectsReservedShortcut() {
        let manager = HotKeyManager.shared

        XCTAssertThrowsError(
            try manager.validate([
                .quickPaste: KeyCombo(key: .delete, modifiers: .command),
                .pasteQueue: KeyCombo(key: .l, modifiers: .command),
                .screenshotOCR: KeyCombo(key: .o, modifiers: [.command, .shift]),
            ])
        ) { error in
            XCTAssertEqual(
                error as? HotKeyManager.ValidationError,
                .reservedShortcut(action: .quickPaste)
            )
        }
    }
}
