import AppKit
import Carbon
import HotKey
import SwiftUI

struct ShortcutRecorderField: NSViewRepresentable {
    @Binding var keyCombo: KeyCombo
    var placeholder: String = "点击录制"
    var onRecord: (KeyCombo) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderFieldView {
        let view = ShortcutRecorderFieldView()
        view.placeholder = placeholder
        view.onRecord = onRecord
        view.keyCombo = keyCombo
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderFieldView, context: Context) {
        nsView.placeholder = placeholder
        nsView.onRecord = onRecord
        nsView.keyCombo = keyCombo
    }
}

final class ShortcutRecorderFieldView: NSControl {
    var onRecord: ((KeyCombo) -> Void)?
    var placeholder: String = "点击录制" {
        didSet { updateDisplay() }
    }

    var keyCombo: KeyCombo = KeyCombo(key: .space, modifiers: .command) {
        didSet {
            guard !isRecording else { return }
            updateDisplay()
        }
    }

    private var isRecording = false {
        didSet { updateDisplay() }
    }
    private var recordedModifiers: NSEvent.ModifierFlags = [] {
        didSet {
            guard isRecording else { return }
            updateDisplay()
        }
    }

    private let textField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        beginRecording()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == UInt16(kVK_Escape) {
            cancelRecording()
            return
        }

        let normalizedModifiers = Constants.normalizedGlobalHotKeyModifiers(
            event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        )
        let keyCombo = KeyCombo(
            carbonKeyCode: UInt32(event.keyCode),
            carbonModifiers: normalizedModifiers.carbonFlags
        )
        finishRecording(with: keyCombo)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }

        recordedModifiers = Constants.normalizedGlobalHotKeyModifiers(
            event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        )
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            cancelRecording()
        }
        return true
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.quaternaryLabelColor.cgColor
        layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.12).cgColor

        textField.font = .systemFont(ofSize: 12, weight: .medium)
        textField.alignment = .center
        textField.lineBreakMode = .byTruncatingTail
        textField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(textField)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        updateDisplay()
    }

    private func beginRecording() {
        isRecording = true
        recordedModifiers = []
        layer?.borderColor = NSColor.controlAccentColor.cgColor
    }

    private func cancelRecording() {
        isRecording = false
        recordedModifiers = []
        layer?.borderColor = NSColor.quaternaryLabelColor.cgColor
        updateDisplay()
    }

    private func finishRecording(with keyCombo: KeyCombo) {
        isRecording = false
        recordedModifiers = []
        layer?.borderColor = NSColor.quaternaryLabelColor.cgColor
        onRecord?(Constants.normalizedGlobalHotKey(keyCombo))
    }

    private func updateDisplay() {
        if isRecording {
            let preview = recordedModifiers.description
            textField.stringValue = preview.isEmpty ? "按下快捷键" : preview
            textField.textColor = .controlAccentColor
            return
        }

        textField.stringValue = keyCombo.description.isEmpty ? placeholder : keyCombo.description
        textField.textColor = .labelColor
    }
}
