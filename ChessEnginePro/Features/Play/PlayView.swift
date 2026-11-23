//
//  PlayView.swift
//  CHESS ENGINE PRO
//
//  Embedded Chess.com experience with a native browser chrome.
//

import SwiftUI

struct PlayView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var browser: ChessComBrowser
    @EnvironmentObject private var analysis: AnalysisManager

    var body: some View {
        VStack(spacing: 0) {
            browserBar
            ZStack(alignment: .top) {
                WebViewContainer(webView: browser.webView)
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
            liveStrip
            quickLinks
        }
        .background(Theme.background)
        .onAppear {
            if environment.selectedTab == .chessCom { browser.startIfNeeded() }
            browser.refreshSessionState()
        }
        .onChange(of: environment.selectedTab) { _, newValue in
            // The web view is never rebuilt; visiting the tab only refreshes
            // the local session badge (no navigation, no reload).
            guard newValue == .chessCom else { return }
            browser.startIfNeeded()
            browser.refreshSessionState()
        }
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
            return "\(event) · Zug \(snapshot.ply) · \(snapshot.statusText)"
        }
        if browser.detectionCount > 0 {
            return "\(browser.detectionCount) Messungen · noch keine gültige Stellung"
        }
        return "Öffne eine Partie oder Analyse auf Chess.com"
    }

    // MARK: - Chrome

    private var browserBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    browser.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(IconButtonStyle())
                .disabled(!browser.canGoBack)
                .opacity(browser.canGoBack ? 1 : 0.4)

                Button {
                    browser.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(IconButtonStyle())
                .disabled(!browser.canGoForward)
                .opacity(browser.canGoForward ? 1 : 0.4)

                HStack(spacing: 6) {
                    Image(systemName: browser.hasSession ? "lock.fill" : "globe")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(browser.hasSession ? Theme.accent : Theme.secondaryText)
                    Text(browser.currentURL?.host ?? "chess.com")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Spacer()
                    if browser.hasSession {
                        Text("ANGEMELDET")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.field))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Theme.divider, lineWidth: 1)
                )

                Button {
                    browser.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(IconButtonStyle())

                Menu {
                    Button {
                        browser.openLogin()
                    } label: {
                        Label("Chess.com Login", systemImage: "person.badge.key")
                    }
                    Button {
                        browser.goHome()
                    } label: {
                        Label("Startseite", systemImage: "house")
                    }
                    Button {
                        browser.openExternally()
                    } label: {
                        Label("In Safari öffnen", systemImage: "safari")
                    }
                    Divider()
                    Button(role: .destructive) {
                        browser.signOutAndClearData()
                        environment.showToast("Sitzung gelöscht")
                    } label: {
                        Label("Sitzung löschen", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .buttonStyle(IconButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    quickLink("Start", url: ChessComBrowser.homeURL)
                    quickLink("Online spielen", url: ChessComBrowser.playURL)
                    quickLink("Puzzles", url: ChessComBrowser.puzzlesURL)
                    quickLink("Profil", url: ChessComBrowser.profileURL)
                    quickLink("Einstellungen", url: ChessComBrowser.settingsURL)
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.bottom, 8)
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

    private var quickLinks: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.accent)
            Text("Sitzung und Partie bleiben beim Tabwechsel erhalten. Anmeldung nur über die offizielle Chess.com-Seite.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.secondaryBackground)
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
