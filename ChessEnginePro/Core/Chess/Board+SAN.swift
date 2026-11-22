//
//  Board+SAN.swift
//  CHESS ENGINE PRO
//
//  Standard algebraic notation: generation and parsing (used by PGN,
//  training puzzles and the engine line display).
//

import Foundation

extension Board {

    /// Strips decorations so two SAN strings can be compared.
    static func normalisedSAN(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "e.p.", with: "")
        text = text.replacingOccurrences(of: "ep", with: "")
        text = text.replacingOccurrences(of: "=", with: "")
        text = text.replacingOccurrences(of: "+", with: "")
        text = text.replacingOccurrences(of: "#", with: "")
        text = text.replacingOccurrences(of: "!", with: "")
        text = text.replacingOccurrences(of: "?", with: "")
        text = text.replacingOccurrences(of: " ", with: "")
        // Castling variants (0-0, o-o ...)
        if text.count >= 3, text.allSatisfy({ $0 == "0" || $0 == "O" || $0 == "-" }) {
            let dashes = text.filter { $0 == "-" }.count
            text = dashes >= 2 ? "O-O-O" : "O-O"
        }
        return text
    }

    /// Full SAN for a legal move including check/mate suffix.
    func san(for move: Move) -> String {
        guard let piece = squares[move.from.index] else { return move.uci }

        let next = applying(move)
        let givesCheck = next.isInCheck(next.sideToMove)
        let isMate = givesCheck && next.legalMoves.isEmpty
        let suffix = isMate ? "#" : (givesCheck ? "+" : "")

        let isCastle = piece.kind == .king && abs(move.to.file - move.from.file) == 2
        if isCastle {
            return (move.to.file == 6 ? "O-O" : "O-O-O") + suffix
        }

        let isCapture = squares[move.to.index] != nil
            || (piece.kind == .pawn && move.from.file != move.to.file)

        if piece.kind == .pawn {
            var text = ""
            if isCapture {
                text += String(Character(UnicodeScalar(UInt8(97 + move.from.file))))
                text += "x"
            }
            text += move.to.name
            if let promotion = move.promotion {
                text += "=" + String(promotion.letter)
            }
            return text + suffix
        }

        var text = String(piece.kind.letter)

        // Disambiguation between identical pieces reaching the same square.
        let competitors = legalMoves.filter { candidate in
            guard candidate.to == move.to, candidate.from != move.from else { return false }
            guard let other = squares[candidate.from.index] else { return false }
            return other.kind == piece.kind && other.color == piece.color
        }
        if !competitors.isEmpty {
            let sameFile = competitors.contains { $0.from.file == move.from.file }
            let sameRank = competitors.contains { $0.from.rank == move.from.rank }
            if !sameFile {
                text += String(Character(UnicodeScalar(UInt8(97 + move.from.file))))
            } else if !sameRank {
                text += String(move.from.rank + 1)
            } else {
                text += move.from.name
            }
        }

        if isCapture { text += "x" }
        text += move.to.name
        return text + suffix
    }

    /// Resolves a SAN string (decorations tolerated) to a legal move.
    func move(matchingSan raw: String) -> Move? {
        let wanted = Board.normalisedSAN(raw)
        guard !wanted.isEmpty else { return nil }

        // Direct UCI fallback.
        if let uciMove = Move(uci: raw), isLegal(uciMove) { return uciMove }

        for move in legalMoves where Board.normalisedSAN(san(for: move)) == wanted {
            return move
        }

        // Tolerate pawn captures written without the file ("xd5") and other
        // slightly sloppy exporters by matching on destination + piece.
        for move in legalMoves {
            var generated = Board.normalisedSAN(san(for: move))
            if generated.hasPrefix("x") { generated.removeFirst() }
            if generated == wanted { return move }
        }

        return nil
    }

    /// Applies a SAN move and returns the resulting board.
    func applying(san: String) -> Board? {
        guard let move = move(matchingSan: san) else { return nil }
        return applying(move)
    }

    /// SAN sequence for a list of moves. Illegal moves end the sequence.
    func sanSequence(for moves: [Move]) -> [String] {
        var board = self
        var result: [String] = []
        for move in moves {
            guard board.isLegal(move) else { break }
            result.append(board.san(for: move))
            board.apply(move)
        }
        return result
    }

    /// Converts a UCI principal variation into SAN, starting from this board.
    func sanSequence(fromUCI moves: [String]) -> [String] {
        var board = self
        var result: [String] = []
        for uci in moves {
            guard let move = Move(uci: uci), board.isLegal(move) else { break }
            result.append(board.san(for: move))
            board.apply(move)
        }
        return result
    }

    /// Boards resulting from a UCI line, including the starting board.
    func boards(fromUCI moves: [String]) -> [Board] {
        var board = self
        var boards = [board]
        for uci in moves {
            guard let move = Move(uci: uci), board.isLegal(move) else { break }
            board.apply(move)
            boards.append(board)
        }
        return boards
    }
}
