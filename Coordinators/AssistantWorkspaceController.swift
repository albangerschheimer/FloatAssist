//
//  AssistantWorkspaceController.swift
//  Float Assist
//
//  Copyright (c) 2026 Alban Gerschheimer. Licensed under the MIT License.
//

import AppKit
import Foundation
import Observation
import SwiftUI

/// Coordinates the native windows, shortcuts, and the single active browser.
///
/// This type deliberately owns presentation only. Website state and navigation
/// belong to `AssistantBrowserModel`, which keeps the UI predictable when an
/// assistant service changes or website data is reset.
@MainActor
@Observable
final class AssistantWorkspaceController {
    let browser = AssistantBrowserModel()

    var isPanelPinned = false {
        didSet {
            floatingPanel?.isPinned = isPanelPinned
        }
    }
    private(set) var isResettingWebsiteData = false
    private(set) var shortcutMessage: String?

    @ObservationIgnored private let shortcutStore = GlobalShortcutStore()
    @ObservationIgnored private weak var mainWindow: NSWindow?
    @ObservationIgnored private var floatingPanel: FloatingAssistantPanel?
    @ObservationIgnored private var didStart = false

    func start() {
        guard !didStart else { return }
        didStart = true
        installShortcuts()
    }

    func rememberMainWindow(_ window: NSWindow?) {
        guard let window, !(window is NSPanel) else { return }
        mainWindow = window
    }

    func selectService(_ service: AssistantService) {
        browser.switchService(to: service)
    }

    func showPanel(withClipboard: Bool = false) {
        let panel = makePanelIfNeeded()
        mainWindow?.orderOut(nil)
        panel.isPinned = isPanelPinned
        panel.presentNearPointer()

        if withClipboard,
           let text = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            browser.insertClipboardText(text)
        }
    }

    func hidePanel() {
        floatingPanel?.dismiss()
    }

    func togglePanel() {
        if floatingPanel?.isVisible == true {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func showMainWindow() {
        hidePanel()
        guard let mainWindow else { return }
        NSApp.setActivationPolicy(.regular)
        mainWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func resetWebsiteData() {
        guard !isResettingWebsiteData else { return }
        isResettingWebsiteData = true
        browser.clearWebsiteData { [weak self] in
            Task { @MainActor in
                self?.isResettingWebsiteData = false
            }
        }
    }

    func shortcut(for slot: AppShortcut) -> KeyboardShortcut? {
        shortcutStore.effectiveShortcut(for: slot, default: defaultShortcut(for: slot))
    }

    func updateShortcut(_ shortcut: KeyboardShortcut?, for slot: AppShortcut) {
        shortcutStore.set(shortcut, for: slot)
        installShortcuts()
    }

    func restoreDefaultShortcuts() {
        for slot in AppShortcut.allCases {
            shortcutStore.restoreDefault(for: slot)
        }
        installShortcuts()
    }

    private func makePanelIfNeeded() -> FloatingAssistantPanel {
        if let floatingPanel { return floatingPanel }

        let view = FloatingAssistantView(controller: self)
        let panel = FloatingAssistantPanel(rootView: view) { [weak self] in
            self?.shortcutMessage = nil
        }
        panel.isPinned = isPanelPinned
        floatingPanel = panel
        return panel
    }

    private func installShortcuts() {
        let center = GlobalShortcutCenter.shared
        center.unregisterAll()
        shortcutMessage = nil

        if let shortcut = shortcut(for: .togglePanel) {
            registerShortcut(shortcut, for: .togglePanel) { [weak self] in
                self?.togglePanel()
            }
        }

        if let shortcut = shortcut(for: .clipboardPrompt) {
            registerShortcut(shortcut, for: .clipboardPrompt) { [weak self] in
                self?.showPanel(withClipboard: true)
            }
        }
    }

    private func defaultShortcut(for slot: AppShortcut) -> KeyboardShortcut {
        switch slot {
        case .togglePanel:
            .optionSpace
        case .clipboardPrompt:
            .shiftOptionSpace
        }
    }

    private func registerShortcut(
        _ shortcut: KeyboardShortcut,
        for slot: AppShortcut,
        action: @escaping () -> Void
    ) {
        do {
            try GlobalShortcutCenter.shared.register(shortcut, for: slot) {
                Task { @MainActor in action() }
            }
        } catch {
            shortcutMessage = error.localizedDescription
        }
    }
}
