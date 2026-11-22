//
//  ChessEngineProApp.swift
//  CHESS ENGINE PRO
//

import SwiftUI

@main
struct ChessEngineProApp: App {

    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .environmentObject(environment.settings)
                .environmentObject(environment.stats)
                .environmentObject(environment.analysis)
                .environmentObject(environment.review)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
