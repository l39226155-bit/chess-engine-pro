//
//  AppEnvironment.swift
//  CHESS ENGINE PRO
//
//  Single owner of the long lived stores and controllers.
//

import Foundation
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home
    case chessCom
    case stockfish
    case training
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .chessCom: return "Chess.com"
        case .stockfish: return "Stockfish"
        case .training: return "Training"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .chessCom: return "safari.fill"
        case .stockfish: return "cpu"
        case .training: return "graduationcap.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

@MainActor
final class AppEnvironment: ObservableObject {

    let settings: SettingsStore
    let stats: TrainingStatsStore
    let analysis: AnalysisManager
    let review: GameReviewController
    let store: AnalysisStore
    /// Long lived Chess.com web view - created once, never torn down.
    let browser: ChessComBrowser
    /// Central engine owner (single instance, lifecycle aware).
    let engineManager: EngineManager

    @Published var selectedTab: AppTab = .home
    @Published var toastMessage: String?

    private var toastTask: Task<Void, Never>?

    init() {
        let settings = SettingsStore()
        let engineManager = EngineManager(settings: settings)
        let analysis = AnalysisManager(settings: settings, engines: engineManager)

        self.settings = settings
        self.engineManager = engineManager
        self.analysis = analysis
        self.stats = TrainingStatsStore()
        self.review = GameReviewController(settings: settings)
        self.store = AnalysisStore.shared
        self.browser = ChessComBrowser()

        engineManager.suspendHandler = { [weak analysis] in
            analysis?.pauseForBackground()
        }
        engineManager.resumeHandler = { [weak analysis] in
            analysis?.resumeAfterBackground()
        }
    }

    /// iOS lifecycle: stop heavy work in the background, continue on return.
    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            engineManager.suspend()
        case .active:
            engineManager.resume()
            if selectedTab == .chessCom { browser.refreshSessionState() }
        default:
            break
        }
    }

    func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            toastMessage = message
        }
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_300_000_000)
            guard let self = self, !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { self.toastMessage = nil }
        }
    }

    /// Loads an imported game into the analysis screen.
    func openInAnalysis(game: PGNGame) {
        analysis.load(game: game)
        selectedTab = .stockfish
        showToast("Partie geladen – Analyse läuft")
    }

    /// Loads a position (FEN) into the analysis screen.
    func openInAnalysis(fen: String) {
        do {
            try analysis.setFEN(fen)
            selectedTab = .stockfish
        } catch {
            showToast("Ungültige FEN")
        }
    }

    func startGameReview(game: PGNGame) {
        selectedTab = .stockfish
        showToast("Partieprüfung gestartet")
    }
}
