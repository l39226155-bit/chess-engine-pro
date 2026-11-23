//
//  LiveAnalysisPolicy.swift
//  CHESS ENGINE PRO
//
//  The single place that decides whether the engine may show suggestions for a
//  page that is currently open in the Chess.com web view.
//
//  Supported modes are analysis boards, puzzles/training and games against the
//  computer. A running rated online game against a human is not a supported
//  analysis mode, so the panel stays locked there - no evaluation, no best move
//  and no engine calculation at all.
//

import Foundation

/// What the embedded Chess.com page is currently used for. Classified from the
/// URL only - no page internals are read for this decision.
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

    /// Only these modes expose engine suggestions.
    var allowsEngineSuggestions: Bool {
        switch self {
        case .onlineGame: return false
        case .home, .computer, .analysis, .training: return true
        }
    }

    /// Short reason shown instead of suggestions, or `nil` when allowed.
    var explanation: String? {
        guard !allowsEngineSuggestions else { return nil }
        return "In laufenden gewerteten Online-Partien bleiben Engine-Vorschläge deaktiviert. Analysebrett, Training, Puzzles und Partien gegen den Computer sind freigeschaltet."
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

enum LiveAnalysisPolicy {

    /// Suggestions require both a supported mode and an enabled engine.
    static func allowsSuggestions(in mode: ChessComPageMode, engineEnabled: Bool) -> Bool {
        engineEnabled && mode.allowsEngineSuggestions
    }

    /// Note the panel shows while suggestions are unavailable.
    static func blockNote(for mode: ChessComPageMode) -> String? {
        mode.explanation
    }
}
