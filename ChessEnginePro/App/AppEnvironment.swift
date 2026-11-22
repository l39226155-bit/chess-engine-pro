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
    case play
    case analysis
    case training
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .play: return "Play"
        case .analysis: return "Analyse"
        case .training: return "Training"
        case .profile: return "Profil"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .play: return "safari.fill"
        case .analysis: return "square.grid.3x3.fill"
        case .training: return "graduationcap.fill"
        case .profile: return "person.crop.circle.fill"
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

    @Published var selectedTab: AppTab = .home
    @Published var toastMessage: String?

    private var toastTask: Task<Void, Never>?

    init() {
        let settings = SettingsStore()
        self.settings = settings
        self.stats = TrainingStatsStore()
        self.analysis = AnalysisManager(settings: settings)
        self.review = GameReviewController(settings: settings)
        self.store = AnalysisStore.shared
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
        selectedTab = .analysis
        showToast("Partie geladen – Analyse läuft")
    }

    /// Loads a position (FEN) into the analysis screen.
    func openInAnalysis(fen: String) {
        do {
            try analysis.setFEN(fen)
            selectedTab = .analysis
        } catch {
            showToast("Ungültige FEN")
        }
    }

    func startGameReview(game: PGNGame) {
        selectedTab = .analysis
        showToast("Partieprüfung gestartet")
    }
}
