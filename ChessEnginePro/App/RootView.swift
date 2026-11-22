//
//  RootView.swift
//  CHESS ENGINE PRO
//
//  Custom premium bottom navigation with the five main areas. The Chess.com
//  layer is mounted once and only hidden, never destroyed, so the embedded
//  WKWebView keeps its session and page state across tab switches.
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
        case .stockfish:
            AnalysisView()
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
                        // Repeated taps restart the analysis of the live position.
                        if tab == .stockfish { environment.analysis.analyze() }
                    } else {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            environment.selectedTab = tab
                        }
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .frame(height: 20)
                        Text(tab.title)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(environment.selectedTab == tab ? Theme.accent : Theme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
        .background(
            Theme.secondaryBackground
                .overlay(
                    Rectangle()
                        .fill(Theme.divider)
                        .frame(height: 1),
                    alignment: .top
                )
                .ignoresSafeArea(edges: .bottom)
        )
    }
}
