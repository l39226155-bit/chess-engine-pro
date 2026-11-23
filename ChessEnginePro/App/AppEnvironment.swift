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
        case .chessCom: return "crown.fill"
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

    @Published var selectedTab: AppTab = .home {
        didSet {
            guard oldValue != selectedTab else { return }
            // Live analysis runs at a lower ceiling while the user is playing on
            // Chess.com; the analysis screen always gets the full depth.
            analysis.liveDepthCap = selectedTab == .chessCom ? 12 : nil
            if selectedTab == .chessCom { hasOpenedChessCom = true }
        }
    }

    /// The page is preloaded at launch, but its positions only reach the app
    /// once the Chess.com tab was actually opened - a hidden page must not move
    /// the board or start the engine behind the user's back.
    private var hasOpenedChessCom = false
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

        analysis.liveDepthCap = 12
        // Every payload the page posts is verified before it reaches the model:
        // the detector rebuilds the position from the board and the move list,
        // the synchroniser then rejects stale, duplicate and invalid updates.
        browser.onPositionPayload = { [weak self, weak analysis] payload in
            guard let self = self, let analysis = analysis, self.hasOpenedChessCom else { return }
            guard let detected = ChessComPositionDetector.detect(payload) else { return }
            analysis.ingest(detected, sequence: payload.sequence, session: payload.session)
        }
    }

    /// iOS lifecycle: stop heavy work in the background, continue on return.
    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            engineManager.suspend()
        case .active:
            engineManager.resume()
            if selectedTab == .chessCom {
                browser.refreshSessionState()
                // The page may have changed while the app was suspended.
                browser.requestLiveSnapshot()
            }
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
