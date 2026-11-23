//
//  LivePositionSync.swift
//  CHESS ENGINE PRO
//
//  Single, validated path between a chessboard and the engine. Every board
//  change - played locally or detected on the Chess.com page - is turned into a
//  PositionSnapshot after verification (FEN round trip, kings, pawns, checks,
//  en passant consistency). Only a valid snapshot is handed to Stockfish.
//
//  Every accepted position carries a monotonic version, so the interface and
//  the engine can always tell which position they are looking at and can drop
//  late or duplicated updates instead of showing a stale board.
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
        case pieceCount
        case kingsAdjacent

        var localizedDescription: String {
            switch self {
            case .unparsableFEN: return "FEN nicht lesbar"
            case .fenRoundTrip: return "FEN nicht verlustfrei"
            case .kingCount: return "König fehlt oder doppelt"
            case .pawnOnBackRank: return "Bauer auf der Grundreihe"
            case .opponentInCheck: return "Gegner steht im Schach"
            case .enPassantMismatch: return "En-passant-Feld inkonsistent"
            case .pieceCount: return "Unmögliche Figurenzahl"
            case .kingsAdjacent: return "Könige stehen nebeneinander"
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

        // A garbled extraction (wrong square classes, mixed up boards) usually
        // shows up as an impossible material count, so it is checked here as
        // well. Promotions are legal, therefore only pawns are capped at eight.
        for color in PieceColor.allCases {
            let own = board.pieces(for: color)
            if own.count > 16 || own.filter({ $0.piece.kind == .pawn }).count > 8 {
                if !issues.contains(.pieceCount) { issues.append(.pieceCount) }
            }
        }

        if let whiteKing = board.kingSquare(for: .white),
           let blackKing = board.kingSquare(for: .black),
           abs(whiteKing.file - blackKing.file) <= 1,
           abs(whiteKing.rank - blackKing.rank) <= 1 {
            issues.append(.kingsAdjacent)
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

// MARK: - Source and events

enum PositionSource: String, Equatable, Sendable {
    case local
    case chessCom

    var localizedTitle: String {
        switch self {
        case .local: return "App-Brett"
        case .chessCom: return "Chess.com"
        }
    }

    var sfSymbol: String {
        switch self {
        case .local: return "square.grid.3x3"
        case .chessCom: return "safari.fill"
        }
    }
}

/// Everything the pipeline can report for a new position.
enum SyncEventKind: String, Equatable, Sendable {
    case newGame
    case whiteMove
    case blackMove
    case opponentMove
    case gameOver
    case reset
    case positionLoaded
    case edit
    case undo
    case jump

    var localizedTitle: String {
        switch self {
        case .newGame: return "Neue Partie"
        case .whiteMove: return "Weiß am Zug"
        case .blackMove: return "Schwarz am Zug"
        case .opponentMove: return "Gegner hat gezogen"
        case .gameOver: return "Partie beendet"
        case .reset: return "Zurückgesetzt"
        case .positionLoaded: return "Stellung geladen"
        case .edit: return "Stellung bearbeitet"
        case .undo: return "Zug zurückgenommen"
        case .jump: return "Position angesprungen"
        }
    }

}

struct PositionEvent: Equatable, Sendable, Identifiable {
    var version: Int
    var kind: SyncEventKind
    var ply: Int
    var sideToMove: PieceColor
    var san: String?
    var source: PositionSource

    var id: Int { version }

    var summary: String {
        let turn = "\(sideToMove.localizedName) am Zug"
        if let san = san, !san.isEmpty {
            return "\(kind.localizedTitle) · \(san) · \(turn)"
        }
        return "\(kind.localizedTitle) · \(turn)"
    }
}

struct SyncStatistics: Equatable, Sendable {
    var received = 0
    var accepted = 0
    var duplicates = 0
    var stale = 0
    var rejected = 0

    var summary: String {
        "\(accepted) übernommen · \(duplicates) doppelt · \(stale) veraltet · \(rejected) verworfen"
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
        case detected

        var localizedTitle: String {
            switch self {
            case .move: return "Zug ausgeführt"
            case .undo: return "Zug zurückgenommen"
            case .reset: return "Neu gestartet"
            case .edit: return "Stellung bearbeitet"
            case .imported: return "Partie geladen"
            case .jump: return "Position angesprungen"
            case .detected: return "Auf Chess.com erkannt"
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
    var version: Int
    var source: PositionSource
    var eventKind: SyncEventKind
    /// Which FEN fields are verified rather than inferred.
    var confidence: FenConfidence = .exact

    var id: String { fen + "#" + String(version) }
}

// MARK: - Synchroniser

/// Collects validated positions, de-duplicates unchanged ones, rejects stale
/// updates and exposes the counters used by the interface and the tests.
final class LivePositionSync {

    private(set) var snapshot: PositionSnapshot?
    private(set) var validation = PositionValidation.valid
    private(set) var changeCount = 0
    private(set) var rejectedCount = 0
    private(set) var receivedCount = 0
    private(set) var version = 0
    private(set) var stats = SyncStatistics()
    private(set) var events: [PositionEvent] = []

    /// Publishes a new position. Returns `true` when the snapshot changed.
    @discardableResult
    func publish(board: Board,
                 lastMove: Move?,
                 sanHistory: [String],
                 reason: PositionSnapshot.ChangeReason,
                 before: Board? = nil,
                 move: Move? = nil,
                 source: PositionSource = .local,
                 externalVersion: Int? = nil,
                 explicitEvent: SyncEventKind? = nil,
                 userColor: PieceColor? = nil,
                 gameOverOverride: Bool? = nil,
                 confidence: FenConfidence = .exact) -> Bool {
        receivedCount += 1
        stats.received += 1

        // A late update from the page must never overwrite a newer position.
        if let externalVersion = externalVersion, externalVersion <= version {
            stats.stale += 1
            return false
        }

        let result = PositionValidation.validate(board)
        validation = result
        guard result.isValid else {
            rejectedCount += 1
            stats.rejected += 1
            return false
        }

        let ply = sanHistory.count
        if explicitEvent == nil,
           let current = snapshot,
           current.fen == board.fen,
           current.ply == ply {
            stats.duplicates += 1
            return false
        }

        var kind: MoveKind?
        if let before = before, let move = move {
            kind = LivePositionSync.moveKind(before: before, move: move, after: board)
        }

        let status = board.status
        let isOver = gameOverOverride ?? status.isFinished
        let event = LivePositionSync.eventKind(previous: snapshot,
                                               board: board,
                                               ply: ply,
                                               reason: reason,
                                               userColor: userColor,
                                               explicit: explicitEvent)

        // Versions come from the page when it provides one, otherwise from the
        // synchroniser itself. Both are strictly monotonic.
        version = max(version + 1, externalVersion ?? 0)
        snapshot = PositionSnapshot(fen: board.fen,
                                    sideToMove: board.sideToMove,
                                    lastMove: lastMove,
                                    lastSAN: sanHistory.last,
                                    moveKind: kind,
                                    ply: ply,
                                    sanHistory: sanHistory,
                                    isGameOver: isOver,
                                    statusText: isOver && !status.isFinished
                                        ? "Partie beendet"
                                        : LivePositionSync.statusText(status: status,
                                                                      sideToMove: board.sideToMove),
                                    reason: reason,
                                    version: version,
                                    source: source,
                                    eventKind: event,
                                    confidence: confidence)
        changeCount += 1
        stats.accepted += 1
        events.append(PositionEvent(version: version,
                                    kind: event,
                                    ply: ply,
                                    sideToMove: board.sideToMove,
                                    san: sanHistory.last,
                                    source: source))
        if events.count > 32 { events.removeFirst(events.count - 32) }
        return true
    }

    // MARK: - Classification

    static func eventKind(previous: PositionSnapshot?,
                          board: Board,
                          ply: Int,
                          reason: PositionSnapshot.ChangeReason,
                          userColor: PieceColor?,
                          explicit: SyncEventKind?) -> SyncEventKind {
        if let explicit = explicit { return explicit }

        switch reason {
        case .reset: return .reset
        case .undo: return .undo
        case .jump: return .jump
        case .edit: return .edit
        case .imported: return .positionLoaded
        case .detected, .move: break
        }

        if let previous = previous, ply == 0, previous.ply > 0 { return .newGame }
        if previous == nil, ply == 0 { return .newGame }
        if let previous = previous, ply < previous.ply { return .positionLoaded }
        if board.isGameOver { return .gameOver }

        let mover = board.sideToMove.opponent
        if let user = userColor, mover != user { return .opponentMove }
        return mover == .white ? .whiteMove : .blackMove
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
