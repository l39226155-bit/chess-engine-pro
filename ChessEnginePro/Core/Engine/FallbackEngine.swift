//
//  FallbackEngine.swift
//  CHESS ENGINE PRO
//
//  A compact alpha-beta engine written in Swift. It keeps every analysis
//  feature usable when the Stockfish static library is not present (for
//  example a simulator build without scripts/build-stockfish.sh).
//

import Foundation

final class FallbackEngine: ChessEngine {

    static let mateScore = 1_000_000

    let displayName = "Eingebaute Engine"
    var isAvailable: Bool { true }

    private var currentTask: Task<Void, Never>?

    func setOption(_ name: String, value: String) {
        // The built-in engine has a fixed configuration.
    }

    func stop() {
        currentTask?.cancel()
        currentTask = nil
    }

    func analyze(fen: String, limits: EngineLimits) -> AsyncStream<EngineUpdate> {
        stop()

        return AsyncStream<EngineUpdate> { continuation in
            let task = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self, let board = Board(fen: fen) else {
                    continuation.finish()
                    return
                }
                await self.run(board: board, limits: limits, continuation: continuation)
                continuation.finish()
            }
            self.currentTask = task
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Search driver

    private func run(board: Board,
                     limits: EngineLimits,
                     continuation: AsyncStream<EngineUpdate>.Continuation) async {
        let started = DispatchTime.now()
        let deadline = limits.moveTimeMs.map { DispatchTime.now() + .milliseconds($0) }
        let maxDepth = max(1, min(limits.depth, 6))
        let multiPV = max(1, limits.multiPV)

        let rootMoves = board.legalMoves
        guard !rootMoves.isEmpty else {
            let score = board.isInCheck(board.sideToMove)
                ? EvalScore.mate(board.sideToMove == .white ? -1 : 1)
                : EvalScore.centipawns(0)
            continuation.yield(EngineUpdate(depth: 0, seldepth: 0, nodes: 0, timeMs: 0,
                                            lines: [EngineLine(rank: 1, score: score, depth: 0, pv: [], nodes: 0)],
                                            bestMove: nil, isFinal: true))
            return
        }

        var nodes = 0
        var lastEmittedLines: [EngineLine] = []

        for depth in 1...maxDepth {
            if Task.isCancelled { return }

            let context = SearchContext(maxDepth: maxDepth + 2)
            var scored: [(move: Move, score: Int, pv: [Move])] = []

            for move in rootMoves {
                if Task.isCancelled { return }
                if let deadline = deadline, DispatchTime.now() > deadline { break }

                let next = board.applying(move)
                let score = -context.negamax(board: next,
                                             depth: depth - 1,
                                             alpha: -FallbackEngine.mateScore,
                                             beta: FallbackEngine.mateScore,
                                             ply: 1,
                                             deadline: deadline,
                                             nodes: &nodes)
                scored.append((move, score, [move] + context.pvTable[1]))
            }

            if scored.isEmpty { break }

            scored.sort { $0.score > $1.score }

            var lines: [EngineLine] = []
            for (offset, entry) in scored.prefix(multiPV).enumerated() {
                let whiteScore = board.sideToMove == .white ? entry.score : -entry.score
                let pvStrings = entry.pv.map { $0.uci }
                lines.append(EngineLine(rank: offset + 1,
                                        score: FallbackEngine.scoreToEval(whiteScore),
                                        depth: depth,
                                        pv: pvStrings,
                                        nodes: UInt64(nodes)))
            }
            lastEmittedLines = lines

            let elapsed = elapsedMilliseconds(since: started)
            continuation.yield(EngineUpdate(depth: depth,
                                            seldepth: depth,
                                            nodes: UInt64(nodes),
                                            timeMs: elapsed,
                                            lines: lines,
                                            bestMove: depth == maxDepth ? scored.first?.move : nil,
                                            isFinal: depth == maxDepth))

            await Task.yield()

            if let deadline = deadline, DispatchTime.now() > deadline { break }
        }

        if lastEmittedLines.isEmpty {
            continuation.finish()
        }
    }

    private func elapsedMilliseconds(since start: DispatchTime) -> Int {
        let now = DispatchTime.now()
        let nanoseconds = now.uptimeNanoseconds - start.uptimeNanoseconds
        return Int(nanoseconds / 1_000_000)
    }

    static func scoreToEval(_ score: Int) -> EvalScore {
        if abs(score) > mateScore - 1000 {
            let plies = mateScore - abs(score)
            let moves = max(1, (plies + 1) / 2)
            return .mate(score > 0 ? moves : -moves)
        }
        return .centipawns(score)
    }

    // MARK: - Evaluation

    /// Static evaluation in centipawns from White's point of view.
    static func evaluate(_ board: Board) -> Int {
        var score = 0
        var whitePawnsByFile = [Int](repeating: 0, count: 8)
        var blackPawnsByFile = [Int](repeating: 0, count: 8)
        var whiteBishops = 0
        var blackBishops = 0
        var whiteRooks: [Square] = []
        var blackRooks: [Square] = []
        var whiteKing = Square(index: 4)
        var blackKing = Square(index: 60)

        for index in 0..<64 {
            guard let piece = board.squares[index] else { continue }
            let square = Square(index: index)
            let sign = piece.color == .white ? 1 : -1
            let relativeRank = piece.color == .white ? square.rank : 7 - square.rank
            let fileCentrality = 3 - min(abs(square.file - 3), abs(square.file - 4))
            let rankCentrality = 3 - min(abs(square.rank - 3), abs(square.rank - 4))

            var value = piece.kind.value
            switch piece.kind {
            case .pawn:
                value += relativeRank * 6
                if relativeRank == 6 { value += 45 }
                value += fileCentrality * 3
                if piece.color == .white {
                    whitePawnsByFile[square.file] += 1
                } else {
                    blackPawnsByFile[square.file] += 1
                }
            case .knight:
                value += fileCentrality * 6 + rankCentrality * 6
                if relativeRank == 0 && square.rank != 0 { value -= 8 }
            case .bishop:
                value += fileCentrality * 4 + relativeRank * 2
                if piece.color == .white { whiteBishops += 1 } else { blackBishops += 1 }
            case .rook:
                value += relativeRank * 2
                if piece.color == .white { whiteRooks.append(square) } else { blackRooks.append(square) }
            case .queen:
                value += fileCentrality
            case .king:
                value += fileCentrality * 12 - relativeRank * 18
                if piece.color == .white { whiteKing = square } else { blackKing = square }
            }
            score += sign * value
        }

        // Bishop pair
        if whiteBishops >= 2 { score += 28 }
        if blackBishops >= 2 { score -= 28 }

        // Pawn structure
        for file in 0..<8 {
            if whitePawnsByFile[file] > 1 { score -= 14 * (whitePawnsByFile[file] - 1) }
            if blackPawnsByFile[file] > 1 { score += 14 * (blackPawnsByFile[file] - 1) }

            let whiteNeighbours = (file > 0 ? whitePawnsByFile[file - 1] : 0)
                + (file < 7 ? whitePawnsByFile[file + 1] : 0)
            let blackNeighbours = (file > 0 ? blackPawnsByFile[file - 1] : 0)
                + (file < 7 ? blackPawnsByFile[file + 1] : 0)
            if whitePawnsByFile[file] > 0 && whiteNeighbours == 0 { score -= 16 }
            if blackPawnsByFile[file] > 0 && blackNeighbours == 0 { score += 16 }
        }

        // Rooks on open or half open files
        for rook in whiteRooks {
            if whitePawnsByFile[rook.file] == 0 { score += blackPawnsByFile[rook.file] == 0 ? 22 : 10 }
        }
        for rook in blackRooks {
            if blackPawnsByFile[rook.file] == 0 { score -= whitePawnsByFile[rook.file] == 0 ? 22 : 10 }
        }

        // King shelter
        score += shelter(for: .white, king: whiteKing, board: board)
        score -= shelter(for: .black, king: blackKing, board: board)

        // Tempo
        score += board.sideToMove == .white ? 8 : -8

        return score
    }

    private static func shelter(for color: PieceColor, king: Square, board: Board) -> Int {
        let direction = color == .white ? 1 : -1
        var bonus = 0
        for fileOffset in -1...1 {
            let file = king.file + fileOffset
            guard (0..<8).contains(file) else { continue }
            for rankOffset in 1...2 {
                let rank = king.rank + direction * rankOffset
                guard (0..<8).contains(rank) else { continue }
                if let piece = board.squares[rank * 8 + file], piece.kind == .pawn, piece.color == color {
                    bonus += rankOffset == 1 ? 8 : 4
                }
            }
        }
        return bonus
    }
}

// MARK: - Search

private final class SearchContext {
    var pvTable: [[Move]]
    private var nodeCounter = 0

    init(maxDepth: Int) {
        pvTable = Array(repeating: [], count: max(4, maxDepth))
    }

    /// Negamax with alpha-beta pruning and a capture quiescence search.
    /// Scores are relative to the side to move at `board`.
    func negamax(board: Board,
                 depth: Int,
                 alpha: Int,
                 beta: Int,
                 ply: Int,
                 deadline: DispatchTime?,
                 nodes: inout Int) -> Int {
        pvTable[ply] = []

        if let deadline = deadline, ply <= 2 {
            nodeCounter += 1
            if nodeCounter % 256 == 0, DispatchTime.now() > deadline { return 0 }
        }
        nodes += 1

        let moves = board.legalMoves
        if moves.isEmpty {
            if board.isInCheck(board.sideToMove) {
                return -FallbackEngine.mateScore + ply
            }
            return 0
        }

        if depth <= 0 {
            return quiescence(board: board, alpha: alpha, beta: beta, ply: ply, depth: 3, nodes: &nodes)
        }

        var alpha = alpha
        var bestMove: Move?
        let ordered = Self.order(moves, board: board)

        for move in ordered {
            let next = board.applying(move)
            let score = -negamax(board: next,
                                 depth: depth - 1,
                                 alpha: -beta,
                                 beta: -alpha,
                                 ply: ply + 1,
                                 deadline: deadline,
                                 nodes: &nodes)
            if score > alpha {
                alpha = score
                bestMove = move
            }
            if alpha >= beta { break }
        }

        if let bestMove = bestMove {
            pvTable[ply] = [bestMove] + pvTable[ply + 1]
        }
        return alpha
    }

    private func quiescence(board: Board,
                            alpha: Int,
                            beta: Int,
                            ply: Int,
                            depth: Int,
                            nodes: inout Int) -> Int {
        nodes += 1
        let staticEval = board.sideToMove == .white
            ? FallbackEngine.evaluate(board)
            : -FallbackEngine.evaluate(board)

        var alpha = max(alpha, staticEval)
        if alpha >= beta || depth <= 0 { return alpha }

        let captures = board.legalMoves.filter { move in
            board.squares[move.to.index] != nil
                || (board.squares[move.from.index]?.kind == .pawn && move.from.file != move.to.file)
        }
        if captures.isEmpty { return alpha }

        for move in Self.order(captures, board: board) {
            let next = board.applying(move)
            let score = -quiescence(board: next,
                                    alpha: -beta,
                                    beta: -alpha,
                                    ply: ply + 1,
                                    depth: depth - 1,
                                    nodes: &nodes)
            if score > alpha { alpha = score }
            if alpha >= beta { break }
        }
        return alpha
    }

    /// Most valuable victim / least valuable attacker ordering.
    private static func order(_ moves: [Move], board: Board) -> [Move] {
        moves.sorted { first, second in
            score(first, board: board) > score(second, board: board)
        }
    }

    private static func score(_ move: Move, board: Board) -> Int {
        var value = 0
        if let victim = board.squares[move.to.index] {
            value += victim.kind.value * 10
        }
        if let attacker = board.squares[move.from.index] {
            value -= attacker.kind.value
            value += (attacker.kind == .pawn ? 40 : 0)
        }
        if let promotion = move.promotion {
            value += promotion.value
        }
        return value
    }
}
