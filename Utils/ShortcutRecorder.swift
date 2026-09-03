//
//  ShortcutRecorder.swift
//  Float Assist
//
//  A lightweight SwiftUI/AppKit shortcut recorder for KeyboardShortcut values.
//

import AppKit
import Carbon
import SwiftUI

/// A simple SwiftUI recorder for a `KeyboardShortcut` binding.
///
/// Click the field and press a combination. Escape cancels recording; Delete
/// or Forward Delete without modifiers clears the current shortcut. By default
/// the recorder requires at least one modifier so it cannot accidentally
/// register an ordinary typing key as a system-wide shortcut.
struct ShortcutRecorder: View {
    @Binding private var shortcut: KeyboardShortcut?
    private let placeholder: String
    private let allowsModifierlessShortcuts: Bool

    init(
        shortcut: Binding<KeyboardShortcut?>,
        placeholder: String = "Record Shortcut",
        allowsModifierlessShortcuts: Bool = false
    ) {
        _shortcut = shortcut
        self.placeholder = placeholder
        self.allowsModifierlessShortcuts = allowsModifierlessShortcuts
    }

    var body: some View {
        HStack(spacing: 6) {
            ShortcutRecorderField(
                shortcut: $shortcut,
                placeholder: placeholder,
                allowsModifierlessShortcuts: allowsModifierlessShortcuts
            )
            .frame(minWidth: 160, idealWidth: 180, maxWidth: 220, minHeight: 28)

            if shortcut != nil {
                Button {
                    shortcut = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Clear shortcut")
                .accessibilityLabel("Clear shortcut")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ShortcutRecorderField: NSViewRepresentable {
    @Binding var shortcut: KeyboardShortcut?
    let placeholder: String
    let allowsModifierlessShortcuts: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> ShortcutRecorderControl {
        let control = ShortcutRecorderControl(frame: .zero)
        control.onShortcutRecorded = { [weak coordinator = context.coordinator] shortcut in
            coordinator?.shortcut = shortcut
        }
        control.configure(
            shortcut: shortcut,
            placeholder: placeholder,
            allowsModifierlessShortcuts: allowsModifierlessShortcuts
        )
        return control
    }

    func updateNSView(_ control: ShortcutRecorderControl, context: Context) {
        context.coordinator.parent = self
        control.configure(
            shortcut: shortcut,
            placeholder: placeholder,
            allowsModifierlessShortcuts: allowsModifierlessShortcuts
        )
    }

    final class Coordinator {
        var parent: ShortcutRecorderField

        init(_ parent: ShortcutRecorderField) {
            self.parent = parent
        }

        var shortcut: KeyboardShortcut? {
            get { parent.shortcut }
            set { parent.shortcut = newValue }
        }
    }
}

private final class ShortcutRecorderControl: NSButton {
    var onShortcutRecorded: ((KeyboardShortcut?) -> Void)?

    private var shortcut: KeyboardShortcut? {
        didSet {
            guard !isRecording else { return }
            updateTitle()
        }
    }
    private var placeholder = "Record Shortcut"
    private var allowsModifierlessShortcuts = false
    private var isRecording = false {
        didSet {
            updateTitle()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        controlSize = .small
        alignment = .center
        imagePosition = .noImage
        focusRingType = .default
        font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        target = self
        action = #selector(beginRecording)
        setAccessibilityLabel("Keyboard shortcut")
        setAccessibilityHelp(
            "Click to record a shortcut. Press Escape to cancel or Delete to clear it."
        )
        updateTitle()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        target = self
        action = #selector(beginRecording)
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    func configure(
        shortcut: KeyboardShortcut?,
        placeholder: String,
        allowsModifierlessShortcuts: Bool
    ) {
        self.shortcut = shortcut
        self.placeholder = placeholder
        self.allowsModifierlessShortcuts = allowsModifierlessShortcuts
        if !isRecording {
            updateTitle()
        }
    }

    @objc private func beginRecording() {
        isRecording = true
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        record(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else {
            return super.performKeyEquivalent(with: event)
        }
        record(event)
        return true
    }

    override func cancelOperation(_ sender: Any?) {
        guard isRecording else {
            super.cancelOperation(sender)
            return
        }
        cancelRecording()
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            cancelRecording()
        }
        return super.resignFirstResponder()
    }

    private func record(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            cancelRecording()
            return
        }

        let hasNoModifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .isEmpty
        if hasNoModifiers && (
            event.keyCode == UInt16(kVK_Delete) ||
                event.keyCode == UInt16(kVK_ForwardDelete)
        ) {
            finish(with: nil)
            return
        }

        guard let shortcut = KeyboardShortcut(event: event) else {
            NSSound.beep()
            return
        }

        guard allowsModifierlessShortcuts || !shortcut.modifiers.isEmpty else {
            title = "Add ⌘, ⌥, ⇧, or ⌃"
            NSSound.beep()
            return
        }

        finish(with: shortcut)
    }

    private func finish(with shortcut: KeyboardShortcut?) {
        isRecording = false
        self.shortcut = shortcut
        onShortcutRecorded?(shortcut)
        window?.makeFirstResponder(nil)
    }

    private func cancelRecording() {
        isRecording = false
    }

    private func updateTitle() {
        if isRecording {
            title = "Press Shortcut…"
        } else if let shortcut {
            title = shortcut.displayString
        } else {
            title = placeholder
        }
    }
}
