//
//  LiveAnalysisPolicy.swift
//  CHESS ENGINE PRO
//
//  Engine assistance is only acceptable where it is allowed: training, analysis
//  boards and games that are already finished. A running online game on
//  Chess.com is never analysed automatically, and the analysis screen refuses to
//  start while such a game is mirrored - otherwise the app itself would offer a
//  way around Chess.com's fair play rules.
//

import Foundation

enum LiveAnalysisPermission: Equatable, Sendable {
    case allowed(context: String)
    case blocked(reason: String)

    var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }

    var contextLabel: String? {
        if case .allowed(let context) = self { return context }
        return nil
    }

    var blockedReason: String? {
        if case .blocked(let reason) = self { return reason }
        return nil
    }
}

enum LiveAnalysisPolicy {

    /// Decides whether the engine may run for a detected page.
    static func permission(url: String, isGameOver: Bool) -> LiveAnalysisPermission {
        let path = normalizedPath(url)

        if path.contains("/analysis") {
            return .allowed(context: "Analysebrett")
        }
        if path.contains("/puzzles") || path.contains("/puzzle") {
            return .allowed(context: "Puzzle-Training")
        }
        if path.contains("/training") || path.contains("/lessons") || path.contains("/drills") {
            return .allowed(context: "Training")
        }
        if path.contains("/play/computer") || path.contains("/computer") {
            return .allowed(context: "Partie gegen den Computer")
        }
        if isGameOver {
            return .allowed(context: "Partie beendet")
        }
        if isLiveGame(path) {
            return .blocked(reason: "Laufende Online-Partie – Engine-Hilfe ist auf Chess.com nicht erlaubt.")
        }
        return .blocked(reason: "Keine freigegebene Trainings- oder Analyseumgebung – die Engine bleibt aus.")
    }

    private static func isLiveGame(_ path: String) -> Bool {
        path.contains("/game/")
            || path.contains("/play/")
            || path.contains("/live")
            || path == "/play"
    }

    /// Uses the URL path only; query strings never decide the permission.
    private static func normalizedPath(_ url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let components = URLComponents(string: trimmed) {
            return components.path.lowercased()
        }
        return trimmed.lowercased()
    }
}
