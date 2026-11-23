//
//  ChessComPositionDetector.swift
//  CHESS ENGINE PRO
//
//  Turns a payload read from the rendered Chess.com board into a verified
//  position. The app only reads what the page already displays (piece elements
//  and the visible move list); no private endpoint and no page internals are
//  used.
//
//  Two independent paths are evaluated for every payload:
//
//  1. History replay - the visible SAN move list is replayed with the app's own
//     rules engine. When the resulting placement matches the detected board and
//     every visible move was legal, the position is authoritative: castling
//     rights, en passant square and both move counters are exact.
//  2. Structural - the 64 squares are taken as truth, the side to move comes
//     from the clock indicator and castling rights are derived from king/rook
//     placement. This path is used when the move list is virtualised or does
//     not replay cleanly; it is marked as such in the UI.
//

import Foundation

// MARK: - Payload

/// Raw snapshot posted by the injected Chess.com probe.
struct ChessComPositionPayload: Equatable, Sendable {
    /// Identifies the injected page session; a reload starts a new one.
    var session: String
    /// Monotonic counter from the page. Used to reject out of order updates.
    var sequence: Int
    var url: String
    /// FEN placement field read from the board, ranks 8 to 1.
    var placement: String
    /// "w", "b" or empty when the page shows no turn indicator.
    var sideToMove: String
    /// Visible SAN moves of the current game, oldest first.
    var moves: [String]
    var userColor: String?
    var isGameOver: Bool
    var boardID: String
    var orientation: String
    var capturedAt: Double

    init(session: String = "",
         sequence: Int = 0,
         url: String = "",
         placement: String,
         sideToMove: String = "",
         moves: [String] = [],
         userColor: String? = nil,
         isGameOver: Bool = false,
         boardID: String = "",
         orientation: String = "white",
         capturedAt: Double = 0) {
        self.session = session
        self.sequence = sequence
        self.url = url
        self.placement = placement
        self.sideToMove = sideToMove
        self.moves = moves
        self.userColor = userColor
        self.isGameOver = isGameOver
        self.boardID = boardID
        self.orientation = orientation
        self.capturedAt = capturedAt
    }
}

extension ChessComPositionPayload: Decodable {

    private enum CodingKeys: String, CodingKey {
        case session, sequence, url, placement, sideToMove, moves
        case userColor, isGameOver, boardID, orientation, capturedAt
    }

    /// Every field is optional on the wire so a page update can never crash the
    /// decoder; a payload without placement is ignored by the detector.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        session = (try? container.decode(String.self, forKey: .session)) ?? ""
        sequence = (try? container.decode(Int.self, forKey: .sequence)) ?? 0
        url = (try? container.decode(String.self, forKey: .url)) ?? ""
        placement = (try? container.decode(String.self, forKey: .placement)) ?? ""
        sideToMove = (try? container.decode(String.self, forKey: .sideToMove)) ?? ""
        moves = (try? container.decode([String].self, forKey: .moves)) ?? []
        userColor = try? container.decode(String.self, forKey: .userColor)
        isGameOver = (try? container.decode(Bool.self, forKey: .isGameOver)) ?? false
        boardID = (try? container.decode(String.self, forKey: .boardID)) ?? ""
        orientation = (try? container.decode(String.self, forKey: .orientation)) ?? "white"
        capturedAt = (try? container.decode(Double.self, forKey: .capturedAt)) ?? 0
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

    var fen: String { board.fen }
    var ply: Int { uciMoves.count }
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
                                           validation: PositionValidation.validate(replayed.board))
            }
        }

        var structural: DetectedPosition?
        if let board = structuralBoard(placement: placement,
                                      sideToMove: turn ?? .white,
                                      ply: payload.moves.count) {
            structural = DetectedPosition(board: board,
                                          moveList: payload.moves,
                                          uciMoves: [],
                                          lastMove: nil,
                                          isGameOver: payload.isGameOver,
                                          userColor: user,
                                          boardID: payload.boardID,
                                          origin: .structure,
                                          validation: PositionValidation.validate(board))
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

    static func structuralBoard(placement: String,
                                sideToMove: PieceColor,
                                ply: Int) -> Board? {
        let side = sideToMove == .white ? "w" : "b"
        let fullmove = max(1, ply / 2 + 1)
        guard var board = Board(fen: "\(placement) \(side) - - 0 \(fullmove)") else { return nil }
        board.castling = inferredCastling(for: board)
        return board
    }

    /// Conservative castling detection: a right is kept only while king and
    /// rook still stand on their original squares. Because the board alone
    /// cannot tell whether a rook already moved away and back, this is the
    /// fallback path and is labelled accordingly in the interface.
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
