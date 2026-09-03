//
//  ProviderArchitectureTests.swift
//  Float Assist Tests
//
//  Copyright (c) 2026 Alban Gerschheimer. Licensed under the MIT License.
//

import Foundation
import XCTest
@testable import Float_Assist

final class AssistantServiceTests: XCTestCase {
    @MainActor
    func testServicesHaveStableNamesAndSeparateStores() {
        XCTAssertEqual(AssistantService.allCases, [.claude, .gemini, .chatGPT])
        XCTAssertEqual(AssistantService.claude.displayName, "Claude")
        XCTAssertEqual(AssistantService.gemini.displayName, "Gemini")
        XCTAssertEqual(AssistantService.chatGPT.displayName, "ChatGPT")

        let identifiers = Set(AssistantService.allCases.map {
            AssistantBrowserModel.dataStoreIdentifier(for: $0)
        })
        XCTAssertEqual(identifiers.count, AssistantService.allCases.count)
    }

    func testTrustedDomainsRequireCompleteLabels() {
        let configuration = AssistantService.claude.configuration

        XCTAssertTrue(configuration.acceptsTopLevelHost("claude.ai"))
        XCTAssertTrue(configuration.acceptsTopLevelHost("www.claude.ai"))
        XCTAssertTrue(configuration.acceptsTopLevelHost("console.anthropic.com"))
        XCTAssertFalse(configuration.acceptsTopLevelHost("claude.ai.example"))
        XCTAssertFalse(configuration.acceptsTopLevelHost("notclaude.ai"))
    }

    @MainActor
    func testBrowserRoutesTrustedAndExternalURLsSafely() {
        let browser = AssistantBrowserModel(service: .chatGPT)

        XCTAssertEqual(
            browser.navigationRoute(for: URL(string: "https://chatgpt.com/")!),
            .showInApp
        )
        XCTAssertEqual(
            browser.navigationRoute(for: URL(string: "https://help.openai.com/")!),
            .showInApp
        )
        XCTAssertEqual(
            browser.navigationRoute(for: URL(string: "https://example.com/")!),
            .openInDefaultApplication
        )
        XCTAssertEqual(
            browser.navigationRoute(for: URL(string: "file:///tmp/example")!),
            .block
        )
        XCTAssertEqual(
            browser.navigationRoute(for: URL(string: "javascript:alert(1)")!),
            .block
        )
    }
}

final class GlobalShortcutTests: XCTestCase {
    func testDefaultShortcutsHaveExpectedValues() {
        XCTAssertEqual(KeyboardShortcut.optionSpace.displayString, "⌥Space")
        XCTAssertEqual(KeyboardShortcut.shiftOptionSpace.displayString, "⌥⇧Space")
        XCTAssertNotEqual(KeyboardShortcut.optionSpace, .shiftOptionSpace)
    }

    func testStoreRoundTripsCustomShortcut() {
        let suiteName = "FloatAssistTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Unable to create an isolated UserDefaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = GlobalShortcutStore(defaults: defaults)
        let shortcut = KeyboardShortcut(
            keyCode: 8,
            modifiers: [.command, .shift]
        )

        store.set(shortcut, for: .togglePanel)

        XCTAssertEqual(store.shortcut(for: .togglePanel), shortcut)
        XCTAssertEqual(
            store.shortcut(for: .clipboardPrompt, default: .shiftOptionSpace),
            .shiftOptionSpace
        )
    }

    func testClearedAppShortcutStaysDisabledUntilDefaultsAreRestored() {
        let suiteName = "FloatAssistTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Unable to create an isolated UserDefaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = GlobalShortcutStore(defaults: defaults)
        store.set(nil, for: .togglePanel)

        XCTAssertNil(
            store.effectiveShortcut(for: .togglePanel, default: .optionSpace)
        )

        store.restoreDefault(for: .togglePanel)

        XCTAssertEqual(
            store.effectiveShortcut(for: .togglePanel, default: .optionSpace),
            .optionSpace
        )
    }
}
