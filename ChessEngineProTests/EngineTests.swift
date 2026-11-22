//
//  EngineTests.swift
//  CHESS ENGINE PRO
//
//  Engine transport, fallback search and persistence tests.
//

import XCTest
@testable import ChessEnginePro

final class EngineTests: XCTestCase {

    func testFallbackEngineProducesLegalAnalysis() async {
        let engine = FallbackEngine()
        var finalUpdate: EngineUpdate?
        for await update in engine.analyze(fen: Board.startFEN,
                                           limits: EngineLimits.depth(3, multiPV: 3)) {
            finalUpdate = update
            if update.isFinal { break }
        }

        guard let update = finalUpdate else {
            return XCTFail("Keine Engine-Antwort")
        }
        XCTAssertFalse(update.lines.isEmpty)
        XCTAssertLessThanOrEqual(update.lines.count, 3)
        XCTAssertEqual(update.lines.first?.rank, 1)

        let board = Board()
        if let best = update.bestMove {
            XCTAssertTrue(board.isLegal(best))
        }
        for line in update.lines {
            XCTAssertFalse(line.pv.isEmpty)
            XCTAssertFalse(board.sanSequence(fromUCI: line.pv).isEmpty)
        }
    }

    func testFallbackEngineFindsMateInOne() async {
        // White: Kg1, Ra1; Black: Kh8, pawns g7/h7. Ra8 is back rank mate.
        guard let board = Board(fen: "7k/6pp/8/8/8/8/8/R5K1 w - - 0 1") else {
            return XCTFail("FEN ungültig")
        }
        let engine = FallbackEngine()
        var best: Move?
        for await update in engine.analyze(fen: board.fen, limits: .depth(3, multiPV: 1)) {
            if update.isFinal {
                best = update.bestMove ?? update.lines.first?.firstMove
                break
            }
        }
        guard let move = best else { return XCTFail("Keine Antwort") }
        let reply = board.applying(move)
        XCTAssertEqual(reply.status, .checkmate(winner: .white))
    }

    func testStockfishBridgeIfAvailable() async throws {
        try XCTSkipUnless(StockfishBuild.isLinked, "Stockfish ist in diesem Build nicht eingebunden")

        let engine = StockfishEngine.shared
        engine.setOption("MultiPV", value: "2")
        var finalUpdate: EngineUpdate?
        for await update in engine.analyze(fen: Board.startFEN, limits: .depth(8, multiPV: 2)) {
            finalUpdate = update
            if update.isFinal { break }
        }
        guard let update = finalUpdate else {
            return XCTFail("Stockfish lieferte keine Antwort")
        }
        XCTAssertFalse(update.lines.isEmpty)
        XCTAssertNotNil(update.bestMove)
        if let move = update.bestMove {
            XCTAssertTrue(Board().isLegal(move))
        }
    }

    func testAnalysisStoreRoundTrip() {
        let store = AnalysisStore.shared
        let record = AnalysisRecord(id: UUID().uuidString,
                                    title: "Unit-Test",
                                    fen: Board.startFEN,
                                    createdAt: Date(),
                                    summary: "+0.00 · Tiefe 1",
                                    pgn: nil,
                                    moveCount: 0,
                                    evaluatedBy: "Test")
        store.save(record)
        XCTAssertTrue(store.records(limit: 500).contains { $0.id == record.id })
        store.delete(id: record.id)
        XCTAssertFalse(store.records(limit: 500).contains { $0.id == record.id })
    }

    @MainActor
    func testAnalysisManagerPlaysMoves() async {
        let settings = SettingsStore()
        settings.settings.autoAnalyze = false
        settings.settings.engineEnabled = true
        settings.settings.backend = .builtIn

        let manager = AnalysisManager(settings: settings)
        guard let e2e4 = manager.board.move(from: Square(name: "e2")!, to: Square(name: "e4")!) else {
            return XCTFail("Zug e2e4 nicht gefunden")
        }
        manager.play(e2e4)
        XCTAssertEqual(manager.board.sideToMove, .black)
        XCTAssertEqual(manager.moveLog, ["e4"])

        manager.undo()
        XCTAssertEqual(manager.board.sideToMove, .white)
        XCTAssertTrue(manager.moveLog.isEmpty)
    }
}
