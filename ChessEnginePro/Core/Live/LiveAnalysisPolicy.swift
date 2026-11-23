//
//  LiveAnalysisPolicy.swift
//  CHESS ENGINE PRO
//
//  The single place that decides whether the engine may show suggestions for a
//  Chess.com page, and for a local demo session.
//
//  Modes and their handling:
//
//  | Mode                                   | Engine suggestions |
//  | -------------------------------------- | ------------------ |
//  | Computer game (/play/computer)         | yes                |
//  | Analysis board (/analysis)             | yes                |
//  | Training and puzzles (/puzzles, ...)   | yes                |
//  | Chess.com home / profile               | yes (no board)     |
//  | Running game against a human (/game/…) | no                 |
//  | Finished game (same page, game over)   | yes                |
//
//  A local demo session is a shared screen: everybody present sees the engine.
//  It never unlocks a running online game - that guard is not configurable.
//

import Foundation

/// What the embedded Chess.com page is currently used for. Classified from the
/// URL and the detected game-over state only.
enum ChessComPageMode: String, Equatable, Sendable {
    case home
    case computer
    case analysis
    case training
    case onlineGame

    var localizedTitle: String {
        switch self {
        case .home: return "Chess.com"
        case .computer: return "Gegen Computer"
        case .analysis: return "Analysebrett"
        case .training: return "Training"
        case .onlineGame: return "Online-Partie"
        }
    }

    var sfSymbol: String {
        switch self {
        case .home: return "crown.fill"
        case .computer: return "desktopcomputer"
        case .analysis: return "square.grid.3x3.fill"
        case .training: return "graduationcap.fill"
        case .onlineGame: return "person.2.fill"
        }
    }

    /// Only these modes expose engine suggestions while the game is running.
    var allowsEngineSuggestions: Bool {
        switch self {
        case .onlineGame: return false
        case .home, .computer, .analysis, .training: return true
        }
    }

    var isOnlineGame: Bool { self == .onlineGame }

    /// Short reason shown instead of suggestions, or `nil` when allowed.
    var explanation: String? {
        guard !allowsEngineSuggestions else { return nil }
        return "Laufende Partie gegen einen Menschen: Engine-Vorschläge sind gesperrt. Sobald die Partie beendet ist, wird sie automatisch analysiert – Analysebrett, Training, Puzzles und Partien gegen den Computer sind jederzeit freigeschaltet."
    }

    /// Maps a Chess.com URL to its mode. The computer lobby also lives under
    /// `/play`, so it is checked before the generic online paths.
    static func classify(_ url: URL?) -> ChessComPageMode {
        guard let url = url else { return .home }
        let host = (url.host ?? "").lowercased()
        guard host.isEmpty || host.contains("chess.com") else { return .home }

        let path = url.path.lowercased()
        if path.hasPrefix("/play/computer") || path.hasPrefix("/computer") { return .computer }
        if path.hasPrefix("/analysis") || path.hasPrefix("/explorer") { return .analysis }
        if path.hasPrefix("/puzzles")
            || path.hasPrefix("/practice")
            || path.hasPrefix("/lessons")
            || path.hasPrefix("/drills") { return .training }
        if path.hasPrefix("/game")
            || path.hasPrefix("/play")
            || path.hasPrefix("/live") { return .onlineGame }
        return .home
    }
}

/// Result of the gate for the position that is currently on screen.
enum AnalysisAvailability: Equatable, Sendable {
    case enabled
    case blocked(reason: String)

    var isEnabled: Bool {
        if case .enabled = self { return true }
        return false
    }

    var reason: String? {
        if case .blocked(let reason) = self { return reason }
        return nil
    }
}

enum LiveAnalysisPolicy {

    /// Suggestions need an enabled engine and either a supported mode or a
    /// finished online game. A running game against a human stays blocked.
    static func allowsSuggestions(in mode: ChessComPageMode,
                                  engineEnabled: Bool,
                                  isGameOver: Bool = false) -> Bool {
        guard engineEnabled else { return false }
        if mode.allowsEngineSuggestions { return true }
        return mode.isOnlineGame && isGameOver
    }

    /// Full decision including the explanation used by the panel.
    static func availability(in mode: ChessComPageMode,
                             engineEnabled: Bool,
                             isGameOver: Bool) -> AnalysisAvailability {
        if allowsSuggestions(in: mode, engineEnabled: engineEnabled, isGameOver: isGameOver) {
            return .enabled
        }
        if !engineEnabled {
            return .blocked(reason: "Die Engine ist in den Einstellungen deaktiviert.")
        }
        return .blocked(reason: mode.explanation
                        ?? "Engine-Vorschläge sind für diese Ansicht nicht verfügbar.")
    }

    /// Note the panel shows while suggestions are unavailable.
    static func blockNote(for mode: ChessComPageMode) -> String? {
        mode.explanation
    }
}
