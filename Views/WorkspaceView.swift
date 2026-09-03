//
//  WorkspaceView.swift
//  Float Assist
//
//  Copyright (c) 2026 Alban Gerschheimer. Licensed under the MIT License.
//

import AppKit
import SwiftUI

struct WorkspaceView: View {
    @Bindable var controller: AssistantWorkspaceController

    var body: some View {
        VStack(spacing: 0) {
            AssistantHeader(controller: controller, compact: false)
            AssistantWebView(model: controller.browser)

            HStack {
                if let message = controller.shortcutMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else {
                    Label("Website sessions stay in this Mac's WebKit storage.", systemImage: "lock")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if controller.browser.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .font(.caption)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .background(WindowReference { controller.rememberMainWindow($0) })
        .onAppear { controller.start() }
        .frame(minWidth: 560, minHeight: 420)
    }
}

struct AssistantHeader: View {
    @Bindable var controller: AssistantWorkspaceController
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Picker("Assistant", selection: Binding(
                get: { controller.browser.provider },
                set: { controller.selectService($0) }
            )) {
                ForEach(AssistantService.allCases) { service in
                    Text(service.displayName).tag(service)
                }
            }
            .labelsHidden()
            .frame(maxWidth: compact ? 150 : 180)

            Divider().frame(height: 18)

            Button {
                controller.browser.goBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!controller.browser.canGoBack)
            .accessibilityLabel("Back")

            Button {
                controller.browser.goForward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!controller.browser.canGoForward)
            .accessibilityLabel("Forward")

            Button {
                controller.browser.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("Reload")

            Button {
                controller.browser.loadHome()
            } label: {
                Image(systemName: "house")
            }
            .accessibilityLabel("Home")

            Spacer(minLength: 0)

            if !compact {
                Button {
                    controller.showPanel()
                } label: {
                    Label("Float", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, compact ? 12 : 16)
        .padding(.vertical, compact ? 8 : 10)
        .background(.bar)
    }
}

struct PreferencesView: View {
    @Bindable var controller: AssistantWorkspaceController
    @State private var panelShortcut: KeyboardShortcut?
    @State private var clipboardShortcut: KeyboardShortcut?
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section("Assistant") {
                Picker("Default assistant", selection: Binding(
                    get: { controller.browser.provider },
                    set: { controller.selectService($0) }
                )) {
                    ForEach(AssistantService.allCases) { service in
                        Text(service.displayName).tag(service)
                    }
                }

                Text("Each service uses its own WebKit website-data store.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Global shortcuts") {
                HStack {
                    Text("Show or hide floating panel")
                    Spacer()
                    ShortcutRecorder(shortcut: $panelShortcut)
                }

                HStack {
                    Text("Ask with clipboard text")
                    Spacer()
                    ShortcutRecorder(shortcut: $clipboardShortcut)
                }

                Button("Restore Default Shortcuts") {
                    controller.restoreDefaultShortcuts()
                    loadShortcuts()
                }

                Text("A shortcut must include at least one modifier. Clear a recorder to disable that shortcut. If macOS reserves it, Float Assist keeps the rest of the app available and shows the error in the window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Text("Resetting website data removes cookies, cached website data, and sign-in sessions for all configured assistants.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Reset Website Data", role: .destructive) {
                    confirmReset = true
                }
                .disabled(controller.isResettingWebsiteData)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear(perform: loadShortcuts)
        .onChange(of: panelShortcut) { _, value in
            controller.updateShortcut(value, for: .togglePanel)
        }
        .onChange(of: clipboardShortcut) { _, value in
            controller.updateShortcut(value, for: .clipboardPrompt)
        }
        .alert("Reset Website Data?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                controller.resetWebsiteData()
            }
        } message: {
            Text("You will need to sign in to each assistant again.")
        }
    }

    private func loadShortcuts() {
        panelShortcut = controller.shortcut(for: .togglePanel) ?? .optionSpace
        clipboardShortcut = controller.shortcut(for: .clipboardPrompt) ?? .shiftOptionSpace
    }
}

struct AppMenuContent: View {
    let controller: AssistantWorkspaceController

    var body: some View {
        Button("Show Float Assist") {
            controller.showMainWindow()
        }
        Button("Toggle Floating Panel") {
            controller.togglePanel()
        }
        Divider()
        ForEach(AssistantService.allCases) { service in
            Button(service.displayName) {
                controller.selectService(service)
                controller.showMainWindow()
            }
        }
        Divider()
        Button("Quit Float Assist") {
            NSApp.terminate(nil)
        }
    }
}

private struct WindowReference: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowReferenceView {
        WindowReferenceView(onWindow: onWindow)
    }

    func updateNSView(_ nsView: WindowReferenceView, context: Context) {
        nsView.onWindow = onWindow
        onWindow(nsView.window)
    }
}

private final class WindowReferenceView: NSView {
    var onWindow: (NSWindow?) -> Void

    init(onWindow: @escaping (NSWindow?) -> Void) {
        self.onWindow = onWindow
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindow(window)
    }
}
