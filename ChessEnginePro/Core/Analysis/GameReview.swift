//
//  GameReview.swift
//  CHESS ENGINE PRO
//
//  Walks through an imported PGN, evaluates every position and derives
//  per move quality, accuracy and an evaluation graph.
//

import Foundation
import Combine

@MainActor
final class GameReviewController: ObservableObject {

    struct ReviewedMove: Identifiable, Hashable {
        var id: Int { ply }
        var ply: Int
        var number: Int
        var color: PieceColor
        var san: String
        var uci: String
        var scoreBefore: EvalScore
        var scoreAfter: EvalScore
        var quality: MoveQuality
        var bestSAN: String?
        var loss: Int
    }

    @Published private(set) var game: PGNGame?
    @Published private(set) var boards: [Board] = []
    @Published private(set) var moves: [ReviewedMove] = []
    @Published private(set) var progress: Double = 0
    @Published private(set) var isReviewing = false
    @Published private(set) var selectedPly: Int = 0
    @Published private(set) var accuracyWhite: Double?
    @Published private(set) var accuracyBlack: Double?
    @Published private(set) var errorMessage: String?

    private var reviewTask: Task<Void, Never>?
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
    }

    var selectedBoard: Board {
        if boards.indices.contains(selectedPly) { return boards[selectedPly] }
        return boards.last ?? Board()
    }

    var selectedMove: ReviewedMove? {
        guard selectedPly > 0 else { return nil }
        return moves.first { $0.ply == selectedPly - 1 }
    }

    func select(ply: Int) {
        selectedPly = max(0, min(ply, max(0, boards.count - 1)))
    }

    func cancel() {
        reviewTask?.cancel()
        reviewTask = nil
        isReviewing = false
    }

    func startReview(of game: PGNGame, engine: ChessEngine, depth: Int) {
        cancel()
        self.game = game
        boards = game.boards
        moves = []
        progress = 0
        selectedPly = boards.isEmpty ? 0 : min(1, boards.count - 1)
        errorMessage = nil

        guard boards.count >= 2 else {
            errorMessage = "Die Partie enthält keine Züge."
            return
        }

        isReviewing = true
        let limits = EngineLimits.depth(max(8, min(depth, 20)), multiPV: 1)
        let positions = boards

        reviewTask = Task { [weak self] in
            guard let self = self else { return }
            var scores: [EvalScore] = []
            var bestMoves: [Move?] = []

            for (index, position) in positions.enumerated() {
                if Task.isCancelled { break }
                let result = await self.evaluate(position,
                                                 engine: engine,
                                                 limits: limits)
                scores.append(result.0)
                bestMoves.append(result.1)
                self.progress = Double(index + 1) / Double(positions.count)
            }

            guard !Task.isCancelled else {
                self.isReviewing = false
                return
            }

            self.finalise(scores: scores, bestMoves: bestMoves, positions: positions)
            self.isReviewing = false
        }
    }

    private func evaluate(_ board: Board,
                          engine: ChessEngine,
                          limits: EngineLimits) async -> (EvalScore, Move?) {
        var lastUpdate: EngineUpdate?
        for await update in engine.analyze(fen: board.fen, limits: limits) {
            lastUpdate = update
            if update.isFinal { break }
        }
        if Task.isCancelled { engine.stop() }
        let score = lastUpdate?.lines.first?.score ?? .zero
        let move = lastUpdate?.bestMove ?? lastUpdate?.lines.first?.firstMove
        return (score, move)
    }

    private func finalise(scores: [EvalScore], bestMoves: [Move?], positions: [Board]) {
        guard scores.count == positions.count else {
            errorMessage = "Die Analyse wurde unterbrochen."
            return
        }
        var reviewed: [ReviewedMove] = []
        var whiteAccuracySum = 0.0
        var blackAccuracySum = 0.0
        var whiteCount = 0
        var blackCount = 0

        guard let game = game else { return }
        let startBoard = positions[0]

        for index in 0..<game.moves.count {
            guard positions.indices.contains(index + 1) else { break }
            let san = game.moves[index].san
            let scoreBefore = scores[index]
            let scoreAfter = scores[index + 1]
            let loss = EvalScore.loss(from: scoreBefore, to: scoreAfter)
            let quality = MoveQuality.classify(loss: loss)
            let color: PieceColor = index % 2 == 0 ? .white : .black
            
            var bestSAN: String?
            if let best = bestMoves[index], positions[index].isLegal(best) {
                bestSAN = positions[index].san(for: best)
            }

            reviewed.append(ReviewedMove(ply: index,
                                         number: startBoard.fullmoveNumber + index / 2,
                                         color: color,
                                         san: san,
                                         uci: game.moves[index].uci,
                                         scoreBefore: scoreBefore,
                                         scoreAfter: scoreAfter,
                                         quality: quality,
                                         bestSAN: bestSAN,
                                         loss: loss))

            let moveAccuracy = max(0.0, 100.0 - Double(loss) / 12.0)
            if color == .white {
                whiteAccuracySum += moveAccuracy
                whiteCount += 1
            } else {
                blackAccuracySum += moveAccuracy
                blackCount += 1
            }
        }

        moves = reviewed
        accuracyWhite = whiteCount > 0 ? whiteAccuracySum / Double(whiteCount) : nil
        accuracyBlack = blackCount > 0 ? blackAccuracySum / Double(blackCount) : nil
        selectedPly = min(1, positions.count - 1)
    }

    // MARK: - Output

    var mistakes: [ReviewedMove] {
        moves.filter { $0.quality == .blunder || $0.quality == .mistake }
    }

    var summaryText: String {
        guard !moves.isEmpty else { return "Noch keine Auswertung." }
        let blunders = moves.filter { $0.quality == .blunder }.count
        let mistakes = moves.filter { $0.quality == .mistake }.count
        let inaccuracies = moves.filter { $0.quality == .inaccuracy }.count
        return "\(moves.count) Züge · \(blunders) Patzer · \(mistakes) Fehler · \(inaccuracies) Ungenauigkeiten"
    }

    func exportAnnotated() -> String {
        guard let game = game else { return "" }
        var headers = game.headers
        headers["Annotator"] = "CHESS ENGINE PRO"
        var text = PGN.export(game)
        // Append a compact evaluation list as comments.
        var annotations = "\n\n"
        for reviewed in moves {
            annotations += "{ \(reviewed.quality.localizedTitle), \(reviewed.scoreBefore.display) } "
            if reviewed.ply % 2 == 1 { annotations += "\n" }
        }
        text += annotations
        return text
    }
}
