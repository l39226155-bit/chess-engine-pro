//
//  NaturalMoveSelection.swift
//  CHESS ENGINE PRO
//
//  "Natural move selection": the engine always reports objective evaluations,
//  while the style profiles describe *how* a candidate plays. Style fit is a
//  transparent score derived from concrete features of the position, and it is
//  always penalised by the real evaluation loss so a bad move never looks good.
//

import Foundation

// MARK: - Play styles

enum MoveStyle: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case solid
    case aggressive
    case positional
    case tactical
    case balanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solid: return "SOLID"
        case .aggressive: return "AGGRESSIVE"
        case .positional: return "POSITIONAL"
        case .tactical: return "TACTICAL"
        case .balanced: return "BALANCED"
        }
    }

    var localizedTitle: String {
        switch self {
        case .solid: return "Solide"
        case .aggressive: return "Aggressiv"
        case .positional: return "Positionell"
        case .tactical: return "Taktisch"
        case .balanced: return "Ausgewogen"
        }
    }

    var summary: String {
        switch self {
        case .solid:
            return "Sichere Entwicklung, Königssicherheit und wenig Risiko."
        case .aggressive:
            return "Aktive Figuren, offene Linien und Initiative."
        case .positional:
            return "Langfristige Verbesserung, Zentrum und Bauernstruktur."
        case .tactical:
            return "Kombinationen, Gabeln, Fesselungen und Abzugsschach."
        case .balanced:
            return "Ausgewogene Mischung aller Spielideen."
        }
    }

    var sfSymbol: String {
        switch self {
        case .solid: return "shield.lefthalf.filled"
        case .aggressive: return "flame.fill"
        case .positional: return "square.grid.3x3.square"
        case .tactical: return "bolt.fill"
        case .balanced: return "circle.hexagongrid.fill"
        }
    }
}

// MARK: - Features of a single move

struct MoveFeatures: Hashable, Sendable {
    var isCapture = false
    var isCheck = false
    var isCastle = false
    var isPromotion = false
    var isSacrifice = false
    var isQuiet = true
    var capturedValue = 0
    var movedPieceValue = 0
    var createsFork = false
    var opensFile = false
    var controlsCenter = false
    var developsPiece = false
    var isRetreat = false
    var isKingMove = false
    var pawnMoveNearKing = false
    var attacksQueenOrKing = false
    var materialGain = 0
    var mobilityDelta = 0

    static let centerSquares: Set<String> = ["d4", "e4", "d5", "e5"]

    /// Derives every feature from the position before the move.
    static func make(for move: Move, on board: Board) -> MoveFeatures {
        var features = MoveFeatures()
        guard let piece = board.squares[move.from.index] else { return features }

        let next = board.applying(move)
        let opponent = piece.color.opponent

        features.isCastle = piece.kind == .king && abs(move.to.file - move.from.file) == 2
        features.isPromotion = move.promotion != nil
        features.isKingMove = piece.kind == .king
        features.movedPieceValue = piece.kind.value

        let target = board.squares[move.to.index]
        let isEnPassant = piece.kind == .pawn && move.from.file != move.to.file && target == nil
        features.isCapture = target != nil || isEnPassant
        features.capturedValue = (target?.kind.value ?? 0) + (isEnPassant ? 100 : 0)
        features.isCheck = next.isInCheck(next.sideToMove)
        features.isQuiet = !features.isCapture && !features.isCheck && !features.isPromotion

        let destinationAttacked = next.isAttacked(move.to, by: opponent)
        features.isSacrifice = destinationAttacked
            && features.movedPieceValue > features.capturedValue + 50
            && !features.isCastle

        let attacked = next.attackedTargets(from: move.to)
        var valuableTargets = 0
        for square in attacked {
            guard let hit = next.squares[square.index], hit.color == opponent else { continue }
            if hit.kind.value >= 300 { valuableTargets += 1 }
            if hit.kind == .king { valuableTargets += 1 }
            if hit.kind == .queen || hit.kind == .king {
                features.attacksQueenOrKing = true
            }
        }
        features.createsFork = valuableTargets >= 2

        features.controlsCenter = MoveFeatures.centerSquares.contains(move.to.name)
            || attacked.contains { MoveFeatures.centerSquares.contains($0.name) }

        if piece.kind == .rook || piece.kind == .queen {
            let ownPawns = next.pieces(for: piece.color)
            features.opensFile = !ownPawns.contains { $0.piece.kind == .pawn && $0.square.file == move.to.file }
        }

        let homeRank = piece.color == .white ? 0 : 7
        features.developsPiece = (piece.kind == .knight || piece.kind == .bishop)
            && move.from.rank == homeRank
            && move.to.rank != homeRank

        let forward = piece.color == .white ? move.to.rank - move.from.rank : move.from.rank - move.to.rank
        features.isRetreat = forward < 0 && piece.kind != .pawn

        if piece.kind == .pawn, let king = board.kingSquare(for: piece.color) {
            features.pawnMoveNearKing = abs(move.from.file - king.file) <= 1
        }

        features.materialGain = features.capturedValue - (destinationAttacked ? features.movedPieceValue / 2 : 0)
        features.mobilityDelta = next.pseudoMoveCount(for: piece.color)
            - board.pseudoMoveCount(for: piece.color)

        return features
    }
}

// MARK: - Board helpers

extension Board {

    /// True when the piece standing on `origin` attacks `target`.
    /// A minimal probe position avoids counting attacks from other pieces.
    func pieceAttacks(from origin: Square, target: Square) -> Bool {
        guard let piece = squares[origin.index] else { return false }
        if piece.kind == .pawn {
            let direction = piece.color == .white ? 1 : -1
            return target.rank == origin.rank + direction && abs(target.file - origin.file) == 1
        }
        var probe = Board.empty
        probe.squares[origin.index] = piece
        probe.squares[target.index] = Piece(color: piece.color.opponent, kind: .pawn)
        probe.sideToMove = piece.color
        return probe.isAttacked(target, by: piece.color)
    }

    func attackedTargets(from origin: Square) -> [Square] {
        Square.all.filter { pieceAttacks(from: origin, target: $0) }
    }

    func pseudoMoveCount(for color: PieceColor) -> Int {
        var total = 0
        for index in 0..<64 {
            guard let piece = squares[index], piece.color == color else { continue }
            total += pseudoLegalMoves(from: Square(index: index)).count
        }
        return total
    }
}

// MARK: - Style fit and tags

enum NaturalMoveSelector {

    /// 0...100 style match, always reduced by the objective evaluation loss.
    static func styleFit(style: MoveStyle,
                         features: MoveFeatures,
                         quality: MoveQuality,
                         score: EvalScore,
                         bestScore: EvalScore) -> Double {
        var value = 50.0

        switch style {
        case .solid:
            if features.isCastle { value += 22 }
            if features.developsPiece { value += 12 }
            if features.isQuiet { value += 8 }
            if features.isSacrifice { value -= 26 }
            if features.isKingMove && !features.isCastle { value -= 14 }
            if features.pawnMoveNearKing { value -= 12 }
            if features.isCapture { value += 4 }

        case .aggressive:
            if features.isCheck { value += 18 }
            if features.isSacrifice { value += 18 }
            if features.attacksQueenOrKing { value += 14 }
            if features.opensFile { value += 10 }
            if features.controlsCenter { value += 8 }
            if features.isRetreat { value -= 15 }
            if features.isCastle { value -= 4 }

        case .positional:
            if features.controlsCenter { value += 14 }
            if features.opensFile { value += 10 }
            if features.developsPiece { value += 12 }
            if features.mobilityDelta > 0 { value += 7 }
            if features.isSacrifice { value -= 18 }
            if features.isRetreat { value += 4 }

        case .tactical:
            if features.isCapture { value += 12 }
            if features.createsFork { value += 22 }
            if features.isCheck { value += 14 }
            if features.isPromotion { value += 16 }
            if features.isSacrifice { value += 10 }
            if features.isQuiet { value -= 10 }

        case .balanced:
            value += 4
            if features.isCapture { value += 2 }
            if features.controlsCenter { value += 3 }
        }

        switch quality {
        case .excellent: value += 14
        case .veryGood: value += 9
        case .good: value += 4
        case .interesting: value += 0
        case .inaccuracy: value -= 14
        case .mistake: value -= 26
        case .blunder: value -= 46
        }

        // The objective evaluation always has the last word.
        let loss = Double(EvalScore.loss(from: bestScore, to: score))
        value -= min(35.0, loss / 18.0)

        return max(0, min(100, value))
    }

    static func tags(for features: MoveFeatures, quality: MoveQuality) -> [String] {
        var tags: [String] = []
        if features.isCastle { tags.append("Rochade") }
        if features.isCheck { tags.append("Schach") }
        if features.isPromotion { tags.append("Umwandlung") }
        if features.createsFork { tags.append("Gabel-Chance") }
        if features.isSacrifice { tags.append("Opfer") }
        if features.attacksQueenOrKing && !features.isCheck { tags.append("Druck auf Dame/König") }
        if features.opensFile { tags.append("Offene Linie") }
        if features.controlsCenter { tags.append("Zentrumskontrolle") }
        if features.developsPiece { tags.append("Entwicklung") }
        if features.isRetreat { tags.append("Rückzug") }
        if features.isQuiet && tags.isEmpty { tags.append("Ruhiger Zug") }
        if features.isCapture && tags.isEmpty { tags.append("Schlagzug") }
        if quality.isProblem { tags.append(quality.localizedTitle) }
        return tags
    }

    static func arrowKind(rank: Int, quality: MoveQuality) -> BoardArrow.Kind {
        if quality == .blunder || quality == .mistake { return .critical }
        switch rank {
        case 1: return .best
        case 2: return .alternative
        default: return .interesting
        }
    }
}
