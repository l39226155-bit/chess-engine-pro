//
//  MoveQuality.swift
//  CHESS ENGINE PRO
//
//  Every quality label is derived from the engine's evaluation, never guessed.
//  A move that loses material or a forced mate can therefore never be shown
//  as "excellent".
//

import Foundation

enum MoveQuality: String, Codable, CaseIterable, Hashable, Sendable {
    case excellent
    case veryGood
    case good
    case interesting
    case inaccuracy
    case mistake
    case blunder

    var localizedTitle: String {
        switch self {
        case .excellent: return "Hervorragend"
        case .veryGood: return "Sehr gut"
        case .good: return "Gut"
        case .interesting: return "Interessant"
        case .inaccuracy: return "Ungenauigkeit"
        case .mistake: return "Fehler"
        case .blunder: return "Patzer"
        }
    }

    var symbol: String {
        switch self {
        case .excellent: return "!!"
        case .veryGood: return "!"
        case .good: return "✓"
        case .interesting: return "★"
        case .inaccuracy: return "?!"
        case .mistake: return "?"
        case .blunder: return "??"
        }
    }

    var sfSymbol: String {
        switch self {
        case .excellent: return "star.circle.fill"
        case .veryGood: return "checkmark.seal.fill"
        case .good: return "checkmark.circle.fill"
        case .interesting: return "sparkles"
        case .inaccuracy: return "exclamationmark.triangle.fill"
        case .mistake: return "xmark.circle.fill"
        case .blunder: return "xmark.octagon.fill"
        }
    }

    /// True for labels that mark a mistake.
    var isProblem: Bool {
        switch self {
        case .inaccuracy, .mistake, .blunder: return true
        default: return false
        }
    }

    /// Centipawn loss thresholds (mate scores are mapped to huge centipawn values).
    static func classify(loss: Int) -> MoveQuality {
        switch loss {
        case ..<11: return .excellent
        case 11...25: return .veryGood
        case 26...50: return .good
        case 51...100: return .interesting
        case 101...200: return .inaccuracy
        case 201...400: return .mistake
        default: return .blunder
        }
    }

    static func classify(best: EvalScore, candidate: EvalScore) -> MoveQuality {
        classify(loss: EvalScore.loss(from: best, to: candidate))
    }

    /// Quality for a played move that was compared against the engine's best move.
    static func classifyForPlayedMove(best: EvalScore?) -> MoveQuality {
        guard let best = best else { return .good }
        return classify(best: best, candidate: best)
    }
}
