//
//  AppEnvironment.swift
//  CHESS ENGINE PRO
//
//  Single owner of the long lived stores and controllers.
//

import Foundation
import Combine
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home
    case chessCom
    case training
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .chessCom: return "Chess.com"
        case .training: return "Training"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .chessCom: return "crown.fill"
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
            // The panel on the Chess.com screen is the only analysis surface, so
            // it may use the full configured depth. On the other tabs the live
            // engine keeps running at a lower ceiling instead of idling.
            analysis.liveDepthCap = selectedTab == .chessCom ? nil : 12
            guard selectedTab == .chessCom else { return }
            if !hasOpenedChessCom { hasOpenedChessCom = true }
            browser.refreshSessionState()
            browser.requestLiveSnapshot()
        }
    }

    /// The manual analysis board is shown above the whole app.
    @Published var isAnalysisPresented = false

    /// The page is preloaded at launch, but its positions only reach the app
    /// once the Chess.com tab was actually opened - a hidden page must not move
    /// the board or start the engine behind the user's back.
    private var hasOpenedChessCom = false
    @Published var toastMessage: String?

    private var toastTask: Task<Void, Never>?
    private var pageModeSink: AnyCancellable?

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
            guard let self = self, let analysis = analysis else { return }
            // A hidden page, an open manual board or a rated online game must
            // never move the board or start a second calculation.
            guard self.hasOpenedChessCom, !self.isAnalysisPresented else { return }
            guard self.browser.allowsLiveSuggestions else { return }
            guard let detected = ChessComPositionDetector.detect(payload) else { return }
            analysis.ingest(detected, sequence: payload.sequence, session: payload.session)
        }

        // One gate for the whole app. Supported modes let the engine work, a
        // running online game stops it and clears the visible results.
        pageModeSink = browser.$pageMode
            .removeDuplicates()
            .sink { mode in
                Task { @MainActor [weak analysis] in
                    guard let analysis = analysis else { return }
                    analysis.liveSuggestionsAllowed = mode.allowsEngineSuggestions
                    if !mode.allowsEngineSuggestions {
                        analysis.suspendLiveAnalysis()
                    }
                }
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

    // MARK: - Manual analysis board

    /// Shows the analysis board (board, variants, preview, FEN tools) above the
    /// app. The engine keeps its single instance; only the visible surface
    /// changes.
    ///
    /// `deferred` waits until an importer, editor or sheet that triggered the
    /// request has finished dismissing, otherwise iOS refuses a second
    /// presentation at the same time.
    func presentAnalysis(deferred: Bool = false) {
        analysis.liveDepthCap = nil
        guard deferred else {
            isAnalysisPresented = true
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            self?.isAnalysisPresented = true
        }
    }

    func closeAnalysis() {
        isAnalysisPresented = false
        analysis.liveDepthCap = selectedTab == .chessCom ? nil : 12
        guard hasOpenedChessCom else { return }
        // The panel takes the Chess.com position back instead of keeping the
        // manually edited board.
        analysis.resumeFromChessCom()
        browser.requestLiveSnapshot(force: true)
    }

    /// Loads an imported game into the analysis board.
    func openInAnalysis(game: PGNGame) {
        analysis.load(game: game)
        presentAnalysis(deferred: true)
        showToast("Partie geladen – Analyse läuft")
    }

    /// Loads a position (FEN) into the analysis board.
    func openInAnalysis(fen: String) {
        do {
            try analysis.setFEN(fen)
            presentAnalysis(deferred: true)
        } catch {
            showToast("Ungültige FEN")
        }
    }
}
