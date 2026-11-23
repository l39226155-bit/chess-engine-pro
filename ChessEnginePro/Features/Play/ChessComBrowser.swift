//
//  ChessComBrowser.swift
//  CHESS ENGINE PRO
//
//  WKWebView integration for Chess.com.
//
//  Security notes:
//  * The login form is Chess.com's own page; the app never reads or stores
//    credentials.
//  * Cookies live in WKWebsiteDataStore.default(), exactly like Safari, and can
//    be wiped from the Play screen at any time.
//  * No private Chess.com API is used and no protection mechanism is bypassed.
//

import Foundation
import Combine
import SwiftUI
import WebKit
import UIKit

@MainActor
final class ChessComBrowser: NSObject, ObservableObject {

    // MARK: - Published state

    @Published private(set) var progress: Double = 0
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var currentURL: URL?
    @Published private(set) var pageTitle: String = "Chess.com"
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasSession: Bool = false
    @Published private(set) var lastPortalMessage: String?
    /// What the open page is used for. Drives the live analysis gate.
    @Published private(set) var pageMode: ChessComPageMode = .home

    /// Engine suggestions are only allowed in analysis, training and games
    /// against the computer.
    var allowsLiveSuggestions: Bool { pageMode.allowsEngineSuggestions }

    // Live position detection
    @Published private(set) var detectionCount: Int = 0
    /// Counts page loads requested by the user. Used by the tests as evidence
    /// that switching tabs never reloads the page.
    @Published private(set) var navigationCount: Int = 0

    /// Called for every new snapshot the page posts (already de-duplicated in
    /// JavaScript). The payload is not yet verified - that happens in the
    /// detector and the synchroniser before anything reaches the engine.
    var onPositionPayload: (@MainActor (ChessComPositionPayload) -> Void)?

    let webView: WKWebView

    private var observations: [NSKeyValueObservation] = []
    private var hasStarted = false

    static let homeURL = URL(string: "https://www.chess.com/")!
    static let loginURL = URL(string: "https://www.chess.com/login_and_go?returnUrl=https%3A%2F%2Fwww.chess.com%2Fhome")!
    static let playURL = URL(string: "https://www.chess.com/play/online")!
    static let puzzlesURL = URL(string: "https://www.chess.com/puzzles")!
    static let profileURL = URL(string: "https://www.chess.com/member")!
    static let settingsURL = URL(string: "https://www.chess.com/settings")!

    override init() {
        let configuration = WKWebViewConfiguration()
        // Persistent data store: the Chess.com session survives app restarts.
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // Read-only probe for the rendered board, injected before the page runs.
        configuration.userContentController.addUserScript(
            WKUserScript(source: ChessComPositionScript.source,
                         injectionTime: .atDocumentEnd,
                         forMainFrameOnly: true)
        )

        webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()

        configuration.userContentController.add(self, name: ChessComPositionScript.handlerName)

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.keyboardDismissMode = .interactive

        observe()
    }

    /// Loads Chess.com exactly once. The browser itself is owned by
    /// AppEnvironment and therefore outlives every SwiftUI view.
    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        if webView.url == nil {
            load(Self.homeURL)
        }
    }

    /// Called whenever the tab becomes visible. The web view lives in the view
    /// hierarchy from launch and is never rebuilt, so showing it must not load
    /// anything: it only needs the layout pass WebKit skips while hidden, a
    /// repaint, and a fresh position from the probe.
    func prepareForDisplay() {
        if !hasStarted { startIfNeeded() }
        webView.setNeedsLayout()
        webView.layoutIfNeeded()
        webView.setNeedsDisplay()
        requestLiveSnapshot()
    }

    /// Asks the injected probe for a snapshot without navigating or reloading.
    /// Used after the app returns from the background, where the page may have
    /// moved on while the app was suspended.
    func requestLiveSnapshot(force: Bool = false) {
        guard hasStarted, webView.url != nil else { return }
        pageMode = ChessComPageMode.classify(webView.url)
        let call = force
            ? "window.__cepLive && window.__cepLive.force ? (window.__cepLive.force(), true) : false"
            : "window.__cepLive && window.__cepLive.snapshot ? (window.__cepLive.snapshot(), true) : false"
        webView.evaluateJavaScript(call) { _, _ in }
    }

    // MARK: - KVO

    private func observe() {
        observations.append(webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
            let value = view.estimatedProgress
            Task { @MainActor in self?.progress = value }
        })
        observations.append(webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
            let value = view.isLoading
            Task { @MainActor in self?.isLoading = value }
        })
        observations.append(webView.observe(\.url, options: [.new]) { [weak self] view, _ in
            let url = view.url
            let mode = ChessComPageMode.classify(url)
            Task { @MainActor in
                self?.currentURL = url
                if self?.pageMode != mode { self?.pageMode = mode }
            }
        })
        observations.append(webView.observe(\.title, options: [.new]) { [weak self] view, _ in
            let title = view.title
            Task { @MainActor in
                if let title = title, !title.isEmpty { self?.pageTitle = title }
            }
        })
    }

    // MARK: - Navigation

    func load(_ url: URL) {
        errorMessage = nil
        navigationCount += 1
        webView.load(URLRequest(url: url))
    }

    func openLogin() {
        load(Self.loginURL)
    }

    func goHome() {
        load(Self.homeURL)
    }

    func reload() {
        errorMessage = nil
        if webView.url == nil {
            load(Self.homeURL)
        } else {
            webView.reload()
        }
    }

    /// Removes all Chess.com cookies and local storage for this app.
    func signOutAndClearData() {
        let dataStore = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        dataStore.removeData(ofTypes: types, modifiedSince: .distantPast) { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                self.hasSession = false
                self.load(Self.homeURL)
            }
        }
    }

    /// Checks whether a Chess.com session cookie exists. The cookie value is
    /// never read, stored or transmitted anywhere.
    func refreshSessionState() {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            let hasSession = cookies.contains { cookie in
                cookie.domain.contains("chess.com") && cookie.name == "PHPSESSID"
            }
            Task { @MainActor in self?.hasSession = hasSession }
        }
    }

    // MARK: - Live position detection

    fileprivate func handlePositionPayload(_ payload: ChessComPositionPayload) {
        detectionCount += 1
        onPositionPayload?(payload)
    }

    // MARK: - JavaScript dialogs

    /// Shows a JavaScript dialog and reports whether it could be presented. A
    /// page that waits for a dialog must never wait forever, so callers answer
    /// the completion handler themselves when this returns `false`.
    @discardableResult
    private func presentAlert(title: String, message: String, actions: [UIAlertAction]) -> Bool {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow })
                ?? scenes.first?.windows.first,
              let root = window.rootViewController else { return false }

        var presenter = root
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        actions.forEach { alert.addAction($0) }
        presenter.present(alert, animated: true)
        return true
    }
}

// MARK: - WKNavigationDelegate

extension ChessComBrowser: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        errorMessage = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        progress = 1
        currentURL = webView.url
        pageMode = ChessComPageMode.classify(webView.url)
        if let title = webView.title, !title.isEmpty { pageTitle = title }
        refreshSessionState()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled { return }
        errorMessage = error.localizedDescription
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        isLoading = false
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled { return }
        errorMessage = error.localizedDescription
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // iOS reclaimed the web process, usually under memory pressure while
        // the engine runs. Without this the tab would keep a blank page.
        isLoading = false
        errorMessage = nil
        navigationCount += 1
        webView.reload()
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if let scheme = url.scheme?.lowercased(),
           !["http", "https", "about", "blob", "data", "javascript"].contains(scheme) {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

// MARK: - WKUIDelegate

extension ChessComBrowser: WKUIDelegate {

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let shown = presentAlert(title: webView.title ?? "Chess.com",
                                 message: message,
                                 actions: [UIAlertAction(title: "OK", style: .default) { _ in completionHandler() }])
        if !shown { completionHandler() }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let shown = presentAlert(title: webView.title ?? "Chess.com",
                                 message: message,
                                 actions: [
                                    UIAlertAction(title: "Abbrechen", style: .cancel) { _ in completionHandler(false) },
                                    UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) }
                                 ])
        if !shown { completionHandler(false) }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let shown = presentAlert(title: webView.title ?? "Chess.com",
                                 message: prompt,
                                 actions: [
                                    UIAlertAction(title: "Abbrechen", style: .cancel) { _ in completionHandler(nil) },
                                    UIAlertAction(title: "OK", style: .default) { _ in completionHandler(defaultText) }
                                 ])
        if !shown { completionHandler(nil) }
    }
}

// MARK: - WKScriptMessageHandler

extension ChessComBrowser: WKScriptMessageHandler {

    nonisolated func userContentController(_ userContentController: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        // WKScriptMessageHandler delivers its messages on the main thread.
        MainActor.assumeIsolated {
            guard message.name == ChessComPositionScript.handlerName else { return }
            guard let body = message.body as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: body),
                  let payload = try? JSONDecoder().decode(ChessComPositionPayload.self, from: data) else {
                return
            }
            self.handlePositionPayload(payload)
        }
    }
}

// MARK: - SwiftUI wrapper

struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
