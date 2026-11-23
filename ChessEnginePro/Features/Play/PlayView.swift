//
//  PlayView.swift
//  CHESS ENGINE PRO
//
//  The merged Chess.com screen: a compact header, the untouched Chess.com page
//  and the integrated Stockfish panel directly underneath. Only the page itself
//  is shown - no address bar, no back/forward chrome - so the screen reads as
//  one app instead of a browser window with a widget.
//

import SwiftUI

struct PlayView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var browser: ChessComBrowser
    @EnvironmentObject private var analysis: AnalysisManager

    var body: some View {
        VStack(spacing: 0) {
            header
            webArea
            AnalysisPanelView()
        }
        .background(Theme.background)
        .onAppear {
            // Start once, during the app's first layout. The page is then ready
            // before the tab is opened and never has to be reloaded later, which
            // is what keeps a running game and its session alive.
            browser.startIfNeeded()
            browser.refreshSessionState()
        }
        .onChange(of: environment.selectedTab) { _, newValue in
            // The web view is never rebuilt; visiting the tab only refreshes the
            // layout and the session badge (no navigation, no reload).
            guard newValue == .chessCom else { return }
            browser.prepareForDisplay()
            browser.refreshSessionState()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.accentMuted)
                    .frame(width: 28, height: 28)
                Image(systemName: "crown.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Chess.com")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                HStack(spacing: 5) {
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 5, height: 5)
                    Text(statusText)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            syncIndicator

            Menu {
                Button { browser.load(ChessComBrowser.homeURL) } label: {
                    Label("Start", systemImage: "house")
                }
                Button { browser.load(ChessComBrowser.playURL) } label: {
                    Label("Online spielen", systemImage: "play.circle")
                }
                Button { browser.load(ChessComBrowser.puzzlesURL) } label: {
                    Label("Puzzles", systemImage: "puzzlepiece")
                }
                Button { browser.load(ChessComBrowser.profileURL) } label: {
                    Label("Profil", systemImage: "person.crop.circle")
                }
                Button { browser.openLogin() } label: {
                    Label("Login", systemImage: "person.badge.key")
                }
                Divider()
                Button { browser.reload() } label: {
                    Label("Seite neu laden", systemImage: "arrow.clockwise")
                }
                Button { environment.presentAnalysis() } label: {
                    Label("Analysebrett öffnen", systemImage: "square.grid.3x3")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 30, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.elevated)
                    )
            }
            .accessibilityLabel("Seite, Sitzung und Analysebrett")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.secondaryBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.divider).frame(height: 1)
        }
    }

    private var connectionColor: Color {
        if browser.errorMessage != nil { return Theme.error }
        if browser.isLoading { return Theme.warning }
        return Theme.accent
    }

    private var statusText: String {
        if browser.errorMessage != nil { return "Verbindung unterbrochen" }
        if browser.isLoading && browser.currentURL == nil { return "Verbindung wird aufgebaut" }
        let connection = browser.isLoading ? "Lädt" : "Verbunden"
        let session = browser.hasSession ? "Angemeldet" : "Nicht angemeldet"
        return "\(connection) · \(session) · \(browser.pageMode.localizedTitle)"
    }

    /// Quiet synchronisation glyph. It turns into a spinner only while the page
    /// is actually loading, so the header never draws attention otherwise.
    @ViewBuilder
    private var syncIndicator: some View {
        if browser.isLoading {
            ProgressView()
                .controlSize(.mini)
                .tint(Theme.accent)
                .frame(width: 26, height: 28)
                .accessibilityLabel("Seite wird geladen")
        } else {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(browser.detectionCount > 0 ? Theme.accent : Theme.secondaryText.opacity(0.55))
                .frame(width: 26, height: 28)
                .accessibilityLabel(browser.detectionCount > 0
                                     ? "Stellung wird synchronisiert"
                                     : "Noch keine Stellung erkannt")
        }
    }

    // MARK: - Page

    private var webArea: some View {
        ZStack(alignment: .top) {
            WebViewContainer(webView: browser.webView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)

            if browser.isLoading {
                ProgressView(value: max(0.03, min(1, browser.progress)))
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
            }

            if let message = browser.errorMessage {
                errorBanner(message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 20))
                .foregroundStyle(Theme.warning)
            Text("Chess.com konnte nicht geladen werden")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            Button("Erneut versuchen") { browser.reload() }
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(16)
        .premiumCard()
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.opacity(0.94))
    }
}
