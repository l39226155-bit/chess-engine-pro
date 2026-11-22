//
//  AnalysisManager.swift
//  CHESS ENGINE PRO
//
//  Coordinates the engine, the board and the natural move selection.
//  All publishing happens on the main actor; engine work stays off the UI thread.
//

import Foundation
import Combine

struct CandidateMove: Identifiable, Hashable, Sendable {
    var rank: Int
    var move: Move
    var san: String
    var score: EvalScore
    var pvUCI: [String]
    var pvSAN: [String]
    var quality: MoveQuality
    var features: MoveFeatures
    var styleFit: Double
    var tags: [String]
    var depth: Int

    var id: Int { rank }

    var arrowKind: BoardArrow.Kind {
        NaturalMoveSelector.arrowKind(rank: rank, quality: quality)
    }
}

@MainActor
final class AnalysisManager: ObservableObject {

    struct HistoryEntry: Hashable {
        var board: Board
        var move: Move
        var san: String
    }

    // MARK: - Published state

    @Published private(set) var board: Board = Board()
    @Published private(set) var lastMove: Move?
    @Published private(set) var candidates: [CandidateMove] = []
    @Published private(set) var evaluation: EvalScore = .zero
    @Published private(set) var depth: Int = 0
    @Published private(set) var seldepth: Int = 0
    @Published private(set) var nodes: UInt64 = 0
    @Published private(set) var isAnalyzing: Bool = false
    @Published private(set) var engineName: String = ""
    @Published private(set) var statusMessage: String?
    @Published private(set) var history: [HistoryEntry] = []
    @Published private(set) var moveLog: [String] = []
    @Published private(set) var sessionStartFEN: String = Board.startFEN
    @Published private(set) var sessionMoves: [PGNMove] = []
    @Published private(set) var isFlipped: Bool = false
    @Published private(set) var hiddenArrowIDs: Set<String> = []
    @Published var showsArrows: Bool = true

    // Preview (stepping through a variation)
    @Published private(set) var previewCandidate: CandidateMove?
    @Published private(set) var previewBoards: [Board] = []
    @Published private(set) var previewMoves: [Move] = []
    @Published private(set) var previewPly: Int = 0

    @Published var style: MoveStyle

    // MARK: - Dependencies

    private let settings: SettingsStore
    private let stockfish = StockfishEngine.shared
    private let fallback = FallbackEngine()
    private var analysisTask: Task<Void, Never>?
    private var generation = 0

    init(settings: SettingsStore) {
        self.settings = settings
        self.style = settings.settings.style
    }

    // MARK: - Derived state

    var activeEngine: ChessEngine {
        switch settings.settings.backend {
        case .builtIn:
            return fallback
        case .stockfish:
            return stockfish.isAvailable ? stockfish : fallback
        case .auto:
            return stockfish.isAvailable ? stockfish : fallback
        }
    }

    var usesStockfish: Bool {
        activeEngine === stockfish
    }

    var displayBoard: Board {
        if previewCandidate != nil, previewBoards.indices.contains(previewPly) {
            return previewBoards[previewPly]
        }
        return board
    }

    var displayLastMove: Move? {
        if previewCandidate != nil {
            if previewPly > 0, previewMoves.indices.contains(previewPly - 1) {
                return previewMoves[previewPly - 1]
            }
            return nil
        }
        return lastMove
    }

    var boardOrientation: PieceColor {
        isFlipped ? .black : .white
    }

    var isPreviewing: Bool { previewCandidate != nil }

    var canPreviewBack: Bool { isPreviewing && previewPly > 0 }
    var canPreviewForward: Bool {
        isPreviewing && previewPly < max(0, previewBoards.count - 1)
    }

    var turnText: String {
        let status = displayBoard.status
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
            return "\(displayBoard.sideToMove.localizedName) am Zug – Schach"
        case .active:
            return "\(displayBoard.sideToMove.localizedName) am Zug"
        }
    }

    /// Arrows currently drawn on the board.
    var arrows: [BoardArrow] {
        guard showsArrows else { return [] }
        if let candidate = previewCandidate {
            guard previewMoves.indices.contains(previewPly) else { return [] }
            let move = previewMoves[previewPly]
            return [BoardArrow(from: move.from, to: move.to, kind: .best)]
        }
        let limit = max(1, settings.settings.arrowCount)
        return candidates.prefix(limit).compactMap { candidate in
            let arrow = BoardArrow(from: candidate.move.from,
                                   to: candidate.move.to,
                                   kind: candidate.arrowKind,
                                   label: candidate.score.display)
            return hiddenArrowIDs.contains(arrow.id) ? nil : arrow
        }
    }

    // MARK: - Analysis

    func analyze(debounce: Bool = false) {
        analysisTask?.cancel()
        analysisTask = nil
        generation += 1
        let currentGeneration = generation

        guard settings.settings.engineEnabled else {
            isAnalyzing = false
            candidates = []
            statusMessage = "Engine deaktiviert – Analyse pausiert."
            return
        }

        let position = board
        let engine = activeEngine
        let limits = settings.settings.limits
        engineName = engine.displayName
        configure(engine)

        isAnalyzing = true
        statusMessage = nil
        depth = 0
        seldepth = 0
        nodes = 0

        analysisTask = Task { [weak self] in
            guard let self = self else { return }
            if debounce {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if Task.isCancelled { return }
            }
            for await update in engine.analyze(fen: position.fen, limits: limits) {
                if Task.isCancelled { break }
                self.consume(update: update, position: position, generation: currentGeneration)
                if update.isFinal { break }
            }
            self.finish(generation: currentGeneration)
        }
    }

    func stop() {
        analysisTask?.cancel()
        analysisTask = nil
        activeEngine.stop()
        isAnalyzing = false
    }

    private func configure(_ engine: ChessEngine) {
        let settings = self.settings.settings
        engine.setOption("Threads", value: "\(settings.effectiveThreads)")
        engine.setOption("Hash", value: "\(max(16, settings.hashMB))")
        engine.setOption("MultiPV", value: "\(max(1, settings.multiPV))")
        engine.setOption("UCI_LimitStrength", value: "false")
    }

    private func consume(update: EngineUpdate, position: Board, generation: Int) {
        guard generation == self.generation else { return }
        depth = max(depth, update.depth)
        seldepth = max(seldepth, update.seldepth)
        nodes = max(nodes, update.nodes)

        guard let best = update.lines.first else { return }
        evaluation = best.score
        candidates = buildCandidates(from: update, position: position)
        if update.isFinal { isAnalyzing = false }
    }

    private func finish(generation: Int) {
        guard generation == self.generation else { return }
        isAnalyzing = false
        if candidates.isEmpty, statusMessage == nil {
            statusMessage = "Keine Analyse verfügbar."
        }
    }

    private func buildCandidates(from update: EngineUpdate, position: Board) -> [CandidateMove] {
        guard let bestScore = update.lines.first?.score else { return [] }
        var result: [CandidateMove] = []
        for line in update.lines {
            guard let move = line.firstMove else { continue }
            guard position.isLegal(move) else { continue }
            let features = MoveFeatures.make(for: move, on: position)
            let quality = MoveQuality.classify(best: bestScore, candidate: line.score)
            let fit = NaturalMoveSelector.styleFit(style: style,
                                                  features: features,
                                                  quality: quality,
                                                  score: line.score,
                                                  bestScore: bestScore)
            result.append(CandidateMove(rank: line.rank,
                                        move: move,
                                        san: position.san(for: move),
                                        score: line.score,
                                        pvUCI: line.pv,
                                        pvSAN: position.sanSequence(fromUCI: line.pv),
                                        quality: quality,
                                        features: features,
                                        styleFit: fit,
                                        tags: NaturalMoveSelector.tags(for: features, quality: quality),
                                        depth: line.depth))
        }
        return result
    }

    // MARK: - Style

    func apply(style newStyle: MoveStyle) {
        style = newStyle
        guard let bestScore = candidates.first?.score else { return }
        candidates = candidates.map { candidate in
            var updated = candidate
            updated.styleFit = NaturalMoveSelector.styleFit(style: newStyle,
                                                           features: candidate.features,
                                                           quality: candidate.quality,
                                                           score: candidate.score,
                                                           bestScore: bestScore)
            return updated
        }
    }

    /// Candidates ordered by the selected style (best engine move stays first).
    var styleRankedCandidates: [CandidateMove] {
        guard let first = candidates.first else { return [] }
        let rest = candidates.dropFirst().sorted { $0.styleFit > $1.styleFit }
        return [first] + rest
    }

    // MARK: - Board interaction

    func play(_ move: Move) {
        guard board.isLegal(move) else { return }
        clearPreview()
        let san = board.san(for: move)
        history.append(HistoryEntry(board: board, move: move, san: san))
        board.apply(move)
        lastMove = move
        moveLog = history.map { $0.san }
        sessionMoves.append(PGNMove(san: san, uci: move.uci))
        statusMessage = nil

        if settings.settings.autoAnalyze {
            analyze(debounce: false)
        } else {
            candidates = []
            isAnalyzing = false
        }
    }

    /// Plays the engine's best move (used by the "best move" button).
    func playBestMove() {
        guard let best = candidates.first else { return }
        play(best.move)
    }

    func undo() {
        guard let entry = history.popLast() else { return }
        clearPreview()
        board = entry.board
        lastMove = history.last?.move
        moveLog = history.map { $0.san }
        if !sessionMoves.isEmpty { sessionMoves.removeLast() }
        analyze(debounce: false)
    }

    func reset() {
        clearPreview()
        board = Board()
        history = []
        moveLog = []
        sessionMoves = []
        sessionStartFEN = Board.startFEN
        lastMove = nil
        candidates = []
        evaluation = .zero
        depth = 0
        nodes = 0
        analyze(debounce: false)
    }

    func setBoard(_ newBoard: Board) {
        clearPreview()
        board = newBoard
        history = []
        moveLog = []
        sessionMoves = []
        sessionStartFEN = newBoard.fen
        lastMove = nil
        depth = 0
        nodes = 0
        evaluateIfEnabled()
    }

    func setFEN(_ fen: String) throws {
        guard let newBoard = Board(fen: fen) else {
            throw PGNError.invalidFEN(fen)
        }
        setBoard(newBoard)
    }

    func load(game: PGNGame) {
        clearPreview()
        let startBoard = game.startBoard
        board = startBoard
        history = []
        moveLog = []
        sessionMoves = []
        sessionStartFEN = game.startFEN
        lastMove = nil

        var current = startBoard
        for move in game.moves {
            guard let parsed = Move(uci: move.uci), current.isLegal(parsed) else { break }
            let san = current.san(for: parsed)
            history.append(HistoryEntry(board: current, move: parsed, san: san))
            current.apply(parsed)
            sessionMoves.append(move)
        }
        board = current
        lastMove = history.last?.move
        moveLog = history.map { $0.san }
        evaluateIfEnabled()
    }

    /// Jumps to the position after `ply` moves of the current session.
    func jump(toPly ply: Int) {
        clearPreview()
        let clamped = max(0, min(ply, history.count))
        board = clamped == 0 ? (Board(fen: sessionStartFEN) ?? Board()) : history[clamped - 1].board.applying(history[clamped - 1].move)
        lastMove = clamped == 0 ? nil : history[clamped - 1].move
        moveLog = Array(history.prefix(clamped).map { $0.san })
        analyze(debounce: false)
    }

    func flip() {
        isFlipped.toggle()
    }

    private func evaluateIfEnabled() {
        if settings.settings.engineEnabled && settings.settings.autoAnalyze {
            analyze(debounce: false)
        } else {
            candidates = []
            isAnalyzing = false
        }
    }

    // MARK: - Variation preview

    func preview(_ candidate: CandidateMove) {
        clearPreview()
        previewCandidate = candidate
        previewMoves = candidate.pvUCI.compactMap(Move.init(uci:))
        previewBoards = board.boards(fromUCI: candidate.pvUCI)
        previewPly = 0
    }

    func previewStep(_ delta: Int) {
        guard isPreviewing else { return }
        let maximum = max(0, previewBoards.count - 1)
        previewPly = max(0, min(previewPly + delta, maximum))
    }

    func previewToEnd() {
        guard isPreviewing else { return }
        previewPly = max(0, previewBoards.count - 1)
    }

    func clearPreview() {
        previewCandidate = nil
        previewBoards = []
        previewMoves = []
        previewPly = 0
    }

    // MARK: - Arrows

    func toggleArrow(_ arrow: BoardArrow) {
        if hiddenArrowIDs.contains(arrow.id) {
            hiddenArrowIDs.remove(arrow.id)
        } else {
            hiddenArrowIDs.insert(arrow.id)
        }
    }

    func showAllArrows() {
        hiddenArrowIDs.removeAll()
        showsArrows = true
    }

    // MARK: - Persistence

    func saveCurrentAnalysis(into store: AnalysisStore) {
        let title: String
        if sessionMoves.isEmpty {
            title = "Stellung \(String(board.fen.prefix(24)))"
        } else {
            title = sessionMoves.prefix(6).map { $0.san }.joined(separator: " ")
        }
        let record = AnalysisRecord(id: UUID().uuidString,
                                    title: title,
                                    fen: board.fen,
                                    createdAt: Date(),
                                    summary: "\(evaluation.display) · Tiefe \(depth) · \(engineName)",
                                    pgn: PGN.export(startFEN: sessionStartFEN,
                                                    moves: sessionMoves,
                                                    headers: ["Event": "CHESS ENGINE PRO Analyse"],
                                                    result: board.status.resultString),
                                    moveCount: sessionMoves.count,
                                    evaluatedBy: engineName)
        store.save(record)
    }

    var currentPGN: String {
        PGN.export(startFEN: sessionStartFEN,
                   moves: sessionMoves,
                   headers: ["Event": "CHESS ENGINE PRO Analyse"],
                   result: board.status.resultString)
    }
}
