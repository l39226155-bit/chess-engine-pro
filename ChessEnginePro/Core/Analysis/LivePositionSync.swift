//
//  LivePositionSync.swift
//  CHESS ENGINE PRO
//
//  Single, validated path between the chessboard and the engine. Every board
//  change in a supported analysis environment is turned into a PositionSnapshot
//  after the position has been verified (FEN round trip, kings, pawns, checks,
//  en passant consistency). Only a valid snapshot is handed to Stockfish.
//

import Foundation

// MARK: - Move classification

enum MoveKind: Equatable, Sendable {
    case normal
    case capture
    case castleKingSide
    case castleQueenSide
    case enPassant
    case promotion(PieceKind)
    case doublePawnPush

    var localizedTitle: String {
        switch self {
        case .normal: return "Zug"
        case .capture: return "Schlagen"
        case .castleKingSide: return "Kleine Rochade"
        case .castleQueenSide: return "Große Rochade"
        case .enPassant: return "En passant"
        case .promotion(let kind): return "Umwandlung \(kind.localizedName)"
        case .doublePawnPush: return "Doppelter Bauernzug"
        }
    }
}

// MARK: - Validation

struct PositionValidation: Equatable, Sendable {

    enum Issue: String, Equatable, Sendable {
        case unparsableFEN
        case fenRoundTrip
        case kingCount
        case pawnOnBackRank
        case opponentInCheck
        case enPassantMismatch

        var localizedDescription: String {
            switch self {
            case .unparsableFEN: return "FEN nicht lesbar"
            case .fenRoundTrip: return "FEN nicht verlustfrei"
            case .kingCount: return "König fehlt oder doppelt"
            case .pawnOnBackRank: return "Bauer auf der Grundreihe"
            case .opponentInCheck: return "Gegner steht im Schach"
            case .enPassantMismatch: return "En-passant-Feld inkonsistent"
            }
        }
    }

    var issues: [Issue] = []

    var isValid: Bool { issues.isEmpty }

    var summary: String {
        if issues.isEmpty { return "FEN gültig" }
        return issues.map { $0.localizedDescription }.joined(separator: ", ")
    }

    static let valid = PositionValidation()

    /// Full structural validation of a position before it is sent to an engine.
    static func validate(_ board: Board) -> PositionValidation {
        guard let reparsed = Board(fen: board.fen) else {
            return PositionValidation(issues: [.unparsableFEN])
        }

        var issues: [Issue] = []
        if reparsed.fen != board.fen { issues.append(.fenRoundTrip) }

        let whiteKings = board.pieces(for: .white).filter { $0.piece.kind == .king }.count
        let blackKings = board.pieces(for: .black).filter { $0.piece.kind == .king }.count
        if whiteKings != 1 || blackKings != 1 { issues.append(.kingCount) }

        if board.allPieces.contains(where: { $0.piece.kind == .pawn && ($0.square.rank == 0 || $0.square.rank == 7) }) {
            issues.append(.pawnOnBackRank)
        }

        // The side that just moved may not be in check.
        if board.isInCheck(board.sideToMove.opponent) { issues.append(.opponentInCheck) }

        if let target = board.enPassant {
            let enemy = board.sideToMove.opponent
            let pawnRank = enemy == .white ? target.rank + 1 : target.rank - 1
            let pawn = board[Square(file: target.file, rank: pawnRank)]
            let targetEmpty = board[target] == nil
            if !targetEmpty || pawn?.kind != .pawn || pawn?.color != enemy {
                issues.append(.enPassantMismatch)
            }
        }

        return PositionValidation(issues: issues)
    }
}

// MARK: - Snapshot

struct PositionSnapshot: Equatable, Identifiable, Sendable {

    enum ChangeReason: String, Equatable, Sendable {
        case move
        case undo
        case reset
        case edit
        case imported
        case jump

        var localizedTitle: String {
            switch self {
            case .move: return "Zug ausgeführt"
            case .undo: return "Zug zurückgenommen"
            case .reset: return "Neu gestartet"
            case .edit: return "Stellung bearbeitet"
            case .imported: return "Partie geladen"
            case .jump: return "Position angesprungen"
            }
        }
    }

    var fen: String
    var sideToMove: PieceColor
    var lastMove: Move?
    var lastSAN: String?
    var moveKind: MoveKind?
    var ply: Int
    var sanHistory: [String]
    var isGameOver: Bool
    var statusText: String
    var reason: ChangeReason

    var id: String { fen }
}

// MARK: - Synchroniser

/// Collects validated positions, de-duplicates unchanged ones and exposes
/// counters used by the UI and the tests.
final class LivePositionSync {

    private(set) var snapshot: PositionSnapshot?
    private(set) var validation = PositionValidation.valid
    private(set) var changeCount = 0
    private(set) var rejectedCount = 0
    private(set) var receivedCount = 0

    /// Publishes a new position. Returns `true` when the snapshot changed.
    @discardableResult
    func publish(board: Board,
                 lastMove: Move?,
                 sanHistory: [String],
                 reason: PositionSnapshot.ChangeReason,
                 before: Board? = nil,
                 move: Move? = nil) -> Bool {
        receivedCount += 1

        let result = PositionValidation.validate(board)
        validation = result
        guard result.isValid else {
            rejectedCount += 1
            return false
        }

        if let current = snapshot,
           current.fen == board.fen,
           current.sanHistory.count == sanHistory.count {
            return false
        }

        var kind: MoveKind?
        if let before = before, let move = move {
            kind = LivePositionSync.moveKind(before: before, move: move, after: board)
        }

        let status = board.status
        snapshot = PositionSnapshot(fen: board.fen,
                                    sideToMove: board.sideToMove,
                                    lastMove: lastMove,
                                    lastSAN: sanHistory.last,
                                    moveKind: kind,
                                    ply: sanHistory.count,
                                    sanHistory: sanHistory,
                                    isGameOver: status.isFinished,
                                    statusText: LivePositionSync.statusText(status: status,
                                                                            sideToMove: board.sideToMove),
                                    reason: reason)
        changeCount += 1
        return true
    }

    /// Classifies a played move, including castling, en passant and promotion.
    static func moveKind(before: Board, move: Move, after: Board) -> MoveKind {
        if let promotion = move.promotion {
            return .promotion(promotion)
        }

        if let piece = before[move.from], piece.kind == .king,
           abs(move.to.file - move.from.file) == 2 {
            return move.to.file > move.from.file ? .castleKingSide : .castleQueenSide
        }

        if let piece = before[move.from], piece.kind == .pawn {
            if move.from.file != move.to.file, before[move.to] == nil {
                return .enPassant
            }
            if abs(move.to.rank - move.from.rank) == 2 {
                return .doublePawnPush
            }
        }

        if before[move.to] != nil { return .capture }
        return .normal
    }

    static func statusText(status: GameStatus, sideToMove: PieceColor) -> String {
        switch status {
        case .checkmate(let winner):
            return "Schachmatt – \(winner.localizedName) gewinnt"
        case .stalemate:
            return "Patt – Remis"
        case .drawInsufficientMaterial:
            return "Remis – unzureichendes Material"
        case .drawFiftyMove:
            return "Remis – 50-Züge-Regel"
        case .check:
            return "\(sideToMove.localizedName) am Zug – Schach"
        case .active:
            return "\(sideToMove.localizedName) am Zug"
        }
    }
}
