//
//  AssistantBrowser.swift
//  Float Assist
//
//  Original browser session layer built with Apple frameworks only.
//

import AppKit
import Foundation
import Observation
import WebKit

/// The web assistants available to the app.  Each service has a deliberately
/// separate website-data-store identifier, so a cookie from one service cannot
/// become a session for another service.
enum AssistantService: String, CaseIterable, Identifiable, Codable, Sendable {
    case claude
    case gemini
    case chatGPT = "chatgpt"

    static let defaultsKey = "assistantBrowser.selectedService"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .gemini: return "Gemini"
        case .chatGPT: return "ChatGPT"
        }
    }

    var configuration: AssistantServiceConfiguration {
        switch self {
        case .claude:
            return AssistantServiceConfiguration(
                homeURL: URL(string: "https://claude.ai/new")!,
                trustedDomains: ["claude.ai", "anthropic.com"],
                persistentStoreIdentifier: UUID(
                    uuidString: "6E983E87-8EFA-47CB-A659-9C7E221E7001"
                )!
            )
        case .gemini:
            return AssistantServiceConfiguration(
                homeURL: URL(string: "https://gemini.google.com/app")!,
                trustedDomains: ["gemini.google.com", "accounts.google.com"],
                persistentStoreIdentifier: UUID(
                    uuidString: "3461E10D-83B3-4207-A0E1-786F8F96D002"
                )!
            )
        case .chatGPT:
            return AssistantServiceConfiguration(
                homeURL: URL(string: "https://chatgpt.com/")!,
                trustedDomains: ["chatgpt.com", "openai.com"],
                persistentStoreIdentifier: UUID(
                    uuidString: "E809A5AD-52BB-4D92-AE37-17B129790003"
                )!
            )
        }
    }
}

/// Immutable per-service browser settings.  Domains are matched as complete
/// host labels: `claude.ai.example` does not match `claude.ai`.
struct AssistantServiceConfiguration: Sendable {
    let homeURL: URL
    let trustedDomains: Set<String>
    let persistentStoreIdentifier: UUID

    init(
        homeURL: URL,
        trustedDomains: Set<String>,
        persistentStoreIdentifier: UUID
    ) {
        self.homeURL = homeURL
        self.trustedDomains = Set(trustedDomains.map(Self.normalizedDomain))
        self.persistentStoreIdentifier = persistentStoreIdentifier
    }

    func acceptsTopLevelHost(_ host: String?) -> Bool {
        guard let host else { return false }
        let candidate = Self.normalizedDomain(host)
        return trustedDomains.contains { domain in
            candidate == domain || candidate.hasSuffix(".\(domain)")
        }
    }

    private static func normalizedDomain(_ value: String) -> String {
        value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}

/// The possible outcomes for a top-level navigation.  Kept internal so the
/// policy is easy to exercise in tests without exposing implementation detail
/// in the app UI.
enum AssistantNavigationRoute: Equatable {
    case showInApp
    case openInDefaultApplication
    case block
}

/// A main-actor-only browser session.  It owns exactly one primary `WKWebView`
/// at a time; changing service discards the old page process and creates a new
/// view connected to the new service's persistent website data store.
@MainActor
@Observable
final class AssistantBrowserModel {
    private static var persistentStores: [AssistantService: WKWebsiteDataStore] = [:]

    private(set) var webView: WKWebView
    private(set) var provider: AssistantService
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var isLoading = false
    private(set) var currentURL: URL?
    private(set) var lastNavigationError: String?

    @ObservationIgnored private let policyDelegate: AssistantWebPolicyDelegate
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private weak var activeHost: (any AssistantWebViewHosting)?

    init(service requestedService: AssistantService? = nil) {
        let storedService = UserDefaults.standard
            .string(forKey: AssistantService.defaultsKey)
            .flatMap(AssistantService.init(rawValue:))
        let selectedService = requestedService ?? storedService ?? .claude
        let delegate = AssistantWebPolicyDelegate()

        provider = selectedService
        policyDelegate = delegate
        webView = Self.makeWebView(for: selectedService)

        delegate.model = self
        configure(webView)
        observe(webView)
        UserDefaults.standard.set(selectedService.rawValue, forKey: AssistantService.defaultsKey)
        loadHome()
    }

    /// Stable store identity is public to the module for simple regression
    /// tests that assert services never share authentication state.
    static func dataStoreIdentifier(for service: AssistantService) -> UUID {
        service.configuration.persistentStoreIdentifier
    }

    // MARK: - Session and navigation

    func switchService(to service: AssistantService) {
        guard service != provider else {
            loadHome()
            return
        }

        policyDelegate.closeAllPopups()
        provider = service
        UserDefaults.standard.set(service.rawValue, forKey: AssistantService.defaultsKey)
        replaceWebView(for: service)
        loadHome()
    }

    func loadHome() {
        currentURL = provider.configuration.homeURL
        canGoBack = false
        canGoForward = false
        isLoading = true
        lastNavigationError = nil
        webView.load(URLRequest(url: provider.configuration.homeURL))
    }

    func goBack() {
        guard webView.canGoBack else { return }
        lastNavigationError = nil
        webView.goBack()
    }

    func goForward() {
        guard webView.canGoForward else { return }
        lastNavigationError = nil
        webView.goForward()
    }

    func reload() {
        guard webView.url != nil else {
            loadHome()
            return
        }
        isLoading = true
        lastNavigationError = nil
        webView.reload()
    }

    /// Inserts caller-provided text into the focused editable element without
    /// reading or changing the system pasteboard.  The text is JSON encoded
    /// before entering JavaScript, so it is data rather than executable code.
    func insertClipboardText(_ text: String) {
        guard !text.isEmpty else { return }
        let encodedText = Self.javaScriptString(text)
        let script = """
        (() => {
            const text = \(encodedText);
            const active = document.activeElement;
            const acceptsTextInput = (element) => element instanceof HTMLInputElement && [
                '', 'text', 'search', 'url', 'email', 'tel'
            ].includes((element.type || 'text').toLowerCase());
            const isEditableTarget = (element) =>
                element && (
                    element.isContentEditable ||
                    element instanceof HTMLTextAreaElement ||
                    acceptsTextInput(element)
                );
            const fallback = Array.from(document.querySelectorAll(
                'textarea, input, [contenteditable], [role="textbox"]'
            )).find(isEditableTarget);
            const target = isEditableTarget(active) ? active : fallback;

            if (!target) return false;
            target.focus();

            if (target instanceof HTMLTextAreaElement || acceptsTextInput(target)) {
                const start = target.selectionStart ?? target.value.length;
                const end = target.selectionEnd ?? start;
                target.setRangeText(text, start, end, 'end');
                target.dispatchEvent(new InputEvent('input', {
                    bubbles: true,
                    inputType: 'insertText',
                    data: text
                }));
                return true;
            }

            if (!target.isContentEditable) return false;
            const selection = window.getSelection();
            if (selection && selection.rangeCount > 0) {
                const range = selection.getRangeAt(0);
                range.deleteContents();
                const node = document.createTextNode(text);
                range.insertNode(node);
                range.setStartAfter(node);
                range.collapse(true);
                selection.removeAllRanges();
                selection.addRange(range);
            } else {
                target.append(document.createTextNode(text));
            }
            target.dispatchEvent(new InputEvent('input', {
                bubbles: true,
                inputType: 'insertText',
                data: text
            }));
            return true;
        })()
        """

        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    /// Clears cookies, caches, local storage, and other WebKit website data
    /// from every service store, then starts the active service from its home
    /// page.  Completion is always delivered on the main queue.
    func clearWebsiteData(completion: @escaping () -> Void = {}) {
        policyDelegate.closeAllPopups()
        webView.stopLoading()

        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let stores = AssistantService.allCases.map(Self.websiteDataStore(for:))
        let deletionGroup = DispatchGroup()

        for store in stores {
            deletionGroup.enter()
            store.removeData(ofTypes: dataTypes, modifiedSince: .distantPast) {
                deletionGroup.leave()
            }
        }

        deletionGroup.notify(queue: .main) { [weak self] in
            guard let self else {
                completion()
                return
            }
            self.replaceWebView(for: self.provider)
            self.loadHome()
            completion()
        }
    }

    // MARK: - Navigation policy

    /// Makes a conservative decision for a main-frame URL.  Known assistant
    /// and sign-in domains stay inside the web view.  Ordinary web links go to
    /// the user's default browser, while executable and local-file schemes are
    /// refused instead of being handed to the operating system.
    func navigationRoute(for url: URL) -> AssistantNavigationRoute {
        guard let scheme = url.scheme?.lowercased() else { return .block }

        switch scheme {
        case "https", "http":
            return provider.configuration.acceptsTopLevelHost(url.host)
                ? .showInApp
                : .openInDefaultApplication
        case "about":
            return url.absoluteString == "about:blank" ? .showInApp : .block
        case "blob":
            return .showInApp
        case "mailto", "tel", "sms", "facetime", "facetime-audio":
            return .openInDefaultApplication
        default:
            // This includes javascript:, data:, file:, and unknown custom
            // schemes.  None should be launched merely because page content
            // requested it.
            return .block
        }
    }

    // MARK: - SwiftUI host handoff

    /// Called by `AssistantWebView` when one of its AppKit containers becomes
    /// the active window.  Only that container gets the single primary web
    /// view, which prevents a hidden window from retaining an obsolete page.
    func activate(host: any AssistantWebViewHosting) {
        activeHost = host
        host.display(webView)
    }

    func refresh(host: any AssistantWebViewHosting) {
        guard activeHost === host else { return }
        host.display(webView)
    }

    // MARK: - WebKit lifecycle

    private func replaceWebView(for service: AssistantService) {
        let oldWebView = webView
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        oldWebView.stopLoading()
        oldWebView.navigationDelegate = nil
        oldWebView.uiDelegate = nil
        oldWebView.removeFromSuperview()

        let replacement = Self.makeWebView(for: service)
        webView = replacement
        canGoBack = false
        canGoForward = false
        currentURL = nil
        isLoading = false
        lastNavigationError = nil

        configure(replacement)
        observe(replacement)
        activeHost?.display(replacement)
    }

    private func configure(_ view: WKWebView) {
        view.navigationDelegate = policyDelegate
        view.uiDelegate = policyDelegate
        view.allowsBackForwardNavigationGestures = true
        view.allowsMagnification = true
    }

    private func observe(_ view: WKWebView) {
        observations = [
            view.observe(\.canGoBack, options: [.initial, .new]) { [weak self] observed, _ in
                DispatchQueue.main.async {
                    guard let self, self.webView === observed else { return }
                    self.canGoBack = observed.canGoBack
                }
            },
            view.observe(\.canGoForward, options: [.initial, .new]) { [weak self] observed, _ in
                DispatchQueue.main.async {
                    guard let self, self.webView === observed else { return }
                    self.canGoForward = observed.canGoForward
                }
            },
            view.observe(\.isLoading, options: [.initial, .new]) { [weak self] observed, _ in
                DispatchQueue.main.async {
                    guard let self, self.webView === observed else { return }
                    self.isLoading = observed.isLoading
                }
            },
            view.observe(\.url, options: [.initial, .new]) { [weak self] observed, _ in
                DispatchQueue.main.async {
                    guard let self, self.webView === observed else { return }
                    self.currentURL = observed.url
                }
            }
        ]
    }

    private static func makeWebView(for service: AssistantService) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteDataStore(for: service)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        return WKWebView(frame: .zero, configuration: configuration)
    }

    private static func websiteDataStore(for service: AssistantService) -> WKWebsiteDataStore {
        if let store = persistentStores[service] {
            return store
        }

        let store = WKWebsiteDataStore(forIdentifier: dataStoreIdentifier(for: service))
        persistentStores[service] = store
        return store
    }

    private static func javaScriptString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let array = String(data: data, encoding: .utf8),
              array.count >= 2 else {
            return "\"\""
        }
        return String(array.dropFirst().dropLast())
    }

    fileprivate func recordNavigationFailure(_ error: Error, from view: WKWebView) {
        guard view === webView else { return }
        isLoading = false
        lastNavigationError = error.localizedDescription
    }

    fileprivate func recordFinishedNavigation(from view: WKWebView) {
        guard view === webView else { return }
        lastNavigationError = nil
    }

    fileprivate func recordTerminatedContentProcess(from view: WKWebView) {
        guard view === webView else { return }
        isLoading = false
        lastNavigationError = "The web content process stopped unexpectedly."
    }
}

/// The UI layer supplies an AppKit host for the one primary web view.  A
/// class-bound protocol lets the model keep only a weak reference to it.
@MainActor
protocol AssistantWebViewHosting: AnyObject {
    func display(_ webView: WKWebView)
}

@MainActor
private final class AssistantWebPolicyDelegate: NSObject, WKNavigationDelegate, WKUIDelegate,
    NSWindowDelegate {
    private final class Popup {
        let window: NSWindow
        let webView: WKWebView

        init(window: NSWindow, webView: WKWebView) {
            self.window = window
            self.webView = webView
        }
    }

    weak var model: AssistantBrowserModel?
    private var popups: [ObjectIdentifier: Popup] = [:]

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let model, manages(webView, for: model) else {
            decisionHandler(.cancel)
            return
        }

        // A nil target frame is a window.open / target=_blank request.  The
        // UI-delegate callback below routes it exactly once.
        if navigationAction.targetFrame == nil, webView === model.webView {
            decisionHandler(.allow)
            return
        }

        guard navigationAction.targetFrame?.isMainFrame != false else {
            decisionHandler(.allow)
            return
        }
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        switch model.navigationRoute(for: url) {
        case .showInApp:
            decisionHandler(.allow)
        case .openInDefaultApplication:
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        case .block:
            decisionHandler(.cancel)
        }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let model,
              manages(webView, for: model),
              let url = navigationAction.request.url else {
            return nil
        }

        switch model.navigationRoute(for: url) {
        case .showInApp:
            return presentTrustedPopup(
                configuration: configuration,
                parentWebView: webView,
                serviceName: model.provider.displayName
            )
        case .openInDefaultApplication:
            NSWorkspace.shared.open(url)
        case .block:
            break
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        model?.recordFinishedNavigation(from: webView)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        model?.recordNavigationFailure(error, from: webView)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        model?.recordNavigationFailure(error, from: webView)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        model?.recordTerminatedContentProcess(from: webView)
    }

    func webViewDidClose(_ webView: WKWebView) {
        closePopup(webView)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let entry = popups.first(where: { $0.value.window === window }) else {
            return
        }
        discardPopup(key: entry.key)
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        // Deliberately never auto-grant microphone or camera access.  A future
        // product-specific permission UI can make an explicit user choice.
        decisionHandler(.deny)
    }

    func closeAllPopups() {
        let activePopups = Array(popups)
        popups.removeAll()

        for (_, popup) in activePopups {
            popup.webView.stopLoading()
            popup.webView.navigationDelegate = nil
            popup.webView.uiDelegate = nil
            popup.window.parent?.removeChildWindow(popup.window)
            popup.window.close()
        }
    }

    private func presentTrustedPopup(
        configuration: WKWebViewConfiguration,
        parentWebView: WKWebView,
        serviceName: String
    ) -> WKWebView {
        let popupWebView = WKWebView(frame: .zero, configuration: configuration)
        popupWebView.navigationDelegate = self
        popupWebView.uiDelegate = self
        popupWebView.allowsBackForwardNavigationGestures = true
        popupWebView.allowsMagnification = true

        let popupWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        popupWindow.title = "Sign in to \(serviceName)"
        popupWindow.contentMinSize = NSSize(width: 420, height: 520)
        popupWindow.contentView = popupWebView
        popupWindow.delegate = self

        let key = ObjectIdentifier(popupWebView)
        popups[key] = Popup(window: popupWindow, webView: popupWebView)

        if let parentWindow = parentWebView.window {
            parentWindow.addChildWindow(popupWindow, ordered: .above)
            let parentFrame = parentWindow.frame
            let popupFrame = popupWindow.frame
            popupWindow.setFrameOrigin(
                NSPoint(
                    x: parentFrame.midX - popupFrame.width / 2,
                    y: parentFrame.midY - popupFrame.height / 2
                )
            )
        } else {
            popupWindow.center()
        }

        NSApp.activate(ignoringOtherApps: true)
        popupWindow.makeKeyAndOrderFront(nil)
        return popupWebView
    }

    private func manages(_ webView: WKWebView, for model: AssistantBrowserModel) -> Bool {
        webView === model.webView || popups[ObjectIdentifier(webView)] != nil
    }

    private func closePopup(_ webView: WKWebView) {
        let key = ObjectIdentifier(webView)
        guard let popup = popups[key] else { return }
        popup.window.close()
        discardPopup(key: key)
    }

    private func discardPopup(key: ObjectIdentifier) {
        guard let popup = popups.removeValue(forKey: key) else { return }
        popup.window.parent?.removeChildWindow(popup.window)
        popup.webView.stopLoading()
        popup.webView.navigationDelegate = nil
        popup.webView.uiDelegate = nil
    }
}
