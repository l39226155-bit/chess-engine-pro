//
//  Types.swift
//  CHESS ENGINE PRO
//
//  Fundamental chess domain types shared by every layer of the app.
//

import Foundation

// MARK: - Color

enum PieceColor: String, Codable, CaseIterable, Hashable, Sendable {
    case white
    case black

    var opponent: PieceColor { self == .white ? .black : .white }

    var localizedName: String { self == .white ? "Weiß" : "Schwarz" }

    /// +1 for white, -1 for black. Handy for score normalisation.
    var sign: Int { self == .white ? 1 : -1 }

    var glyphLetter: String { self == .white ? "w" : "b" }
}

// MARK: - Piece kind

enum PieceKind: String, Codable, CaseIterable, Hashable, Sendable {
    case pawn
    case knight
    case bishop
    case rook
    case queen
    case king

    /// Uppercase letter used in FEN and SAN.
    var letter: Character {
        switch self {
        case .pawn: return "P"
        case .knight: return "N"
        case .bishop: return "B"
        case .rook: return "R"
        case .queen: return "Q"
        case .king: return "K"
        }
    }

    /// SAN prefix: pawn moves carry no letter.
    var sanPrefix: String { self == .pawn ? "" : String(letter) }

    var localizedName: String {
        switch self {
        case .pawn: return "Bauer"
        case .knight: return "Springer"
        case .bishop: return "Läufer"
        case .rook: return "Turm"
        case .queen: return "Dame"
        case .king: return "König"
        }
    }

    /// Centipawn-ish material value, king is deliberately worthless.
    var value: Int {
        switch self {
        case .pawn: return 100
        case .knight: return 320
        case .bishop: return 330
        case .rook: return 500
        case .queen: return 900
        case .king: return 0
        }
    }

    init?(letter: Character) {
        switch Character(letter.lowercased()) {
        case "p": self = .pawn
        case "n": self = .knight
        case "b": self = .bishop
        case "r": self = .rook
        case "q": self = .queen
        case "k": self = .king
        default: return nil
        }
    }

    /// Promotion pieces offered by the UI, ordered by usefulness.
    static var promotionChoices: [PieceKind] { [.queen, .rook, .bishop, .knight] }
}

// MARK: - Piece

struct Piece: Hashable, Codable, Sendable {
    var color: PieceColor
    var kind: PieceKind

    var fenLetter: Character {
        let base = kind.letter
        return color == .white ? base : Character(base.lowercased())
    }

    init(color: PieceColor, kind: PieceKind) {
        self.color = color
        self.kind = kind
    }

    init?(fenLetter: Character) {
        guard let kind = PieceKind(letter: fenLetter) else { return nil }
        self.kind = kind
        self.color = fenLetter.isUppercase ? .white : .black
    }
}

// MARK: - Square

/// 0-based square index: a1 == 0, h1 == 7, a8 == 56, h8 == 63.
struct Square: Hashable, Codable, Sendable, CustomStringConvertible {
    var index: Int

    init(index: Int) {
        self.index = index
    }

    init(file: Int, rank: Int) {
        self.index = rank * 8 + file
    }

    init?(name: String) {
        let chars = Array(name.lowercased())
        guard chars.count == 2,
              let fileAscii = chars[0].asciiValue,
              let rankValue = chars[1].wholeNumberValue else { return nil }
        let file = Int(fileAscii) - 97
        let rank = rankValue - 1
        guard (0..<8).contains(file), (0..<8).contains(rank) else { return nil }
        self.index = rank * 8 + file
    }

    var file: Int { index % 8 }
    var rank: Int { index / 8 }

    var name: String {
        let fileLetter = Character(UnicodeScalar(UInt8(97 + file)))
        return String(fileLetter) + String(rank + 1)
    }

    var description: String { name }

    /// Light squares are a1, h1, a8 ... i.e. (file + rank) is odd.
    var isLightSquare: Bool { (file + rank) % 2 == 1 }

    /// Returns nil when the offset leaves the board.
    func offset(file df: Int, rank dr: Int) -> Square? {
        let f = file + df
        let r = rank + dr
        guard (0..<8).contains(f), (0..<8).contains(r) else { return nil }
        return Square(file: f, rank: r)
    }

    static let all: [Square] = (0..<64).map(Square.init(index:))
}

// MARK: - Move

/// A move is intentionally minimal: from/to plus an optional promotion.
/// Everything else (captures, castling, en passant) is derived from the board,
/// which keeps PGN/UCI conversion trivial.
struct Move: Hashable, Codable, Sendable {
    var from: Square
    var to: Square
    var promotion: PieceKind?

    init(from: Square, to: Square, promotion: PieceKind? = nil) {
        self.from = from
        self.to = to
        self.promotion = promotion
    }

    /// Long algebraic / UCI notation, e.g. "e2e4" or "e7e8q".
    var uci: String {
        var text = from.name + to.name
        if let promotion = promotion {
            text += String(promotion.letter).lowercased()
        }
        return text
    }

    init?(uci: String) {
        let text = uci.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard text.count == 4 || text.count == 5 else { return nil }
        let chars = Array(text)
        guard let from = Square(name: String(chars[0...1])),
              let to = Square(name: String(chars[2...3])) else { return nil }
        var promotion: PieceKind?
        if chars.count == 5, let kind = PieceKind(letter: chars[4]),
           PieceKind.promotionChoices.contains(kind) {
            promotion = kind
        }
        self.init(from: from, to: to, promotion: promotion)
    }

    var isPromotion: Bool { promotion != nil }
}

// MARK: - Castling rights

struct CastlingRights: Hashable, Codable, Sendable {
    var whiteKingSide: Bool
    var whiteQueenSide: Bool
    var blackKingSide: Bool
    var blackQueenSide: Bool

    init(whiteKingSide: Bool = true,
         whiteQueenSide: Bool = true,
         blackKingSide: Bool = true,
         blackQueenSide: Bool = true) {
        self.whiteKingSide = whiteKingSide
        self.whiteQueenSide = whiteQueenSide
        self.blackKingSide = blackKingSide
        self.blackQueenSide = blackQueenSide
    }

    static let none = CastlingRights(whiteKingSide: false,
                                    whiteQueenSide: false,
                                    blackKingSide: false,
                                    blackQueenSide: false)

    var isEmpty: Bool {
        !whiteKingSide && !whiteQueenSide && !blackKingSide && !blackQueenSide
    }

    /// FEN field, "-" when no rights remain.
    var fen: String {
        var text = ""
        if whiteKingSide { text += "K" }
        if whiteQueenSide { text += "Q" }
        if blackKingSide { text += "k" }
        if blackQueenSide { text += "q" }
        return text.isEmpty ? "-" : text
    }

    init(fen: String) {
        self.whiteKingSide = fen.contains("K")
        self.whiteQueenSide = fen.contains("Q")
        self.blackKingSide = fen.contains("k")
        self.blackQueenSide = fen.contains("q")
    }
}

// MARK: - Position status

enum GameStatus: Hashable, Sendable {
    case active
    case check
    case checkmate(winner: PieceColor)
    case stalemate
    case drawInsufficientMaterial
    case drawFiftyMove

    var isFinished: Bool {
        switch self {
        case .active, .check: return false
        default: return true
        }
    }

    var localizedDescription: String {
        switch self {
        case .active: return "Partie läuft"
        case .check: return "Schach"
        case .checkmate(let winner): return "Schachmatt – \(winner.localizedName) gewinnt"
        case .stalemate: return "Patt – Remis"
        case .drawInsufficientMaterial: return "Remis – unzureichendes Material"
        case .drawFiftyMove: return "Remis – 50-Züge-Regel"
        }
    }

    var resultString: String {
        switch self {
        case .checkmate(let winner): return winner == .white ? "1-0" : "0-1"
        case .stalemate, .drawInsufficientMaterial, .drawFiftyMove: return "1/2-1/2"
        case .active, .check: return "*"
        }
    }
}

// MARK: - Board arrow

/// A single engine arrow drawn on top of the analysis board.
struct BoardArrow: Identifiable, Hashable, Codable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        case best
        case alternative
        case interesting
        case critical

        var localizedTitle: String {
            switch self {
            case .best: return "Bester Zug"
            case .alternative: return "Gute Alternative"
            case .interesting: return "Interessant"
            case .critical: return "Kritisch"
            }
        }
    }

    var from: Square
    var to: Square
    var kind: Kind
    var label: String?

    var id: String { kind.rawValue + "-" + from.name + to.name }

    init(from: Square, to: Square, kind: Kind, label: String? = nil) {
        self.from = from
        self.to = to
        self.kind = kind
        self.label = label
    }
}
