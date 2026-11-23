//
//  PlayView.swift
//  CHESS ENGINE PRO
//
//  Embedded Chess.com experience. Only the page itself is shown - no address
//  bar, no back/forward buttons, no reload menu - so the tab reads as part of
//  the app instead of a browser window.
//

import SwiftUI

struct PlayView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var browser: ChessComBrowser
    @EnvironmentObject private var analysis: AnalysisManager

    var body: some View {
        VStack(spacing: 0) {
            header
            quickLinks
            ZStack(alignment: .top) {
                WebViewContainer(webView: browser.webView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)

                if browser.isLoading {
                    ProgressView(value: max(0.03, browser.progress))
                        .progressViewStyle(.linear)
                        .tint(Theme.accent)
                }

                if let message = browser.errorMessage {
                    errorBanner(message)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            liveStrip
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
        HStack(spacing: 10) {
            Image(systemName: "crown.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Theme.accent.opacity(0.14)))

            VStack(alignment: .leading, spacing: 1) {
                Text("Chess.com")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text(browser.hasSession
                     ? "Angemeldet · Sitzung bleibt gespeichert"
                     : "Nicht angemeldet · Anmeldung über Chess.com")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if browser.isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .tint(Theme.accent)
                    .frame(width: 30, height: 30)
            } else {
                Button {
                    browser.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Theme.panel))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Seite neu laden")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Theme.secondaryBackground)
    }

    private var quickLinks: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                quickLink("Start", url: ChessComBrowser.homeURL)
                quickLink("Online spielen", url: ChessComBrowser.playURL)
                quickLink("Puzzles", url: ChessComBrowser.puzzlesURL)
                quickLink("Profil", url: ChessComBrowser.profileURL)
                quickLink("Login", url: ChessComBrowser.loginURL)
            }
            .padding(.horizontal, 14)
        }
        .padding(.vertical, 8)
        .background(Theme.secondaryBackground)
    }

    private func quickLink(_ title: String, url: URL) -> some View {
        Button {
            browser.load(url)
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.panel))
                .overlay(Capsule().stroke(Theme.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Live detection

    private var liveStrip: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(analysis.liveSource == .chessCom ? Theme.info : Theme.secondaryText)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text("Live-Erkennung")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text(liveDetail)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if analysis.isAnalyzing {
                Text("T\(analysis.depth)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
            }

            Button {
                environment.selectedTab = .stockfish
            } label: {
                Text("Analyse")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.accent.opacity(0.14)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.panel)
        .overlay(
            Rectangle().fill(Theme.divider).frame(height: 1),
            alignment: .top
        )
    }

    private var liveDetail: String {
        if analysis.liveSource == .chessCom, let snapshot = analysis.liveSnapshot {
            let event = analysis.liveEvent?.kind.localizedTitle ?? "Stellung erkannt"
            let estimated = snapshot.confidence.isExact ? "" : " · teilweise geschätzt"
            return "\(event) · Zug \(snapshot.ply) · \(snapshot.statusText)\(estimated)"
        }
        if browser.detectionCount > 0 {
            return "\(browser.detectionCount) Messungen · noch keine gültige Stellung"
        }
        return "Öffne eine Partie, ein Puzzle oder ein Analysebrett"
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 22))
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
        .padding(18)
        .premiumCard()
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.opacity(0.94))
    }
}
