//
//  GlobalShortcut.swift
//  Float Assist
//
//  A small, native replacement for a global-shortcut package. It uses Carbon's
//  RegisterEventHotKey API, which works in a sandboxed macOS app without the
//  Accessibility permission required by an event tap.
//

import AppKit
import Carbon
import Foundation

/// The modifier subset accepted by Carbon global hot keys.
///
/// The raw value deliberately stores Carbon's flags, so an encoded shortcut is
/// stable and can be passed to `RegisterEventHotKey` without a translation.
struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt32

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    static let command = ShortcutModifiers(rawValue: UInt32(cmdKey))
    static let option = ShortcutModifiers(rawValue: UInt32(optionKey))
    static let shift = ShortcutModifiers(rawValue: UInt32(shiftKey))
    static let control = ShortcutModifiers(rawValue: UInt32(controlKey))

    /// Converts AppKit's device-independent modifier flags into the Carbon
    /// representation used by global hot keys.
    init(_ flags: NSEvent.ModifierFlags) {
        var modifiers: ShortcutModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        self = modifiers
    }

    var eventFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.command) { flags.insert(.command) }
        if contains(.option) { flags.insert(.option) }
        if contains(.shift) { flags.insert(.shift) }
        if contains(.control) { flags.insert(.control) }
        return flags
    }

    var displayString: String {
        var pieces: [String] = []
        if contains(.control) { pieces.append("⌃") }
        if contains(.option) { pieces.append("⌥") }
        if contains(.shift) { pieces.append("⇧") }
        if contains(.command) { pieces.append("⌘") }
        return pieces.joined()
    }
}

/// A persistent global-hotkey value made of a virtual key code and modifiers.
///
/// It is `Codable`, so callers can save it with `GlobalShortcutStore` or their
/// own persistence mechanism. Virtual key codes are physical macOS key codes;
/// their behavior follows the current keyboard layout as macOS normally does.
struct GlobalShortcut: Codable, Hashable, Sendable {
    let keyCode: UInt16
    let modifiers: ShortcutModifiers

    init(keyCode: UInt16, modifiers: ShortcutModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Returns nil for a press of a modifier key alone, which cannot be a
    /// useful Carbon hot key.
    init?(event: NSEvent) {
        guard !Self.isModifierKey(event.keyCode) else { return nil }
        self.init(keyCode: event.keyCode, modifiers: ShortcutModifiers(event.modifierFlags))
    }

    static let optionSpace = GlobalShortcut(
        keyCode: UInt16(kVK_Space),
        modifiers: [.option]
    )

    static let shiftOptionSpace = GlobalShortcut(
        keyCode: UInt16(kVK_Space),
        modifiers: [.option, .shift]
    )

    var carbonModifiers: UInt32 {
        modifiers.rawValue
    }

    var displayString: String {
        modifiers.displayString + Self.keyLabel(for: keyCode)
    }

    private static func isModifierKey(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case UInt16(kVK_Command),
             UInt16(kVK_RightCommand),
             UInt16(kVK_Shift),
             UInt16(kVK_RightShift),
             UInt16(kVK_Option),
             UInt16(kVK_RightOption),
             UInt16(kVK_Control),
             UInt16(kVK_RightControl),
             UInt16(kVK_CapsLock),
             UInt16(kVK_Function):
            return true
        default:
            return false
        }
    }

    /// Carbon stores physical key codes. These common labels keep the recorder
    /// legible without asking the caller to retain the original NSEvent.
    private static func keyLabel(for keyCode: UInt16) -> String {
        keyLabels[keyCode] ?? "Key \(keyCode)"
    }

    private static let keyLabels: [UInt16: String] = [
        UInt16(kVK_ANSI_A): "A", UInt16(kVK_ANSI_B): "B",
        UInt16(kVK_ANSI_C): "C", UInt16(kVK_ANSI_D): "D",
        UInt16(kVK_ANSI_E): "E", UInt16(kVK_ANSI_F): "F",
        UInt16(kVK_ANSI_G): "G", UInt16(kVK_ANSI_H): "H",
        UInt16(kVK_ANSI_I): "I", UInt16(kVK_ANSI_J): "J",
        UInt16(kVK_ANSI_K): "K", UInt16(kVK_ANSI_L): "L",
        UInt16(kVK_ANSI_M): "M", UInt16(kVK_ANSI_N): "N",
        UInt16(kVK_ANSI_O): "O", UInt16(kVK_ANSI_P): "P",
        UInt16(kVK_ANSI_Q): "Q", UInt16(kVK_ANSI_R): "R",
        UInt16(kVK_ANSI_S): "S", UInt16(kVK_ANSI_T): "T",
        UInt16(kVK_ANSI_U): "U", UInt16(kVK_ANSI_V): "V",
        UInt16(kVK_ANSI_W): "W", UInt16(kVK_ANSI_X): "X",
        UInt16(kVK_ANSI_Y): "Y", UInt16(kVK_ANSI_Z): "Z",
        UInt16(kVK_ANSI_0): "0", UInt16(kVK_ANSI_1): "1",
        UInt16(kVK_ANSI_2): "2", UInt16(kVK_ANSI_3): "3",
        UInt16(kVK_ANSI_4): "4", UInt16(kVK_ANSI_5): "5",
        UInt16(kVK_ANSI_6): "6", UInt16(kVK_ANSI_7): "7",
        UInt16(kVK_ANSI_8): "8", UInt16(kVK_ANSI_9): "9",
        UInt16(kVK_Space): "Space", UInt16(kVK_Return): "↩",
        UInt16(kVK_Tab): "⇥", UInt16(kVK_Delete): "⌫",
        UInt16(kVK_ForwardDelete): "⌦", UInt16(kVK_Escape): "⎋",
        UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_Home): "↖", UInt16(kVK_End): "↘",
        UInt16(kVK_PageUp): "⇞", UInt16(kVK_PageDown): "⇟",
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2",
        UInt16(kVK_F3): "F3", UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9", UInt16(kVK_F10): "F10",
        UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
        UInt16(kVK_F13): "F13", UInt16(kVK_F14): "F14",
        UInt16(kVK_F15): "F15", UInt16(kVK_F16): "F16",
        UInt16(kVK_F17): "F17", UInt16(kVK_F18): "F18",
        UInt16(kVK_F19): "F19", UInt16(kVK_F20): "F20"
    ]
}

/// The application-level shortcut slots. Keeping these two names in one place
/// avoids stringly-typed registration and persistence keys at call sites.
enum AppShortcut: String, CaseIterable, Codable, Sendable {
    case togglePanel
    case clipboardPrompt

    var storageKey: String {
        "appShortcut.\(rawValue)"
    }

    var disabledStorageKey: String {
        "\(storageKey).disabled"
    }
}

/// Preferred name for app-facing code. `GlobalShortcut` remains available as
/// the underlying model name for callers that want to be explicit about scope.
typealias KeyboardShortcut = GlobalShortcut

/// JSON-backed convenience storage for `GlobalShortcut` values.
///
/// Keeping the encoded representation in one `Data` value avoids relying on
/// private UserDefaults conventions and makes the stored format explicit.
struct GlobalShortcutStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func shortcut(forKey key: String) -> GlobalShortcut? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(GlobalShortcut.self, from: data)
    }

    func shortcut(
        forKey key: String,
        default defaultShortcut: GlobalShortcut
    ) -> GlobalShortcut {
        shortcut(forKey: key) ?? defaultShortcut
    }

    func set(_ shortcut: GlobalShortcut?, forKey key: String) {
        guard let shortcut else {
            defaults.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        defaults.set(data, forKey: key)
    }

    func shortcut(for appShortcut: AppShortcut) -> KeyboardShortcut? {
        shortcut(forKey: appShortcut.storageKey)
    }

    func shortcut(
        for appShortcut: AppShortcut,
        default defaultShortcut: KeyboardShortcut
    ) -> KeyboardShortcut {
        shortcut(forKey: appShortcut.storageKey, default: defaultShortcut)
    }

    /// Returns the saved shortcut, its default, or nil when the user has
    /// explicitly disabled this shortcut in Settings.
    func effectiveShortcut(
        for appShortcut: AppShortcut,
        default defaultShortcut: KeyboardShortcut
    ) -> KeyboardShortcut? {
        guard !defaults.bool(forKey: appShortcut.disabledStorageKey) else {
            return nil
        }
        return shortcut(for: appShortcut, default: defaultShortcut)
    }

    /// Saves a user-selected shortcut. Passing nil means the user intentionally
    /// disabled this app shortcut, rather than asking to fall back to a default.
    func set(_ shortcut: KeyboardShortcut?, for appShortcut: AppShortcut) {
        guard let shortcut else {
            defaults.removeObject(forKey: appShortcut.storageKey)
            defaults.set(true, forKey: appShortcut.disabledStorageKey)
            return
        }

        defaults.removeObject(forKey: appShortcut.disabledStorageKey)
        set(shortcut, forKey: appShortcut.storageKey)
    }

    func restoreDefault(for appShortcut: AppShortcut) {
        defaults.removeObject(forKey: appShortcut.storageKey)
        defaults.removeObject(forKey: appShortcut.disabledStorageKey)
    }
}

enum GlobalShortcutRegistrationError: LocalizedError {
    case duplicateShortcut(GlobalShortcut)
    case eventHandlerInstallationFailed(OSStatus)
    case registrationFailed(shortcut: GlobalShortcut, status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .duplicateShortcut(let shortcut):
            return "\(shortcut.displayString) is already registered by this app."
        case .eventHandlerInstallationFailed(let status):
            return "Unable to install the global shortcut handler (OSStatus \(status))."
        case .registrationFailed(let shortcut, let status):
            return "Unable to register \(shortcut.displayString) (OSStatus \(status))."
        }
    }
}

/// Registers application-wide shortcuts through Carbon.
///
/// Use one shared instance, call `register` once for each action, and retain
/// the manager for as long as the shortcuts should remain active. The manager
/// accepts more than two identifiers, while the app can simply register its
/// two desired shortcuts independently.
final class GlobalShortcutManager {
    typealias Action = () -> Void

    static let shared = GlobalShortcutManager()

    private struct Registration {
        let identifier: String
        let id: UInt32
        let shortcut: GlobalShortcut
        let hotKey: EventHotKeyRef
        let action: Action
    }

    private static let signature: OSType = 0x4346_5348 // "CFSH"
    private static let hotKeyEventType = EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: UInt32(kEventHotKeyPressed)
    )

    private var eventHandler: EventHandlerRef?
    private var registrationsByIdentifier: [String: Registration] = [:]
    private var identifiersByID: [UInt32: String] = [:]
    private var nextID: UInt32 = 1

    deinit {
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    /// Registers or replaces one global shortcut. This method must be called
    /// from the main thread, as required by AppKit and Carbon event handling.
    func register(
        _ shortcut: GlobalShortcut,
        for identifier: String,
        action: @escaping Action
    ) throws {
        precondition(Thread.isMainThread, "Register global shortcuts on the main thread.")

        if registrationsByIdentifier.values.contains(where: {
            $0.identifier != identifier && $0.shortcut == shortcut
        }) {
            throw GlobalShortcutRegistrationError.duplicateShortcut(shortcut)
        }

        if let existing = registrationsByIdentifier[identifier], existing.shortcut == shortcut {
            registrationsByIdentifier[identifier] = Registration(
                identifier: existing.identifier,
                id: existing.id,
                shortcut: existing.shortcut,
                hotKey: existing.hotKey,
                action: action
            )
            return
        }

        try installEventHandlerIfNeeded()

        let id = makeIdentifier()
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        var hotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )

        guard status == noErr, let hotKey else {
            throw GlobalShortcutRegistrationError.registrationFailed(
                shortcut: shortcut,
                status: status
            )
        }

        let registration = Registration(
            identifier: identifier,
            id: id,
            shortcut: shortcut,
            hotKey: hotKey,
            action: action
        )
        if let existing = registrationsByIdentifier[identifier] {
            identifiersByID.removeValue(forKey: existing.id)
            UnregisterEventHotKey(existing.hotKey)
        }
        registrationsByIdentifier[identifier] = registration
        identifiersByID[id] = identifier
    }

    func register(
        _ shortcut: KeyboardShortcut,
        for appShortcut: AppShortcut,
        action: @escaping Action
    ) throws {
        try register(shortcut, for: appShortcut.rawValue, action: action)
    }

    func unregister(_ identifier: String) {
        guard let registration = registrationsByIdentifier.removeValue(forKey: identifier) else {
            return
        }
        identifiersByID.removeValue(forKey: registration.id)
        UnregisterEventHotKey(registration.hotKey)
    }

    func unregister(_ appShortcut: AppShortcut) {
        unregister(appShortcut.rawValue)
    }

    func unregisterAll() {
        let identifiers = Array(registrationsByIdentifier.keys)
        for identifier in identifiers {
            unregister(identifier)
        }
    }

    func shortcut(for identifier: String) -> GlobalShortcut? {
        registrationsByIdentifier[identifier]?.shortcut
    }

    func shortcut(for appShortcut: AppShortcut) -> KeyboardShortcut? {
        shortcut(for: appShortcut.rawValue)
    }

    private func installEventHandlerIfNeeded() throws {
        guard eventHandler == nil else { return }

        var eventType = Self.hotKeyEventType
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.hotKeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard status == noErr else {
            eventHandler = nil
            throw GlobalShortcutRegistrationError.eventHandlerInstallationFailed(status)
        }
    }

    private func makeIdentifier() -> UInt32 {
        defer {
            nextID &+= 1
            if nextID == 0 { nextID = 1 }
        }
        return nextID
    }

    private func receiveHotKeyEvent(_ event: EventRef) {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr,
              hotKeyID.signature == Self.signature,
              let identifier = identifiersByID[hotKeyID.id],
              let action = registrationsByIdentifier[identifier]?.action else {
            return
        }

        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async(execute: action)
        }
    }

    private static let hotKeyEventHandler: EventHandlerUPP = {
        _, event, userData in
        guard let event, let userData else { return noErr }
        let manager = Unmanaged<GlobalShortcutManager>
            .fromOpaque(userData)
            .takeUnretainedValue()
        manager.receiveHotKeyEvent(event)
        return noErr
    }
}

/// Preferred app-facing name. A shared center is convenient for the two
/// `AppShortcut` cases while the manager remains available for custom slots.
typealias GlobalShortcutCenter = GlobalShortcutManager
