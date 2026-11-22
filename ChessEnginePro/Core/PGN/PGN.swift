//
//  PGN.swift
//  CHESS ENGINE PRO
//
//  PGN import (headers, comments, variations, NAGs) and export.
//

import Foundation

struct PGNMove: Hashable, Codable, Sendable, Identifiable {
    var id: UUID = UUID()
    var san: String
    var uci: String

    init(san: String, uci: String, id: UUID = UUID()) {
        self.san = san
        self.uci = uci
        self.id = id
    }
}

struct PGNGame: Identifiable, Hashable, Codable, Sendable {
    var id: UUID = UUID()
    var headers: [String: String] = [:]
    var startFEN: String = Board.startFEN
    var moves: [PGNMove] = []
    var result: String = "*"

    var event: String { headers["Event"] ?? "Partie" }
    var site: String { headers["Site"] ?? "" }
    var date: String { headers["Date"] ?? "" }
    var white: String { headers["White"] ?? "Weiß" }
    var black: String { headers["Black"] ?? "Schwarz" }
    var round: String { headers["Round"] ?? "" }

    var title: String {
        let names = "\(white) – \(black)"
        return names.trimmingCharacters(in: .whitespaces).isEmpty ? event : names
    }

    var subtitle: String {
        [date, event].filter { !$0.isEmpty && $0 != "?" }.joined(separator: " · ")
    }

    var startBoard: Board { Board(fen: startFEN) ?? Board() }

    /// Every position of the game, starting with the initial one.
    var boards: [Board] {
        var board = startBoard
        var result = [board]
        for move in moves {
            if let uci = Move(uci: move.uci), board.isLegal(uci) {
                board.apply(uci)
            } else if let sanMove = board.move(matchingSan: move.san) {
                board.apply(sanMove)
            } else {
                break
            }
            result.append(board)
        }
        return result
    }
}

enum PGNError: LocalizedError {
    case noGame
    case invalidFEN(String)
    case illegalMove(san: String, number: Int)

    var errorDescription: String? {
        switch self {
        case .noGame:
            return "Die Datei enthält keine lesbare Partie."
        case .invalidFEN(let fen):
            return "Ungültige Ausgangsstellung: \(fen)"
        case .illegalMove(let san, let number):
            return "Zug \(number) (\(san)) ist in dieser Stellung nicht möglich."
        }
    }
}

enum PGN {

    // MARK: - Parsing

    static func parse(_ text: String) throws -> [PGNGame] {
        let normalised = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalised.components(separatedBy: "\n")

        var games: [PGNGame] = []
        var headers: [String: String] = [:]
        var moveText = ""
        var inMovetext = false

        func flush() throws {
            let trimmed = moveText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty && headers.isEmpty { return }
            games.append(try buildGame(headers: headers, moveText: trimmed))
            headers = [:]
            moveText = ""
            inMovetext = false
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                if inMovetext { try flush() }
                if let pair = parseHeader(line) {
                    headers[pair.0] = pair.1
                }
            } else if !line.isEmpty {
                inMovetext = true
                moveText += line + "\n"
            }
        }
        try flush()

        if games.isEmpty { throw PGNError.noGame }
        return games
    }

    static func parseGame(_ text: String) throws -> PGNGame {
        guard let game = try parse(text).first else { throw PGNError.noGame }
        return game
    }

    private static func parseHeader(_ line: String) -> (String, String)? {
        guard let open = line.firstIndex(of: "\""),
              let close = line.lastIndex(of: "\""),
              open < close else { return nil }
        let key = line[line.index(after: line.startIndex)..<open]
            .trimmingCharacters(in: .whitespaces)
        let value = String(line[line.index(after: open)..<close])
        guard !key.isEmpty else { return nil }
        return (String(key), value)
    }

    /// Removes comments, variations and NAGs from movetext.
    static func stripAnnotations(_ text: String) -> String {
        var result = ""
        var braceDepth = 0
        var parenDepth = 0
        var lineComment = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]

            if lineComment {
                if character == "\n" {
                    lineComment = false
                    result.append(" ")
                }
                index = text.index(after: index)
                continue
            }

            switch character {
            case "{":
                braceDepth += 1
            case "}":
                if braceDepth > 0 { braceDepth -= 1 }
            case "(":
                if braceDepth == 0 { parenDepth += 1 }
            case ")":
                if braceDepth == 0 && parenDepth > 0 { parenDepth -= 1 }
            case ";":
                if braceDepth == 0 && parenDepth == 0 { lineComment = true }
            default:
                if braceDepth == 0 && parenDepth == 0 { result.append(character) }
            }
            index = text.index(after: index)
        }
        return result
    }

    private static func buildGame(headers: [String: String], moveText: String) throws -> PGNGame {
        var game = PGNGame()
        game.headers = headers

        if let fen = headers["FEN"], !fen.isEmpty {
            guard Board(fen: fen) != nil else { throw PGNError.invalidFEN(fen) }
            game.startFEN = fen
        }

        var board = game.startBoard
        let cleaned = stripAnnotations(moveText)
        let tokens = cleaned
            .replacingOccurrences(of: "\t", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\n" })
            .map(String.init)

        var detectedResult: String?
        for rawToken in tokens {
            var token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if token.isEmpty { continue }
            if ["1-0", "0-1", "1/2-1/2", "½-½", "*"].contains(token) {
                detectedResult = token == "½-½" ? "1/2-1/2" : token
                continue
            }

            // Strip leading move numbers ("12.", "12...").
            while let first = token.first, first.isNumber || first == "." {
                token.removeFirst()
            }
            // Strip NAG suffixes like $14
            if let dollar = token.firstIndex(of: "$") {
                token = String(token[token.startIndex..<dollar])
            }
            if token.isEmpty || token == "..." { continue }

            guard let move = board.move(matchingSan: token) else {
                throw PGNError.illegalMove(san: token, number: game.moves.count + 1)
            }
            let notation = board.san(for: move)
            game.moves.append(PGNMove(san: notation, uci: move.uci))
            board.apply(move)
        }

        if let result = headers["Result"], result != "*" {
            game.result = result
        }
        if let detectedResult = detectedResult {
            game.result = detectedResult
        }
        if game.result == "*" {
            game.result = board.status.resultString
        }

        if game.headers["Result"] == nil {
            game.headers["Result"] = game.result
        }

        return game
    }

    // MARK: - Export

    private static let headerOrder = [
        "Event", "Site", "Date", "Round", "White", "Black", "Result",
        "WhiteElo", "BlackElo", "TimeControl", "Termination", "FEN", "SetUp", "Annotator"
    ]

    static func export(_ game: PGNGame) -> String {
        var headers = game.headers
        headers["Event"] = headers["Event"] ?? "CHESS ENGINE PRO Analyse"
        headers["Site"] = headers["Site"] ?? "CHESS ENGINE PRO"
        headers["Date"] = headers["Date"] ?? currentDateString()
        headers["Round"] = headers["Round"] ?? "-"
        headers["White"] = headers["White"] ?? "Weiß"
        headers["Black"] = headers["Black"] ?? "Schwarz"
        headers["Result"] = game.result
        if game.startFEN != Board.startFEN {
            headers["SetUp"] = "1"
            headers["FEN"] = game.startFEN
        }

        var text = ""
        var written = Set<String>()
        for key in headerOrder where headers[key] != nil {
            text += "[\(key) \"\(escape(headers[key] ?? ""))\"]\n"
            written.insert(key)
        }
        for key in headers.keys.sorted() where !written.contains(key) {
            text += "[\(key) \"\(escape(headers[key] ?? ""))\"]\n"
        }
        text += "\n"

        let board = game.startBoard
        var number = board.fullmoveNumber
        var whiteToMove = board.sideToMove == .white
        var tokens: [String] = []

        for move in game.moves {
            if whiteToMove {
                tokens.append("\(number).")
                tokens.append(move.san)
            } else {
                if tokens.isEmpty {
                    tokens.append("\(number)...")
                }
                tokens.append(move.san)
                number += 1
            }
            whiteToMove.toggle()
        }

        let result = game.result.isEmpty ? "*" : game.result
        if whiteToMove {
            // Game ended after black's move.
        }
        tokens.append(result)

        var line = ""
        for token in tokens {
            if line.isEmpty {
                line = token
            } else if line.count + token.count + 1 > 80 {
                text += line + "\n"
                line = token
            } else {
                line += " " + token
            }
        }
        if !line.isEmpty { text += line + "\n" }

        return text
    }

    /// Convenience export for a move list that starts at `startFEN`.
    static func export(startFEN: String,
                       moves: [PGNMove],
                       headers: [String: String] = [:],
                       result: String = "*") -> String {
        var game = PGNGame()
        game.headers = headers
        game.startFEN = startFEN
        game.moves = moves
        game.result = result
        return export(game)
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "'")
             .replacingOccurrences(of: "\n", with: " ")
    }

    static func currentDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }
}
