//
//  AnalysisManagerModeTests.swift
//  CHESS ENGINE PRO
//
//  Mode handling of the detection pipeline: a running game against a human is
//  mirrored but never analysed, a finished game is analysed like any supported
//  mode, and switching into a blocked mode clears the previous results.
//

import XCTest
@testable import ChessEnginePro

@MainActor
final class AnalysisManagerModeTests: XCTestCase {

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

    private func waitForAnalysis(_ manager: AnalysisManager, timeout: TimeInterval = 8) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !manager.candidates.isEmpty { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    // MARK: - Running game against a human

    func testBlockedPositionIsMirroredButNeverAnalysed() async {
        let manager = makeManager()
        let e4 = positionAfterE4()

        manager.ingest(detected(e4.board, san: e4.san, uci: e4.uci),
                       sequence: 1,
                       session: "session-1",
                       allowAnalysis: false)

        // The recognition chain still runs: board, FEN and snapshot are correct.
        XCTAssertEqual(manager.board.fen, e4.board.fen)
        XCTAssertEqual(manager.liveSource, .chessCom)
        XCTAssertEqual(manager.liveSnapshot?.fen, e4.board.fen)
        XCTAssertTrue(manager.liveValidation.isValid)

        // But nothing is calculated.
        XCTAssertFalse(manager.liveAnalysisAllowed)
        XCTAssertTrue(manager.candidates.isEmpty)
        XCTAssertFalse(manager.isAnalyzing)
        XCTAssertEqual(manager.statusMessage, "Laufende Partie gegen einen Menschen – Engine gesperrt.")

        try? await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertTrue(manager.candidates.isEmpty, "Die Engine darf in einer laufenden Partie nicht rechnen")
        XCTAssertFalse(manager.isAnalyzing)
    }

    func testSwitchingIntoABlockedModeRemovesPreviousResults() async {
        let manager = makeManager()
        let e4 = positionAfterE4()

        manager.ingest(detected(e4.board, san: e4.san, uci: e4.uci),
                       sequence: 1,
                       session: "session-1")
        let analysed = await waitForAnalysis(manager)
        XCTAssertTrue(analysed, "Die Engine lief nicht für die freigegebene Stellung")
        XCTAssertFalse(manager.candidates.isEmpty)

        // The next position arrives from a running game against a human.
        var board = e4.board
        guard let reply = board.move(from: Square(name: "e7")!, to: Square(name: "e5")!) else {
            return XCTFail("Teststellung konnte nicht aufgebaut werden")
        }
        let replySAN = board.san(for: reply)
        board.apply(reply)

        manager.ingest(detected(board, san: e4.san + [replySAN], uci: e4.uci + [reply.uci]),
                       sequence: 2,
                       session: "session-1",
                       allowAnalysis: false)

        XCTAssertEqual(manager.board.fen, board.fen)
        XCTAssertTrue(manager.candidates.isEmpty, "Alte Varianten dürfen nicht stehen bleiben")
        XCTAssertFalse(manager.isAnalyzing)
        XCTAssertFalse(manager.liveAnalysisAllowed)
    }

    // MARK: - Finished game

    func testFinishedGameIsAnalysed() async {
        let manager = makeManager()
        let e4 = positionAfterE4()

        manager.ingest(detected(e4.board, san: e4.san, uci: e4.uci, isGameOver: true),
                       sequence: 1,
                       session: "session-1",
                       allowAnalysis: LiveAnalysisPolicy.allowsSuggestions(
                           in: .onlineGame,
                           engineEnabled: true,
                           isGameOver: true))

        XCTAssertTrue(manager.liveAnalysisAllowed)
        XCTAssertEqual(manager.liveSnapshot?.isGameOver, true)

        let analysed = await waitForAnalysis(manager)
        XCTAssertTrue(analysed, "Eine beendete Partie muss analysiert werden")
        for candidate in manager.candidates {
            XCTAssertTrue(manager.board.isLegal(candidate.move), candidate.san)
        }
        manager.stop()
    }
}
