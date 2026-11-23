//
//  ChessComPositionDetector.swift
//  CHESS ENGINE PRO
//
//  Turns a payload read from the rendered Chess.com board into a position. The
//  app only reads what the page already displays (piece elements and the
//  visible move list); no private endpoint and no page internals are used.
//
//  Two independent paths are evaluated for every payload:
//
//  1. History replay - the visible SAN move list is replayed with the app's own
//     rules engine. When the resulting placement matches the detected board and
//     every visible move was legal, the position is authoritative: castling
//     rights, en passant square, halfmove clock and move number are exact.
//  2. Structural - the 64 squares are taken as truth, the side to move comes
//     from the clock indicator and castling rights are derived from king/rook
//     placement. Castling, en passant, both counters and the ply count are
//     marked as inferred, never as verified.
//

import Foundation

// MARK: - Payload

/// Raw snapshot posted by the injected Chess.com probe.
struct ChessComPositionPayload: Equatable, Sendable {
    /// Identifies the injected page session; a reload starts a new one.
    var session: String
    /// Monotonic counter from the page. Used to reject out of order updates.
    var sequence: Int
    /// FEN placement field read from the board, ranks 8 to 1.
    var placement: String
    /// "w", "b" or empty when the page shows no turn indicator.
    var sideToMove: String
    /// Visible SAN moves of the current game, oldest first.
    var moves: [String]
    var userColor: String?
    var isGameOver: Bool
    var boardID: String

    init(session: String = "",
         sequence: Int = 0,
         placement: String,
         sideToMove: String = "",
         moves: [String] = [],
         userColor: String? = nil,
         isGameOver: Bool = false,
         boardID: String = "") {
        self.session = session
        self.sequence = sequence
        self.placement = placement
        self.sideToMove = sideToMove
        self.moves = moves
        self.userColor = userColor
        self.isGameOver = isGameOver
        self.boardID = boardID
    }
}

extension ChessComPositionPayload: Decodable {

    private enum CodingKeys: String, CodingKey {
        case session, sequence, placement, sideToMove, moves
        case userColor, isGameOver, boardID
    }

    /// Every field is optional on the wire so a page update can never crash the
    /// decoder; a payload without placement is ignored by the detector.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        session = (try? container.decode(String.self, forKey: .session)) ?? ""
        sequence = (try? container.decode(Int.self, forKey: .sequence)) ?? 0
        placement = (try? container.decode(String.self, forKey: .placement)) ?? ""
        sideToMove = (try? container.decode(String.self, forKey: .sideToMove)) ?? ""
        moves = (try? container.decode([String].self, forKey: .moves)) ?? []
        userColor = try? container.decode(String.self, forKey: .userColor)
        isGameOver = (try? container.decode(Bool.self, forKey: .isGameOver)) ?? false
        boardID = (try? container.decode(String.self, forKey: .boardID)) ?? ""
    }
}

// MARK: - Detection result

enum DetectionOrigin: String, Equatable, Sendable {
    case history
    case structure

    var localizedTitle: String {
        switch self {
        case .history: return "Zugliste verifiziert"
        case .structure: return "Brett erkannt"
        }
    }
}

/// Which parts of the produced FEN are verified and which are only inferred.
/// The interface must show this honestly: an inferred field is a best guess,
/// never a fact.
struct FenConfidence: Equatable, Sendable {
    var sideToMove: Bool
    var castling: Bool
    var enPassant: Bool
    var halfmove: Bool
    var ply: Bool

    static let exact = FenConfidence(sideToMove: true,
                                     castling: true,
                                     enPassant: true,
                                     halfmove: true,
                                     ply: true)
    static let inferred = FenConfidence(sideToMove: false,
                                        castling: false,
                                        enPassant: false,
                                        halfmove: false,
                                        ply: false)

    var isExact: Bool { sideToMove && castling && enPassant && halfmove && ply }

    var estimatedFields: [String] {
        var fields: [String] = []
        if !sideToMove { fields.append("Zugrecht") }
        if !castling { fields.append("Rochaderechte") }
        if !enPassant { fields.append("En-passant-Feld") }
        if !halfmove { fields.append("Halbzugzähler") }
        if !ply { fields.append("Zugnummer") }
        return fields
    }

    var note: String {
        if isExact { return "FEN vollständig verifiziert" }
        return "Geschätzt: " + estimatedFields.joined(separator: ", ")
    }
}

struct DetectedPosition: Equatable, Sendable {
    var board: Board
    var moveList: [String]
    var uciMoves: [String]
    var lastMove: Move?
    var isGameOver: Bool
    var userColor: PieceColor?
    var boardID: String
    var origin: DetectionOrigin
    var validation: PositionValidation
    var confidence: FenConfidence
}

// MARK: - Detector

enum ChessComPositionDetector {

    /// Reads a payload and returns the best verified position, or `nil` when the
    /// page does not expose a board at all.
    static func detect(_ payload: ChessComPositionPayload) -> DetectedPosition? {
        let placement = payload.placement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !placement.isEmpty, placement.split(separator: "/").count == 8 else { return nil }

        let turn = color(from: payload.sideToMove)
        let user = color(from: payload.userColor)

        var history: DetectedPosition?
        if !payload.moves.isEmpty {
            let replayed = replay(payload.moves)
            if replayed.uciMoves.count == payload.moves.count,
               !replayed.uciMoves.isEmpty,
               placementString(replayed.board) == placement {
                history = DetectedPosition(board: replayed.board,
                                           moveList: payload.moves,
                                           uciMoves: replayed.uciMoves,
                                           lastMove: replayed.lastMove,
                                           isGameOver: payload.isGameOver,
                                           userColor: user,
                                           boardID: payload.boardID,
                                           origin: .history,
                                           validation: PositionValidation.validate(replayed.board),
                                           confidence: .exact)
            }
        }

        var structural: DetectedPosition?
        if let board = structuralBoard(placement: placement,
                                      sideToMove: turn ?? .white) {
            structural = DetectedPosition(board: board,
                                          moveList: payload.moves,
                                          uciMoves: [],
                                          lastMove: nil,
                                          isGameOver: payload.isGameOver,
                                          userColor: user,
                                          boardID: payload.boardID,
                                          origin: .structure,
                                          validation: PositionValidation.validate(board),
                                          confidence: FenConfidence(sideToMove: turn != nil,
                                                                    castling: false,
                                                                    enPassant: false,
                                                                    halfmove: false,
                                                                    ply: false))
        }

        if let history = history, history.validation.isValid { return history }
        if let structural = structural, structural.validation.isValid { return structural }
        // An invalid result is still returned so the UI can explain the refusal
        // instead of silently showing a stale position.
        return history ?? structural
    }

    // MARK: - History replay

    /// Replays the visible SAN list with the app's own move generator.
    static func replay(_ moves: [String]) -> (board: Board, uciMoves: [String], lastMove: Move?) {
        var board = Board()
        var uciMoves: [String] = []
        var lastMove: Move?
        for san in moves {
            guard let move = board.move(matchingSan: san) else { break }
            uciMoves.append(move.uci)
            board.apply(move)
            lastMove = move
        }
        return (board, uciMoves, lastMove)
    }

    // MARK: - Structural fallback

    /// The board alone cannot prove castling rights, en passant, the halfmove
    /// clock or the move number. This builder therefore uses neutral counters
    /// and marks every one of those fields as inferred.
    static func structuralBoard(placement: String,
                                sideToMove: PieceColor) -> Board? {
        let side = sideToMove == .white ? "w" : "b"
        guard var board = Board(fen: "\(placement) \(side) - - 0 1") else { return nil }
        board.castling = inferredCastling(for: board)
        return board
    }

    /// Conservative castling detection: a right is kept only while king and
    /// rook still stand on their original squares. Because the board alone
    /// cannot tell whether a rook already moved away and back, the result is
    /// reported as inferred.
    static func inferredCastling(for board: Board) -> CastlingRights {
        var rights = CastlingRights.none

        func standing(_ color: PieceColor, _ kind: PieceKind, at name: String) -> Bool {
            guard let square = Square(name: name), let piece = board[square] else { return false }
            return piece.color == color && piece.kind == kind
        }

        if standing(.white, .king, at: "e1") {
            rights.whiteKingSide = standing(.white, .rook, at: "h1")
            rights.whiteQueenSide = standing(.white, .rook, at: "a1")
        }
        if standing(.black, .king, at: "e8") {
            rights.blackKingSide = standing(.black, .rook, at: "h8")
            rights.blackQueenSide = standing(.black, .rook, at: "a8")
        }
        return rights
    }

    // MARK: - Helpers

    static func placementString(_ board: Board) -> String {
        guard let field = board.fen.split(separator: " ").first else { return "" }
        return String(field)
    }

    static func color(from raw: String?) -> PieceColor? {
        switch (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "w", "white": return .white
        case "b", "black": return .black
        default: return nil
        }
    }
}
