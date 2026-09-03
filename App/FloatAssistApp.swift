//
//  FloatAssistApp.swift
//  Float Assist
//
//  Copyright (c) 2026 Alban Gerschheimer. Licensed under the MIT License.
//

import AppKit
import SwiftUI

@main
struct FloatAssistApp: App {
    @NSApplicationDelegateAdaptor(FloatAssistAppDelegate.self) private var appDelegate
    @State private var controller = AssistantWorkspaceController()

    var body: some Scene {
        Window("Float Assist", id: "main") {
            WorkspaceView(controller: controller)
        }
        .defaultSize(width: 1040, height: 720)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Show Floating Panel") {
                    controller.showPanel()
                }
                .keyboardShortcut("f", modifiers: [.command, .option])

                Button("Ask with Clipboard") {
                    controller.showPanel(withClipboard: true)
                }
                .keyboardShortcut("f", modifiers: [.command, .option, .shift])
            }
        }

        Settings {
            PreferencesView(controller: controller)
                .frame(width: 640, height: 420)
        }

        MenuBarExtra {
            AppMenuContent(controller: controller)
        } label: {
            Image("MenuBarMark")
        }
        .menuBarExtraStyle(.menu)
    }
}

final class FloatAssistAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
