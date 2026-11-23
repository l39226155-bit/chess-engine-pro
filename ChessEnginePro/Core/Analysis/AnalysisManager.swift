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
    /// Plain German explanation derived from the features of this line.
    var explanation: String

    var id: Int { rank }

    var roleTitle: String { StrategicExplainer.roleTitle(rank: rank) }

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

    // Live position synchronisation: only validated snapshots reach the engine.
    @Published private(set) var liveSnapshot: PositionSnapshot?
    @Published private(set) var liveValidation = PositionValidation.valid
    @Published private(set) var liveChangeCount: Int = 0
    @Published private(set) var analysisProgress: Double = 0
    @Published private(set) var targetDepth: Int = 0

    // Detection pipeline state (Chess.com live positions).
    @Published private(set) var liveEvent: PositionEvent?
    @Published private(set) var liveSource: PositionSource = .local
    @Published private(set) var syncStats = SyncStatistics()
    @Published private(set) var liveBoardID: String?
    @Published private(set) var lastDetectedMoves: [String] = []
    @Published private(set) var lastDetectionOrigin: DetectionOrigin?
    /// Set while a running online game must not be analysed (fair play).
    @Published private(set) var engineBlockedReason: String?
    /// Why the engine may run, e.g. "Analysebrett" or "Partie beendet".
    @Published private(set) var liveContextLabel: String?

    // Preview (stepping through a variation)
    @Published private(set) var previewCandidate: CandidateMove?
    @Published private(set) var previewBoards: [Board] = []
    @Published private(set) var previewMoves: [Move] = []
    @Published private(set) var previewPly: Int = 0

    @Published var style: MoveStyle

    // MARK: - Dependencies

    private let settings: SettingsStore
    private let engines: EngineManager
    let liveSync = LivePositionSync()
    private var analysisTask: Task<Void, Never>?
    private var generation = 0
    private var resumePending = false

    /// Depth ceiling used while the app is not showing the analysis screen.
    /// Keeps live analysis responsive instead of maxing out the CPU during play.
    var liveDepthCap: Int?
    private var liveSession: String?
    private var externalBase = 0
    private var lastPayloadSequence = 0

    init(settings: SettingsStore, engines: EngineManager) {
        self.settings = settings
        self.engines = engines
        self.style = settings.settings.style
    }

    // MARK: - Derived state

    var activeEngine: ChessEngine { engines.engine }

    var usesStockfish: Bool { engines.usesStockfish }

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
        if previewCandidate != nil {
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

    func analyze(debounce: Bool = false, depthCap: Int? = nil) {
        analysisTask?.cancel()
        analysisTask = nil
        generation += 1
        let currentGeneration = generation

        // Never calculate for a running online game, even when the analysis
        // screen asks for it.
        if let reason = engineBlockedReason {
            engines.stop()
            isAnalyzing = false
            candidates = []
            analysisProgress = 0
            statusMessage = reason
            return
        }

        guard settings.settings.engineEnabled else {
            isAnalyzing = false
            candidates = []
            statusMessage = "Engine deaktiviert – Analyse pausiert."
            return
        }

        let position = board
        let validation = PositionValidation.validate(position)
        guard validation.isValid else {
            isAnalyzing = false
            candidates = []
            analysisProgress = 0
            statusMessage = "Stellung ungültig – Analyse abgebrochen."
            return
        }
        syncLivePosition(reason: .edit)

        let engine = activeEngine
        let base = settings.settings.limits
        let limits: EngineLimits
        if let cap = depthCap, !settings.settings.useTimeLimit {
            limits = EngineLimits.depth(min(base.depth, max(1, cap)), multiPV: base.multiPV)
        } else {
            limits = base
        }
        engineName = engine.displayName
        targetDepth = settings.settings.useTimeLimit ? 0 : max(1, limits.depth)
        analysisProgress = 0
        engines.configure()

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
        // Invalidate any update that is already in flight, so a cancelled
        // search can never publish results for a position that is gone.
        generation += 1
        engines.stop()
        isAnalyzing = false
        analysisProgress = 0
    }

    /// iOS suspends the app: stop calculating, remember to continue later.
    func pauseForBackground() {
        resumePending = isAnalyzing
        stop()
        if resumePending {
            statusMessage = "Analyse pausiert – App im Hintergrund."
        }
    }

    func resumeAfterBackground() {
        guard resumePending else { return }
        resumePending = false
        statusMessage = nil
        if settings.settings.engineEnabled { analyze() }
    }

    /// Validates the current board and mirrors it into the live synchroniser.
    private func syncLivePosition(reason: PositionSnapshot.ChangeReason,
                                  before: Board? = nil,
                                  move: Move? = nil) {
        liveSync.publish(board: board,
                         lastMove: lastMove,
                         sanHistory: moveLog,
                         reason: reason,
                         before: before,
                         move: move)
        liveSnapshot = liveSync.snapshot
        liveValidation = liveSync.validation
        liveChangeCount = liveSync.changeCount
        syncStats = liveSync.stats
        liveSource = liveSync.snapshot?.source ?? .local
        liveEvent = liveSync.events.last
    }

    // MARK: - Chess.com live detection

    /// Receives a verified position detected on the Chess.com page.
    ///
    /// The synchroniser drops duplicated, stale and invalid updates; only a
    /// newly accepted, valid position may touch the board or the engine. The
    /// fair play policy decides whether the engine may run for this page at
    /// all - a running online game is mirrored but never analysed.
    func ingest(_ detected: DetectedPosition,
                sequence: Int? = nil,
                session: String? = nil) {
        lastDetectionOrigin = detected.origin

        let sessionChanged = session != nil && session != liveSession
        if let session = session { liveSession = session }

        var incomingSequence: Int?
        if let sequence = sequence {
            // The page restarts its counter after a reload. Rebase it onto the
            // synchroniser's version so the sequence stays strictly monotonic
            // while late payloads from the old page are still rejected.
            if sessionChanged || (session == nil && sequence < lastPayloadSequence) {
                externalBase = liveSync.version
                lastPayloadSequence = 0
            }
            lastPayloadSequence = max(lastPayloadSequence, sequence)
            incomingSequence = externalBase + sequence
        }

        let boardChanged = liveBoardID != nil && liveBoardID != detected.boardID
        let explicit: SyncEventKind? = boardChanged
            ? (detected.moveList.isEmpty ? .newGame : .positionLoaded)
            : nil

        let accepted = liveSync.publish(board: detected.board,
                                        lastMove: detected.lastMove,
                                        sanHistory: detected.moveList,
                                        reason: .detected,
                                        source: .chessCom,
                                        externalVersion: incomingSequence,
                                        explicitEvent: explicit,
                                        userColor: detected.userColor,
                                        gameOverOverride: detected.isGameOver,
                                        confidence: detected.confidence)

        liveSnapshot = liveSync.snapshot
        liveValidation = liveSync.validation
        liveChangeCount = liveSync.changeCount
        syncStats = liveSync.stats
        liveEvent = liveSync.events.last
        liveSource = liveSync.snapshot?.source ?? liveSource

        guard accepted, liveSync.validation.isValid else { return }

        let permission = LiveAnalysisPolicy.permission(url: detected.url,
                                                       isGameOver: detected.isGameOver)
        liveContextLabel = permission.contextLabel
        engineBlockedReason = permission.blockedReason

        clearPreview()
        // Results of the previous position must never stay on screen for the
        // new one, not even for the few milliseconds before the engine answers.
        candidates = []
        evaluation = .zero
        depth = 0
        seldepth = 0
        nodes = 0
        analysisProgress = 0
        // Rebuild the local history from the verified move list so jump and the
        // move list chips keep working on a mirrored game.
        var rebuilt: [HistoryEntry] = []
        var walker = Board()
        for uci in detected.uciMoves {
            guard let parsed = Move(uci: uci), walker.isLegal(parsed) else { break }
            let san = walker.san(for: parsed)
            rebuilt.append(HistoryEntry(board: walker, move: parsed, san: san))
            walker.apply(parsed)
        }
        history = rebuilt
        board = detected.board
        lastMove = detected.lastMove
        moveLog = detected.moveList
        sessionMoves = Array(zip(detected.moveList, detected.uciMoves)).map {
            PGNMove(san: $0.0, uci: $0.1)
        }
        sessionStartFEN = Board.startFEN
        liveBoardID = detected.boardID
        lastDetectedMoves = Array(detected.moveList.suffix(6))
        statusMessage = nil

        if let reason = engineBlockedReason {
            // Fair play: cancel any running search, keep the mirrored board
            // passive and explain why.
            stop()
            statusMessage = reason
            return
        }

        if settings.settings.engineEnabled && settings.settings.autoAnalyze {
            analyze(debounce: true, depthCap: liveDepthCap)
        } else {
            candidates = []
            isAnalyzing = false
        }
    }

    /// Leaves the fair play guard because the board belongs to the user again.
    private func releaseLiveGuard() {
        engineBlockedReason = nil
        liveContextLabel = nil
        liveBoardID = nil
    }

    private func consume(update: EngineUpdate, position: Board, generation: Int) {
        guard generation == self.generation else { return }
        depth = max(depth, update.depth)
        seldepth = max(seldepth, update.seldepth)
        nodes = max(nodes, update.nodes)

        if targetDepth > 0 {
            analysisProgress = min(1, Double(update.depth) / Double(targetDepth))
        } else if let milliseconds = settings.settings.limits.moveTimeMs, milliseconds > 0 {
            analysisProgress = min(1, Double(update.timeMs) / Double(milliseconds))
        }

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
                                        depth: line.depth,
                                        explanation: StrategicExplainer.explain(features: features,
                                                                               quality: quality,
                                                                               score: line.score,
                                                                               best: bestScore)))
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
        releaseLiveGuard()
        clearPreview()
        let before = board
        let san = board.san(for: move)
        history.append(HistoryEntry(board: before, move: move, san: san))
        board.apply(move)
        lastMove = move
        moveLog = history.map { $0.san }
        sessionMoves.append(PGNMove(san: san, uci: move.uci))
        statusMessage = nil
        syncLivePosition(reason: .move, before: before, move: move)

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
        syncLivePosition(reason: .undo)
        analyze(debounce: false)
    }

    func reset() {
        clearPreview()
        releaseLiveGuard()
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
        syncLivePosition(reason: .reset)
        analyze(debounce: false)
    }

    func setBoard(_ newBoard: Board) {
        clearPreview()
        releaseLiveGuard()
        board = newBoard
        history = []
        moveLog = []
        sessionMoves = []
        sessionStartFEN = newBoard.fen
        lastMove = nil
        depth = 0
        nodes = 0
        syncLivePosition(reason: .edit)
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
        releaseLiveGuard()
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
        syncLivePosition(reason: .imported)
        evaluateIfEnabled()
    }

    /// Jumps to the position after `ply` moves of the current session.
    func jump(toPly ply: Int) {
        clearPreview()
        let clamped = max(0, min(ply, history.count))
        board = clamped == 0 ? (Board(fen: sessionStartFEN) ?? Board()) : history[clamped - 1].board.applying(history[clamped - 1].move)
        lastMove = clamped == 0 ? nil : history[clamped - 1].move
        moveLog = Array(history.prefix(clamped).map { $0.san })
        syncLivePosition(reason: .jump)
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
