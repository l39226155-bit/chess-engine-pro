//
//  RootView.swift
//  CHESS ENGINE PRO
//
//  Four tabs. The Chess.com screen is the central workspace and the only place
//  the web view lives: it is mounted once and only hidden, never destroyed, so
//  the embedded WKWebView keeps its session and page state across tab switches.
//

import SwiftUI

struct RootView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            tabBar
        }
        .background(Theme.background.ignoresSafeArea())
        .overlay(alignment: .top) {
            if let message = environment.toastMessage {
                Toast(text: message)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .fullScreenCover(isPresented: $environment.isAnalysisPresented,
                         onDismiss: { environment.closeAnalysis() }) {
            AnalysisView(onClose: { environment.isAnalysisPresented = false })
                .environmentObject(environment)
                .environmentObject(settings)
                .environmentObject(environment.analysis)
                .environmentObject(environment.browser)
        }
        .onAppear {
            if settings.settings.engineEnabled {
                environment.analysis.analyze()
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        ZStack {
            // Long lived layer: opacity 0 keeps the web view in the hierarchy,
            // which preserves the chess.com page, its cookies, scroll offset and
            // any running game. Rebuilding it would reload the site.
            PlayView()
                .opacity(environment.selectedTab == .chessCom ? 1 : 0)
                .allowsHitTesting(environment.selectedTab == .chessCom)
                .accessibilityHidden(environment.selectedTab != .chessCom)

            if environment.selectedTab != .chessCom {
                tabContent
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch environment.selectedTab {
        case .home:
            HomeView()
        case .training:
            TrainingView()
        case .settings:
            SettingsView()
        case .chessCom:
            EmptyView()
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    if environment.selectedTab == tab {
                        // Repeated taps refresh the panel's position without
                        // touching the page.
                        if tab == .chessCom {
                            environment.browser.prepareForDisplay()
                        }
                    } else {
                        environment.selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .frame(height: 19)
                        Text(tab.title)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(environment.selectedTab == tab ? Theme.accent : Theme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 7)
                    .padding(.bottom, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .background(
            Theme.secondaryBackground
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Theme.divider)
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }
}
