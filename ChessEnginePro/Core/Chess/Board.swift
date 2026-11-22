//
//  Board.swift
//  CHESS ENGINE PRO
//
//  Complete chess rules implementation: FEN, legal move generation,
//  castling, en passant, promotion and position status.
//

import Foundation

struct Board: Hashable, Codable, Sendable {
    static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    static let emptyFEN = "8/8/8/8/8/8/8/8 w - - 0 1"

    /// 64 squares, a1 first.
    var squares: [Piece?]
    var sideToMove: PieceColor
    var castling: CastlingRights
    var enPassant: Square?
    var halfmoveClock: Int
    var fullmoveNumber: Int

    init(squares: [Piece?],
         sideToMove: PieceColor = .white,
         castling: CastlingRights = .none,
         enPassant: Square? = nil,
         halfmoveClock: Int = 0,
         fullmoveNumber: Int = 1) {
        var normalised = squares
        if normalised.count < 64 {
            normalised.append(contentsOf: Array(repeating: nil, count: 64 - normalised.count))
        } else if normalised.count > 64 {
            normalised = Array(normalised.prefix(64))
        }
        self.squares = normalised
        self.sideToMove = sideToMove
        self.castling = castling
        self.enPassant = enPassant
        self.halfmoveClock = halfmoveClock
        self.fullmoveNumber = fullmoveNumber
    }

    init() {
        self = Board(fen: Board.startFEN) ?? Board.empty
    }

    static var empty: Board {
        Board(squares: Array(repeating: nil, count: 64))
    }

    // MARK: - FEN

    init?(fen rawFEN: String) {
        let fen = rawFEN.trimmingCharacters(in: .whitespacesAndNewlines)
        let fields = fen.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let placement = fields.first else { return nil }

        var squares: [Piece?] = Array(repeating: nil, count: 64)
        let ranks = placement.split(separator: "/", omittingEmptySubsequences: false)
        guard ranks.count == 8 else { return nil }

        for (rankOffset, rankText) in ranks.enumerated() {
            let rank = 7 - rankOffset
            var file = 0
            for character in rankText {
                if let digit = character.wholeNumberValue, digit > 0, digit <= 8 {
                    file += digit
                } else if let piece = Piece(fenLetter: character) {
                    guard file < 8 else { return nil }
                    squares[rank * 8 + file] = piece
                    file += 1
                } else {
                    return nil
                }
            }
            guard file == 8 else { return nil }
        }

        let sideToMove = fields.count > 1 && fields[1].lowercased() == "b" ? PieceColor.black : .white
        let castling = fields.count > 2 ? CastlingRights(fen: fields[2]) : .none
        var enPassant: Square?
        if fields.count > 3, fields[3] != "-" {
            enPassant = Square(name: fields[3])
        }
        let halfmove = fields.count > 4 ? Int(fields[4]) ?? 0 : 0
        let fullmove = fields.count > 5 ? Int(fields[5]) ?? 1 : 1

        self.init(squares: squares,
                  sideToMove: sideToMove,
                  castling: castling,
                  enPassant: enPassant,
                  halfmoveClock: halfmove,
                  fullmoveNumber: max(1, fullmove))
    }

    var fen: String {
        var placement = ""
        for rank in stride(from: 7, through: 0, by: -1) {
            var empty = 0
            for file in 0..<8 {
                if let piece = squares[rank * 8 + file] {
                    if empty > 0 {
                        placement += String(empty)
                        empty = 0
                    }
                    placement.append(piece.fenLetter)
                } else {
                    empty += 1
                }
            }
            if empty > 0 { placement += String(empty) }
            if rank > 0 { placement += "/" }
        }

        let side = sideToMove == .white ? "w" : "b"
        let ep = enPassant?.name ?? "-"
        return "\(placement) \(side) \(castling.fen) \(ep) \(halfmoveClock) \(fullmoveNumber)"
    }

    // MARK: - Access

    subscript(square: Square) -> Piece? {
        get { squares[square.index] }
        set { squares[square.index] = newValue }
    }

    func piece(at square: Square) -> Piece? { squares[square.index] }

    func kingSquare(for color: PieceColor) -> Square? {
        for index in 0..<64 {
            if let piece = squares[index], piece.kind == .king, piece.color == color {
                return Square(index: index)
            }
        }
        return nil
    }

    var allPieces: [(square: Square, piece: Piece)] {
        var result: [(square: Square, piece: Piece)] = []
        for index in 0..<64 {
            if let piece = squares[index] {
                result.append((square: Square(index: index), piece: piece))
            }
        }
        return result
    }

    func pieces(for color: PieceColor) -> [(square: Square, piece: Piece)] {
        allPieces.filter { $0.piece.color == color }
    }

    // MARK: - Attack detection

    private static let knightOffsets: [(Int, Int)] = [
        (1, 2), (2, 1), (2, -1), (1, -2),
        (-1, -2), (-2, -1), (-2, 1), (-1, 2)
    ]

    private static let kingOffsets: [(Int, Int)] = [
        (1, 0), (1, 1), (0, 1), (-1, 1),
        (-1, 0), (-1, -1), (0, -1), (1, -1)
    ]

    private static let bishopDirections: [(Int, Int)] = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
    private static let rookDirections: [(Int, Int)] = [(1, 0), (-1, 0), (0, 1), (0, -1)]

    /// True when `color` attacks `square` (pawn pushes excluded, captures only).
    func isAttacked(_ square: Square, by color: PieceColor) -> Bool {
        // Pawns
        let pawnRank = square.rank + (color == .white ? -1 : 1)
        for df in [-1, 1] {
            let f = square.file + df
            guard (0..<8).contains(f), (0..<8).contains(pawnRank) else { continue }
            if let piece = squares[pawnRank * 8 + f], piece.kind == .pawn, piece.color == color {
                return true
            }
        }

        // Knights
        for (df, dr) in Board.knightOffsets {
            let f = square.file + df
            let r = square.rank + dr
            guard (0..<8).contains(f), (0..<8).contains(r) else { continue }
            if let piece = squares[r * 8 + f], piece.kind == .knight, piece.color == color {
                return true
            }
        }

        // King
        for (df, dr) in Board.kingOffsets {
            let f = square.file + df
            let r = square.rank + dr
            guard (0..<8).contains(f), (0..<8).contains(r) else { continue }
            if let piece = squares[r * 8 + f], piece.kind == .king, piece.color == color {
                return true
            }
        }

        // Sliding pieces
        for (df, dr) in Board.bishopDirections {
            var f = square.file + df
            var r = square.rank + dr
            while (0..<8).contains(f), (0..<8).contains(r) {
                if let piece = squares[r * 8 + f] {
                    if piece.color == color, piece.kind == .bishop || piece.kind == .queen {
                        return true
                    }
                    break
                }
                f += df
                r += dr
            }
        }

        for (df, dr) in Board.rookDirections {
            var f = square.file + df
            var r = square.rank + dr
            while (0..<8).contains(f), (0..<8).contains(r) {
                if let piece = squares[r * 8 + f] {
                    if piece.color == color, piece.kind == .rook || piece.kind == .queen {
                        return true
                    }
                    break
                }
                f += df
                r += dr
            }
        }

        return false
    }

    func isInCheck(_ color: PieceColor) -> Bool {
        guard let king = kingSquare(for: color) else { return false }
        return isAttacked(king, by: color.opponent)
    }

    var isCheck: Bool { isInCheck(sideToMove) }

    // MARK: - Pseudo legal moves

    private func promotionMoves(from: Square, to: Square) -> [Move] {
        PieceKind.promotionChoices.map { Move(from: from, to: to, promotion: $0) }
    }

    func pseudoLegalMoves(from square: Square) -> [Move] {
        guard let piece = squares[square.index] else { return [] }
        let me = piece.color
        var moves: [Move] = []

        func isEnemy(_ target: Square) -> Bool {
            guard let other = squares[target.index] else { return false }
            return other.color != me
        }

        switch piece.kind {
        case .pawn:
            let direction = me == .white ? 1 : -1
            let startRank = me == .white ? 1 : 6
            let promotionRank = me == .white ? 7 : 0

            if let one = square.offset(file: 0, rank: direction), squares[one.index] == nil {
                if one.rank == promotionRank {
                    moves.append(contentsOf: promotionMoves(from: square, to: one))
                } else {
                    moves.append(Move(from: square, to: one))
                    if square.rank == startRank,
                       let two = square.offset(file: 0, rank: direction * 2),
                       squares[two.index] == nil {
                        moves.append(Move(from: square, to: two))
                    }
                }
            }

            for df in [-1, 1] {
                guard let target = square.offset(file: df, rank: direction) else { continue }
                if isEnemy(target) {
                    if target.rank == promotionRank {
                        moves.append(contentsOf: promotionMoves(from: square, to: target))
                    } else {
                        moves.append(Move(from: square, to: target))
                    }
                } else if enPassant == target {
                    moves.append(Move(from: square, to: target))
                }
            }

        case .knight:
            for (df, dr) in Board.knightOffsets {
                guard let target = square.offset(file: df, rank: dr) else { continue }
                if squares[target.index] == nil || isEnemy(target) {
                    moves.append(Move(from: square, to: target))
                }
            }

        case .king:
            for (df, dr) in Board.kingOffsets {
                guard let target = square.offset(file: df, rank: dr) else { continue }
                if squares[target.index] == nil || isEnemy(target) {
                    moves.append(Move(from: square, to: target))
                }
            }

            let homeRank = me == .white ? 0 : 7
            let kingHome = Square(file: 4, rank: homeRank)
            if square == kingHome, !isAttacked(square, by: me.opponent) {
                let kingSide = me == .white ? castling.whiteKingSide : castling.blackKingSide
                if kingSide {
                    let f1 = Square(file: 5, rank: homeRank)
                    let g1 = Square(file: 6, rank: homeRank)
                    if squares[f1.index] == nil, squares[g1.index] == nil,
                       !isAttacked(f1, by: me.opponent), !isAttacked(g1, by: me.opponent) {
                        moves.append(Move(from: square, to: g1))
                    }
                }
                let queenSide = me == .white ? castling.whiteQueenSide : castling.blackQueenSide
                if queenSide {
                    let b1 = Square(file: 1, rank: homeRank)
                    let c1 = Square(file: 2, rank: homeRank)
                    let d1 = Square(file: 3, rank: homeRank)
                    if squares[b1.index] == nil, squares[c1.index] == nil, squares[d1.index] == nil,
                       !isAttacked(d1, by: me.opponent), !isAttacked(c1, by: me.opponent) {
                        moves.append(Move(from: square, to: c1))
                    }
                }
            }

        case .bishop, .rook, .queen:
            var directions: [(Int, Int)] = []
            switch piece.kind {
            case .bishop: directions = Board.bishopDirections
            case .rook: directions = Board.rookDirections
            default: directions = Board.bishopDirections + Board.rookDirections
            }
            for (df, dr) in directions {
                var current = square
                while let next = current.offset(file: df, rank: dr) {
                    if let occupant = squares[next.index] {
                        if occupant.color != me {
                            moves.append(Move(from: square, to: next))
                        }
                        break
                    }
                    moves.append(Move(from: square, to: next))
                    current = next
                }
            }
        }

        return moves
    }

    var pseudoLegalMoves: [Move] {
        var result: [Move] = []
        for index in 0..<64 {
            guard let piece = squares[index], piece.color == sideToMove else { continue }
            result.append(contentsOf: pseudoLegalMoves(from: Square(index: index)))
        }
        return result
    }

    // MARK: - Legal moves

    func legalMoves(from square: Square) -> [Move] {
        guard let piece = squares[square.index], piece.color == sideToMove else { return [] }
        return pseudoLegalMoves(from: square).filter { move in
            let next = applying(move)
            guard let king = next.kingSquare(for: piece.color) else { return false }
            return !next.isAttacked(king, by: piece.color.opponent)
        }
    }

    var legalMoves: [Move] {
        var result: [Move] = []
        for index in 0..<64 {
            guard let piece = squares[index], piece.color == sideToMove else { continue }
            result.append(contentsOf: legalMoves(from: Square(index: index)))
        }
        return result
    }

    func isLegal(_ move: Move) -> Bool {
        legalMoves(from: move.from).contains { $0 == move }
    }

    /// All moves that reach `to` - used by the UI for tap-to-move.
    func legalMoves(to target: Square, from origin: Square? = nil) -> [Move] {
        if let origin = origin {
            return legalMoves(from: origin).filter { $0.to == target }
        }
        return legalMoves.filter { $0.to == target }
    }

    // MARK: - Making moves

    /// Returns a new board with the move played. The move is assumed legal.
    func applying(_ move: Move) -> Board {
        var copy = self
        copy.apply(move)
        return copy
    }

    mutating func apply(_ move: Move) {
        guard let moving = squares[move.from.index] else { return }
        let me = moving.color
        let isPawn = moving.kind == .pawn
        let isKing = moving.kind == .king

        var captured = squares[move.to.index] != nil

        // En passant capture removes the pawn behind the target square.
        if isPawn, move.from.file != move.to.file, squares[move.to.index] == nil,
           enPassant == move.to {
            let capturedSquare = Square(file: move.to.file, rank: move.from.rank)
            if squares[capturedSquare.index] != nil {
                squares[capturedSquare.index] = nil
                captured = true
            }
        }

        // Castling moves the rook as well.
        if isKing, abs(move.to.file - move.from.file) == 2 {
            let rank = move.from.rank
            if move.to.file == 6 {
                let rookFrom = Square(file: 7, rank: rank)
                let rookTo = Square(file: 5, rank: rank)
                squares[rookTo.index] = squares[rookFrom.index]
                squares[rookFrom.index] = nil
            } else if move.to.file == 2 {
                let rookFrom = Square(file: 0, rank: rank)
                let rookTo = Square(file: 3, rank: rank)
                squares[rookTo.index] = squares[rookFrom.index]
                squares[rookFrom.index] = nil
            }
        }

        squares[move.to.index] = move.promotion.map { Piece(color: me, kind: $0) } ?? moving
        squares[move.from.index] = nil

        // En passant target square after a double pawn push.
        if isPawn, abs(move.to.rank - move.from.rank) == 2 {
            enPassant = Square(file: move.from.file, rank: (move.from.rank + move.to.rank) / 2)
        } else {
            enPassant = nil
        }

        // Castling rights
        if isKing {
            if me == .white {
                castling.whiteKingSide = false
                castling.whiteQueenSide = false
            } else {
                castling.blackKingSide = false
                castling.blackQueenSide = false
            }
        } else if moving.kind == .rook {
            switch move.from.name {
            case "h1": castling.whiteKingSide = false
            case "a1": castling.whiteQueenSide = false
            case "h8": castling.blackKingSide = false
            case "a8": castling.blackQueenSide = false
            default: break
            }
        }

        // A rook captured on its home square removes the right as well.
        switch move.to.name {
        case "h1": castling.whiteKingSide = false
        case "a1": castling.whiteQueenSide = false
        case "h8": castling.blackKingSide = false
        case "a8": castling.blackQueenSide = false
        default: break
        }

        halfmoveClock = (isPawn || captured) ? 0 : halfmoveClock + 1
        if sideToMove == .black { fullmoveNumber += 1 }
        sideToMove = sideToMove.opponent
    }

    /// Applies a list of moves; returns nil when one of them is illegal.
    func applying(_ moves: [Move]) -> Board? {
        var board = self
        for move in moves {
            guard board.isLegal(move) else { return nil }
            board.apply(move)
        }
        return board
    }

    // MARK: - Status

    var status: GameStatus {
        let inCheck = isInCheck(sideToMove)
        let moves = legalMoves
        if moves.isEmpty {
            return inCheck ? .checkmate(winner: sideToMove.opponent) : .stalemate
        }
        if isInsufficientMaterial { return .drawInsufficientMaterial }
        if halfmoveClock >= 100 { return .drawFiftyMove }
        return inCheck ? .check : .active
    }

    var isGameOver: Bool { status.isFinished }

    var isInsufficientMaterial: Bool {
        var knights = 0
        var bishops = 0
        var bishopSquareColors: Set<Bool> = []
        for index in 0..<64 {
            guard let piece = squares[index] else { continue }
            switch piece.kind {
            case .king: continue
            case .knight: knights += 1
            case .bishop:
                bishops += 1
                bishopSquareColors.insert(Square(index: index).isLightSquare)
            default:
                return false
            }
        }
        if knights == 0 && bishops == 0 { return true }
        if knights == 1 && bishops == 0 { return true }
        if knights == 0 && bishops == 1 { return true }
        if knights == 0 && bishops == 2 && bishopSquareColors.count == 1 { return true }
        return false
    }

    // MARK: - Material

    /// Material balance in centipawns, from white's point of view.
    var materialBalance: Int {
        var balance = 0
        for piece in squares.compactMap({ $0 }) {
            balance += piece.color == .white ? piece.kind.value : -piece.kind.value
        }
        return balance
    }

    var pieceCount: Int {
        squares.compactMap { $0 }.count
    }

    // MARK: - Helpers

    func move(from origin: Square, to target: Square, promotion: PieceKind? = nil) -> Move? {
        legalMoves(from: origin).first { $0.to == target && $0.promotion == promotion }
    }

    /// Pretty printable ASCII board, useful for logs and tests.
    var asciiDescription: String {
        var lines: [String] = []
        for rank in stride(from: 7, through: 0, by: -1) {
            var line = "\(rank + 1) "
            for file in 0..<8 {
                if let piece = squares[rank * 8 + file] {
                    line += String(piece.fenLetter) + " "
                } else {
                    line += ". "
                }
            }
            lines.append(line)
        }
        lines.append("  a b c d e f g h")
        return lines.joined(separator: "\n")
    }
}
