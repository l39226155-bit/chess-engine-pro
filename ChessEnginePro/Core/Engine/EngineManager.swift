//
//  EngineManager.swift
//  CHESS ENGINE PRO
//
//  Central owner of the chess engines: picks the backend, keeps exactly one
//  engine instance alive and pauses CPU heavy work when iOS suspends the app.
//

import Foundation
import Combine

@MainActor
final class EngineManager: ObservableObject {

    /// Called when iOS moves the app to the background.
    var suspendHandler: (() -> Void)?
    /// Called when the app becomes active again.
    var resumeHandler: (() -> Void)?

    @Published private(set) var isSuspended = false
    @Published private(set) var engineName: String = StockfishBuild.displayName

    private let settings: SettingsStore
    private let stockfish = StockfishEngine.shared
    private let fallback = FallbackEngine()

    init(settings: SettingsStore) {
        self.settings = settings
    }

    // MARK: - Backend selection

    /// The single engine instance used for every analysis in the app.
    var engine: ChessEngine {
        switch settings.settings.backend {
        case .builtIn:
            return fallback
        case .stockfish, .auto:
            return stockfish.isAvailable ? stockfish : fallback
        }
    }

    var usesStockfish: Bool { engine === stockfish }

    var isBusy: Bool { isSuspended }

    // MARK: - Options

    /// Applies the user's engine configuration before a search starts.
    func configure() {
        let settings = self.settings.settings
        let engine = self.engine
        engineName = engine.displayName
        engine.setOption("Threads", value: "\(settings.effectiveThreads)")
        engine.setOption("Hash", value: "\(max(16, settings.hashMB))")
        engine.setOption("MultiPV", value: "\(max(1, settings.multiPV))")
        engine.setOption("UCI_LimitStrength", value: "false")
    }

    func stop() {
        engine.stop()
    }

    // MARK: - App lifecycle

    /// Stops calculations and remembers that they should continue on return.
    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        stop()
        suspendHandler?()
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        resumeHandler?()
    }
}
