//
//  TrainingModels.swift
//  CHESS ENGINE PRO
//
//  Bundled puzzle and opening libraries (fully offline).
//

import Foundation
import Combine

enum PuzzleCategory: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case mate1
    case mate2
    case mate3
    case tactics
    case endgame
    case defense

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mate1: return "Matt in 1"
        case .mate2: return "Matt in 2"
        case .mate3: return "Matt in 3"
        case .tactics: return "Taktik"
        case .endgame: return "Endspiele"
        case .defense: return "Verteidigung"
        }
    }

    var subtitle: String {
        switch self {
        case .mate1: return "Finde das Matt in einem Zug"
        case .mate2: return "Forciertes Matt in zwei Zügen"
        case .mate3: return "Matt in drei Zügen"
        case .tactics: return "Gabeln, Fesselungen, Abzüge"
        case .endgame: return "Technik im Endspiel"
        case .defense: return "Rette die Stellung"
        }
    }

    var icon: String {
        switch self {
        case .mate1: return "1.circle.fill"
        case .mate2: return "2.circle.fill"
        case .mate3: return "3.circle.fill"
        case .tactics: return "bolt.fill"
        case .endgame: return "hourglass"
        case .defense: return "shield.fill"
        }
    }
}

struct TrainingPuzzle: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var title: String
    var fen: String
    /// Alternating UCI moves: solution[0] belongs to the solver, solution[1]
    /// is the forced reply, and so on.
    var solution: [String]
    var category: PuzzleCategory
    var difficulty: Int
    var theme: String
    var hint: String

    var sideToMove: PieceColor {
        Board(fen: fen)?.sideToMove ?? .white
    }

    var difficultyText: String {
        String(repeating: "●", count: max(1, min(5, difficulty)))
            + String(repeating: "○", count: max(0, 5 - max(1, min(5, difficulty))))
    }
}

@MainActor
final class PuzzleLibrary: ObservableObject {

    static let shared = PuzzleLibrary()

    @Published private(set) var puzzles: [TrainingPuzzle] = []
    @Published private(set) var loadError: String?

    private init() {
        load()
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "TrainingPuzzles", withExtension: "json") else {
            loadError = "Trainingsdaten nicht gefunden."
            return
        }
        do {
            let data = try Data(contentsOf: url)
            puzzles = try JSONDecoder().decode([TrainingPuzzle].self, from: data)
                .filter { Board(fen: $0.fen) != nil }
        } catch {
            loadError = error.localizedDescription
        }
    }

    func puzzles(in category: PuzzleCategory) -> [TrainingPuzzle] {
        puzzles.filter { $0.category == category }
    }

    func count(in category: PuzzleCategory) -> Int {
        puzzles(in: category).count
    }

    func randomPuzzle(in category: PuzzleCategory) -> TrainingPuzzle? {
        puzzles(in: category).randomElement()
    }
}

struct OpeningLine: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var eco: String
    var description: String
    /// SAN moves from the starting position.
    var moves: [String]

    var moveCount: Int { moves.count }
}

@MainActor
final class OpeningLibrary: ObservableObject {

    static let shared = OpeningLibrary()

    @Published private(set) var openings: [OpeningLine] = []
    @Published private(set) var loadError: String?

    private init() {
        load()
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "Openings", withExtension: "json") else {
            loadError = "Eröffnungsdaten nicht gefunden."
            return
        }
        do {
            let data = try Data(contentsOf: url)
            openings = try JSONDecoder().decode([OpeningLine].self, from: data)
        } catch {
            loadError = error.localizedDescription
        }
    }
}
