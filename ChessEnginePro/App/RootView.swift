//
//  RootView.swift
//  CHESS ENGINE PRO
//
//  Custom premium bottom navigation with the five main areas.
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

    @ViewBuilder
    private var content: some View {
        switch environment.selectedTab {
        case .home:
            HomeView()
        case .play:
            PlayView()
        case .analysis:
            AnalysisView()
        case .training:
            TrainingView()
        case .profile:
            ProfileView()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    if environment.selectedTab == tab {
                        // Repeated taps scroll to top / restart analysis.
                        if tab == .analysis { environment.analysis.analyze() }
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
                            .font(.system(size: 10, weight: .medium, design: .rounded))
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
