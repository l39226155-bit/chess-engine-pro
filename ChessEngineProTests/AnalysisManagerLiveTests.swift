//
//  AnalysisManagerLiveTests.swift
//  CHESS ENGINE PRO
//
//  End-to-end tests of the detection pipeline: what reaches the board, what
//  reaches the engine, and what is refused. The built-in engine keeps the tests
//  independent of Stockfish.
//

import XCTest
@testable import ChessEnginePro

@MainActor
final class AnalysisManagerLiveTests: XCTestCase {

    private func makeManager() -> AnalysisManager {
        let settings = SettingsStore()
        settings.settings.engineEnabled = true
        settings.settings.autoAnalyze = true
        settings.settings.backend = .builtIn
        settings.settings.useTimeLimit = false
        settings.settings.depth = 2
        settings.settings.multiPV = 2
        settings.settings.style = .balanced
        return AnalysisManager(settings: settings, engines: EngineManager(settings: settings))
    }

    private func detected(_ board: Board,
                          san: [String] = [],
                          uci: [String] = [],
                          isGameOver: Bool = false,
                          boardID: String = "board-1") -> DetectedPosition {
        DetectedPosition(board: board,
                         moveList: san,
                         uciMoves: uci,
                         lastMove: nil,
                         isGameOver: isGameOver,
                         userColor: .white,
                         boardID: boardID,
                         origin: .history,
                         validation: PositionValidation.validate(board),
                         confidence: .exact)
    }

    private func positionAfterE4() -> (board: Board, san: [String], uci: [String]) {
        var board = Board()
        guard let move = board.move(from: Square(name: "e2")!, to: Square(name: "e4")!) else {
            return (board, [], [])
        }
        let san = board.san(for: move)
        board.apply(move)
        return (board, [san], [move.uci])
    }

    private func positionAfterE4AndE5() -> (board: Board, san: [String], uci: [String]) {
        let e4 = positionAfterE4()
        var board = e4.board
        guard let reply = board.move(from: Square(name: "e7")!, to: Square(name: "e5")!) else {
            return (board, e4.san, e4.uci)
        }
        let replySAN = board.san(for: reply)
        board.apply(reply)
        return (board, e4.san + [replySAN], e4.uci + [reply.uci])
    }

    private func waitForAnalysis(_ manager: AnalysisManager, timeout: TimeInterval = 8) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !manager.candidates.isEmpty { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    // MARK: - Engine hand-off

    func testDetectedPositionStartsTheEngine() async {
        let manager = makeManager()
        let e4 = positionAfterE4()

        manager.ingest(detected(e4.board, san: e4.san, uci: e4.uci),
                       sequence: 1,
                       session: "session-1")

        XCTAssertEqual(manager.board.fen, e4.board.fen)
        XCTAssertEqual(manager.liveSource, .chessCom)

        let started = await waitForAnalysis(manager)
        XCTAssertTrue(started, "Die Engine lieferte keine Varianten")
        for candidate in manager.candidates {
            XCTAssertTrue(manager.board.isLegal(candidate.move), candidate.san)
        }
        manager.stop()
    }

    func testRunningGameIsAnalysedWhileItIsMirrored() async {
        let manager = makeManager()
        let e4 = positionAfterE4()

        // Training and games against the computer: the engine runs while the
        // position is mirrored.
        manager.ingest(detected(e4.board, san: e4.san, uci: e4.uci, isGameOver: false),
                       sequence: 1,
                       session: "session-1")

        XCTAssertEqual(manager.board.fen, e4.board.fen)
        let analysed = await waitForAnalysis(manager)
        XCTAssertTrue(analysed, "Die Engine lief nicht für die laufende Stellung")
        manager.stop()
    }

    func testRapidUpdatesAnalyseOnlyTheLatestPosition() async {
        let manager = makeManager()
        let e4 = positionAfterE4()
        let e5 = positionAfterE4AndE5()

        manager.ingest(detected(e4.board, san: e4.san, uci: e4.uci),
                       sequence: 1,
                       session: "session-1")
        manager.ingest(detected(e5.board, san: e5.san, uci: e5.uci),
                       sequence: 2,
                       session: "session-1")

        let analysed = await waitForAnalysis(manager)
        XCTAssertTrue(analysed, "Die Engine lief nicht für die letzte Stellung")
        XCTAssertEqual(manager.board.fen, e5.board.fen)
        XCTAssertEqual(manager.liveSync.snapshot?.ply, 2)
        for candidate in manager.candidates {
            XCTAssertTrue(e5.board.isLegal(candidate.move), candidate.san)
        }
        manager.stop()
    }

    // MARK: - Guard rails

    func testInvalidDetectionNeverReachesTheBoard() {
        let manager = makeManager()
        let start = manager.board

        manager.ingest(detected(Board.empty),
                       sequence: 1,
                       session: "session-1")

        XCTAssertEqual(manager.board.fen, start.fen)
        XCTAssertEqual(manager.syncStats.rejected, 1)
        XCTAssertTrue(manager.candidates.isEmpty)
        XCTAssertFalse(manager.isAnalyzing)
    }

    func testStaleSequenceCannotReplaceANewerPosition() {
        let manager = makeManager()
        let e4 = positionAfterE4()

        manager.ingest(detected(e4.board, san: e4.san, uci: e4.uci),
                       sequence: 5,
                       session: "session-1")
        manager.ingest(detected(Board()),
                       sequence: 4,
                       session: "session-1")

        XCTAssertEqual(manager.board.fen, e4.board.fen)
        XCTAssertEqual(manager.syncStats.stale, 1)
        manager.stop()
    }

    func testReloadedPageIsRebasedInsteadOfRejected() {
        let manager = makeManager()
        let e4 = positionAfterE4()
        let e5 = positionAfterE4AndE5()

        manager.ingest(detected(e4.board, san: e4.san, uci: e4.uci),
                       sequence: 40,
                       session: "session-1")
        let before = manager.liveSync.version

        // New page session with a counter that starts at 1 again.
        manager.ingest(detected(e5.board, san: e5.san, uci: e5.uci),
                       sequence: 1,
                       session: "session-2")

        XCTAssertEqual(manager.board.fen, e5.board.fen)
        XCTAssertGreaterThan(manager.liveSync.version, before)
        XCTAssertEqual(manager.syncStats.stale, 0)
        manager.stop()
    }

    func testNewDetectedGameReplacesTheMirroredBoard() {
        let manager = makeManager()
        let e4 = positionAfterE4()

        manager.ingest(detected(e4.board, san: e4.san, uci: e4.uci, boardID: "game-1"),
                       sequence: 1,
                       session: "session-1")
        XCTAssertEqual(manager.board.fen, e4.board.fen)

        manager.ingest(detected(Board(), boardID: "game-2"),
                       sequence: 2,
                       session: "session-1")

        XCTAssertEqual(manager.board.fen, Board.startFEN)
        manager.stop()
    }
}
