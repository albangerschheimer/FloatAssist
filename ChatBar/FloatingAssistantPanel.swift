//
//  FloatingAssistantPanel.swift
//  Float Assist
//
//  Copyright (c) 2026 Alban Gerschheimer. Licensed under the MIT License.
//

import AppKit
import SwiftUI

@MainActor
final class FloatingAssistantPanel: NSPanel, NSWindowDelegate {
    var isPinned = false

    private let onDismiss: () -> Void

    init<Content: View>(rootView: Content, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        contentView = NSHostingView(rootView: rootView)
        title = "Float Assist"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        minSize = NSSize(width: 480, height: 340)
        delegate = self
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func presentNearPointer() {
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main {
            let visible = screen.visibleFrame
            let origin = NSPoint(
                x: visible.midX - frame.width / 2,
                y: max(visible.minY + 24, visible.midY - frame.height / 2)
            )
            setFrameOrigin(origin)
        }

        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        orderOut(nil)
        onDismiss()
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !isPinned, isVisible else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isPinned, !self.isKeyWindow else { return }

            // An authentication window is presented as a child of this panel.
            // Keep the panel alive while that child owns focus, otherwise a
            // normal sign-in redirect would make the assistant disappear.
            if NSApp.keyWindow?.parent === self {
                return
            }

            self.dismiss()
        }
    }
}

struct FloatingAssistantView: View {
    @Bindable var controller: AssistantWorkspaceController

    var body: some View {
        VStack(spacing: 0) {
            AssistantHeader(controller: controller, compact: true)

            AssistantWebView(model: controller.browser)

            HStack(spacing: 12) {
                Toggle("Keep open", isOn: $controller.isPanelPinned)
                    .toggleStyle(.switch)

                Spacer()

                if let message = controller.shortcutMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }

                Button("Open Window") {
                    controller.showMainWindow()
                }
                .buttonStyle(.bordered)

                Button {
                    controller.hidePanel()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Close floating assistant")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.bar)
        }
        .frame(minWidth: 480, minHeight: 340)
    }
}
