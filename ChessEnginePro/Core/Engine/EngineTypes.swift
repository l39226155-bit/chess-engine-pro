//
//  EngineTypes.swift
//  CHESS ENGINE PRO
//
//  Shared types between the Stockfish UCI engine and the built-in fallback.
//

import Foundation

// MARK: - Evaluation

/// An evaluation from White's point of view.
enum EvalScore: Hashable, Codable, Sendable {
    case centipawns(Int)
    case mate(Int)

    static let zero = EvalScore.centipawns(0)

    var isMate: Bool {
        if case .mate = self { return true }
        return false
    }

    /// Mate aware centipawn value used for quality classification and graphs.
    var whiteCentipawns: Int {
        switch self {
        case .centipawns(let value):
            return value
        case .mate(let moves):
            if moves == 0 { return 0 }
            let magnitude = 100_000 - abs(moves) * 100
            return moves > 0 ? magnitude : -magnitude
        }
    }

    var pawns: Double { Double(whiteCentipawns) / 100.0 }

    var display: String {
        switch self {
        case .centipawns(let value):
            let sign = value > 0 ? "+" : ""
            return sign + String(format: "%.2f", Double(value) / 100.0)
        case .mate(let moves):
            if moves == 0 { return "#" }
            return (moves > 0 ? "M" : "-M") + String(abs(moves))
        }
    }

    var localizedDescription: String {
        switch self {
        case .mate(let moves):
            if moves > 0 { return "Matt für Weiß in \(abs(moves))" }
            if moves < 0 { return "Matt für Schwarz in \(abs(moves))" }
            return "Matt"
        case .centipawns(let value):
            if value == 0 { return "Ausgeglichen" }
            let side = value > 0 ? "Weiß" : "Schwarz"
            return "\(side) +\(String(format: "%.2f", abs(Double(value)) / 100.0))"
        }
    }

    /// Win probability for White, used by the evaluation bar.
    var whiteWinProbability: Double {
        if case .mate(let moves) = self {
            if moves == 0 { return 0.5 }
            return moves > 0 ? 0.995 : 0.005
        }
        let cp = Double(max(-2000, min(2000, whiteCentipawns)))
        return 1.0 / (1.0 + exp(-cp / 400.0))
    }

    func inverted() -> EvalScore {
        switch self {
        case .centipawns(let value): return .centipawns(-value)
        case .mate(let moves): return .mate(-moves)
        }
    }

    /// Centipawn loss compared to a better score, mate aware and clamped.
    static func loss(from best: EvalScore, to candidate: EvalScore) -> Int {
        max(0, best.whiteCentipawns - candidate.whiteCentipawns)
    }
}

// MARK: - Lines

struct EngineLine: Identifiable, Hashable, Codable, Sendable {
    var rank: Int
    var score: EvalScore
    var depth: Int
    /// UCI moves, e.g. ["e2e4", "e7e5"].
    var pv: [String]
    var nodes: UInt64

    var id: Int { rank }

    var firstMove: Move? { pv.first.flatMap(Move.init(uci:)) }
}

struct EngineUpdate: Hashable, Sendable {
    var depth: Int
    var seldepth: Int
    var nodes: UInt64
    var timeMs: Int
    var lines: [EngineLine]
    var bestMove: Move?
    var isFinal: Bool

    var primaryScore: EvalScore? { lines.first?.score }

    var nps: Int {
        guard timeMs > 0 else { return 0 }
        return Int(nodes) * 1000 / timeMs
    }
}

struct EngineLimits: Hashable, Codable, Sendable {
    var depth: Int = 18
    var multiPV: Int = 3
    var moveTimeMs: Int?
    var nodes: UInt64?

    static func depth(_ depth: Int, multiPV: Int = 3) -> EngineLimits {
        EngineLimits(depth: depth, multiPV: multiPV, moveTimeMs: nil, nodes: nil)
    }

    static func time(_ milliseconds: Int, multiPV: Int = 3) -> EngineLimits {
        EngineLimits(depth: 60, multiPV: multiPV, moveTimeMs: milliseconds, nodes: nil)
    }
}

// MARK: - Engine protocol

protocol ChessEngine: AnyObject {
    var displayName: String { get }
    var isAvailable: Bool { get }
    func setOption(_ name: String, value: String)
    func analyze(fen: String, limits: EngineLimits) -> AsyncStream<EngineUpdate>
    func stop()
}

enum EngineError: LocalizedError {
    case unavailable
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Die Engine ist nicht verfügbar."
        case .cancelled: return "Analyse abgebrochen."
        }
    }
}
