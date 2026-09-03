//
//  AssistantWebView.swift
//  Float Assist
//
//  Original SwiftUI host for AssistantBrowserModel's one primary WKWebView.
//  Copyright (c) 2026 Alban Gerschheimer. Licensed under the MIT License.
//

import AppKit
import SwiftUI
import WebKit

/// Embeds the browser model's primary web view in SwiftUI without creating a
/// second `WKWebView`.  A main window and a floating panel may both keep this
/// representable alive, but only the key window claims the shared view.
@MainActor
struct AssistantWebView: NSViewRepresentable {
    let model: AssistantBrowserModel

    func makeNSView(context: Context) -> AssistantWebViewContainer {
        AssistantWebViewContainer(model: model)
    }

    func updateNSView(_ container: AssistantWebViewContainer, context: Context) {
        container.update(model: model)
    }
}

@MainActor
final class AssistantWebViewContainer: NSView, AssistantWebViewHosting {
    private weak var model: AssistantBrowserModel?
    private weak var displayedWebView: WKWebView?
    private var keyWindowObserver: NSObjectProtocol?

    init(model: AssistantBrowserModel) {
        self.model = model
        super.init(frame: .zero)
        autoresizesSubviews = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let keyWindowObserver {
            NotificationCenter.default.removeObserver(keyWindowObserver)
        }
    }

    func update(model newModel: AssistantBrowserModel) {
        if model !== newModel {
            displayedWebView?.removeFromSuperview()
            model = newModel
        }

        if window?.isKeyWindow == true {
            activateIfEligible()
        } else if let model {
            // This is intentionally a no-op for inactive containers.  It lets
            // an already active container resize/reinstall after a SwiftUI
            // update without allowing a hidden window to steal the view.
            model.refresh(host: self)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let keyWindowObserver {
            NotificationCenter.default.removeObserver(keyWindowObserver)
            self.keyWindowObserver = nil
        }

        guard let window else {
            displayedWebView?.removeFromSuperview()
            return
        }

        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.activateIfEligible()
            }
        }

        if window.isKeyWindow {
            activateIfEligible()
        }
    }

    override func layout() {
        super.layout()
        if let displayedWebView, displayedWebView.superview === self {
            displayedWebView.frame = bounds
        }
    }

    func display(_ webView: WKWebView) {
        guard window != nil else { return }
        guard displayedWebView !== webView || webView.superview !== self else { return }

        displayedWebView?.removeFromSuperview()
        webView.removeFromSuperview()
        webView.frame = bounds
        webView.autoresizingMask = [.width, .height]
        displayedWebView = webView
        addSubview(webView)
    }

    private func activateIfEligible() {
        guard let model,
              let window,
              window.isKeyWindow,
              !window.isMiniaturized else {
            return
        }
        model.activate(host: self)
    }
}
