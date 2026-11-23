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

    private let analysisURL = "https://www.chess.com/analysis"
    private let liveGameURL = "https://www.chess.com/game/live/1"

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
                          url: String,
                          isGameOver: Bool = false,
                          boardID: String = "board-1") -> DetectedPosition {
        DetectedPosition(board: board,
                         moveList: san,
                         uciMoves: uci,
                         lastMove: nil,
                         isGameOver: isGameOver,
                         userColor: .white,
                         boardID: boardID,
                         url: url,
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

    private func waitForAnalysis(_ manager: AnalysisManager, timeout: TimeInterval = 8) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !manager.candidates.isEmpty { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    // MARK: - Fair play

    func testRunningOnlineGameIsMirroredWithoutAnyEngineWork() {
        let manager = makeManager()
        let e4 = positionAfterE4()

        manager.ingest(detected(e4.board, san: e4.san, uci: e4.uci, url: liveGameURL),
                       sequence: 1,
                       session: "session-1")

        XCTAssertEqual(manager.board.fen, e4.board.fen)
        XCTAssertNotNil(manager.engineBlockedReason)
        XCTAssertNil(manager.liveContextLabel)
        XCTAssertFalse(manager.isAnalyzing)
        XCTAssertTrue(manager.candidates.isEmpty)

        // The analysis screen must not bypass the guard either.
        manager.analyze()
        XCTAssertFalse(manager.isAnalyzing)
        XCTAssertTrue(manager.candidates.isEmpty)
        XCTAssertNotNil(manager.statusMessage)
        manager.stop()
    }

    func testFinishedGameOnAGamePageIsAnalysed() async {
        let manager = makeManager()
        let e4 = positionAfterE4()

        manager.ingest(detected(e4.board, san: e4.san, uci: e4.uci, url: liveGameURL, isGameOver: true),
                       sequence: 1,
                       session: "session-1")

        XCTAssertNil(manager.engineBlockedReason)
        XCTAssertEqual(manager.liveContextLabel, "Partie beendet")
        let analysed = await waitForAnalysis(manager)
        XCTAssertTrue(analysed, "Die Engine lief nicht für die beendete Partie")
        manager.stop()
    }

    func testLocalBoardReleasesTheFairPlayGuard() {
        let manager = makeManager()
        let e4 = positionAfterE4()
        manager.ingest(detected(e4.board, san: e4.san, uci: e4.uci, url: liveGameURL),
                       sequence: 1,
                       session: "session-1")
        XCTAssertNotNil(manager.engineBlockedReason)

        manager.reset()
        XCTAssertNil(manager.engineBlockedReason)
        XCTAssertNil(manager.liveContextLabel)
        manager.stop()
    }

    // MARK: - Engine hand-off

    func testAnalysisPageStartsTheEngineForTheDetectedPosition() async {
        let manager = makeManager()
        let e4 = positionAfterE4()

        manager.ingest(detected(e4.board, san: e4.san, uci: e4.uci, url: analysisURL),
                       sequence: 1,
                       session: "session-1")

        XCTAssertNil(manager.engineBlockedReason)
        XCTAssertEqual(manager.liveContextLabel, "Analysebrett")
        XCTAssertEqual(manager.board.fen, e4.board.fen)

        let started = await waitForAnalysis(manager)
        XCTAssertTrue(started, "Die Engine lieferte keine Varianten")
        XCTAssertFalse(manager.candidates.isEmpty)
        for candidate in manager.candidates {
            XCTAssertTrue(manager.board.isLegal(candidate.move), candidate.san)
        }
        manager.stop()
    }

    func testRapidUpdatesAnalyseOnlyTheLatestPosition() async {
        let manager = makeManager()
        let e4 = positionAfterE4()

        var second = e4.board
        guard let reply = second.move(from: Square(name: "e7")!, to: Square(name: "e5")!) else {
            return XCTFail("e7e5 nicht gefunden")
        }
        let replySAN = second.san(for: reply)
        second.apply(reply)

        manager.ingest(detected(e4.board, san: e4.san, uci: e4.uci, url: analysisURL),
                       sequence: 1,
                       session: "session-1")
        manager.ingest(detected(second,
                                san: e4.san + [replySAN],
                                uci: e4.uci + [reply.uci],
                                url: analysisURL),
                       sequence: 2,
                       session: "session-1")

        let analysed = await waitForAnalysis(manager)
        XCTAssertTrue(analysed, "Die Engine lief nicht für die letzte Stellung")
        XCTAssertEqual(manager.board.fen, second.fen)
        XCTAssertEqual(manager.liveSync.snapshot?.ply, 2)
        for candidate in manager.candidates {
            XCTAssertTrue(second.isLegal(candidate.move), candidate.san)
        }
        manager.stop()
    }

    func testInvalidDetectionNeverReachesTheBoard() {
        let manager = makeManager()
        let start = manager.board

        manager.ingest(detected(Board.empty, url: analysisURL),
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

        manager.ingest(detected(e4.board, san: e4.san, uci: e4.uci, url: analysisURL),
                       sequence: 5,
                       session: "session-1")
        manager.ingest(detected(Board(), url: analysisURL),
                       sequence: 4,
                       session: "session-1")

        XCTAssertEqual(manager.board.fen, e4.board.fen)
        XCTAssertEqual(manager.syncStats.stale, 1)
        manager.stop()
    }

    func testReloadedPageIsRebasedInsteadOfRejected() {
        let manager = makeManager()
        let e4 = positionAfterE4()

        manager.ingest(detected(e4.board, san: e4.san, uci: e4.uci, url: analysisURL),
                       sequence: 40,
                       session: "session-1")
        let before = manager.liveSync.version

        var second = e4.board
        guard let reply = second.move(from: Square(name: "e7")!, to: Square(name: "e5")!) else {
            return XCTFail("e7e5 nicht gefunden")
        }
        let replySAN = second.san(for: reply)
        second.apply(reply)

        // New page session with a counter that starts at 1 again.
        manager.ingest(detected(second,
                                san: e4.san + [replySAN],
                                uci: e4.uci + [reply.uci],
                                url: analysisURL),
                       sequence: 1,
                       session: "session-2")

        XCTAssertEqual(manager.board.fen, second.fen)
        XCTAssertGreaterThan(manager.liveSync.version, before)
        XCTAssertEqual(manager.syncStats.stale, 0)
        manager.stop()
    }
}
