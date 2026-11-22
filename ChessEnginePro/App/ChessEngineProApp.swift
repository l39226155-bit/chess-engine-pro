//
//  ChessEngineProApp.swift
//  CHESS ENGINE PRO
//

import SwiftUI

@main
struct ChessEngineProApp: App {

    @StateObject private var environment = AppEnvironment()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .environmentObject(environment.settings)
                .environmentObject(environment.stats)
                .environmentObject(environment.analysis)
                .environmentObject(environment.review)
                .environmentObject(environment.browser)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onChange(of: scenePhase) { _, phase in
                    environment.handleScenePhase(phase)
                }
        }
    }
}
