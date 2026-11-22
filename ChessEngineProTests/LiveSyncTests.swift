//
//  LiveSyncTests.swift
//  CHESS ENGINE PRO
//
//  Tests for the validated position pipeline that feeds Stockfish.
//

import XCTest
@testable import ChessEnginePro

final class LiveSyncTests: XCTestCase {

    private func play(_ board: Board,
                      _ from: String,
                      _ to: String,
                      _ promotion: PieceKind? = nil) throws -> (before: Board, move: Move, after: Board) {
        let origin = try XCTUnwrap(Square(name: from))
        let target = try XCTUnwrap(Square(name: to))
        let move = try XCTUnwrap(board.move(from: origin, to: target, promotion: promotion),
                                "Illegaler Zug \(from)\(to)")
        return (board, move, board.applying(move))
    }

    // MARK: - Publishing

    func testMoveIsPublishedWithSideToMoveAndPly() throws {
        let sync = LivePositionSync()
        let step = try play(Board(), "e2", "e4")

        XCTAssertTrue(sync.publish(board: step.after,
                                   lastMove: step.move,
                                   sanHistory: ["e4"],
                                   reason: .move,
                                   before: step.before,
                                   move: step.move))

        let snapshot = try XCTUnwrap(sync.snapshot)
        XCTAssertEqual(snapshot.sideToMove, .black)
        XCTAssertEqual(snapshot.ply, 1)
        XCTAssertEqual(snapshot.lastSAN, "e4")
        XCTAssertEqual(snapshot.moveKind, .doublePawnPush)
        XCTAssertFalse(snapshot.isGameOver)
        XCTAssertTrue(sync.validation.isValid)
        XCTAssertEqual(sync.changeCount, 1)
    }

    func testUnchangedPositionIsNotRepublished() throws {
        let sync = LivePositionSync()
        let step = try play(Board(), "d2", "d4")

        XCTAssertTrue(sync.publish(board: step.after, lastMove: step.move, sanHistory: ["d4"], reason: .move,
                                   before: step.before, move: step.move))
        XCTAssertFalse(sync.publish(board: step.after, lastMove: step.move, sanHistory: ["d4"], reason: .move,
                                    before: step.before, move: step.move))
        XCTAssertEqual(sync.changeCount, 1)
        XCTAssertEqual(sync.receivedCount, 2)
    }

    func testFullMoveSequenceKeepsHistory() throws {
        let sync = LivePositionSync()
        var board = Board()
        var history: [String] = []

        for (from, to) in [("e2", "e4"), ("e7", "e5")] {
            let step = try play(board, from, to)
            history.append(board.san(for: step.move))
            board = step.after
            sync.publish(board: board, lastMove: step.move, sanHistory: history, reason: .move,
                         before: step.before, move: step.move)
        }

        let snapshot = try XCTUnwrap(sync.snapshot)
        XCTAssertEqual(snapshot.ply, 2)
        XCTAssertEqual(snapshot.sanHistory, ["e4", "e5"])
        XCTAssertEqual(snapshot.sideToMove, .white)
    }

    // MARK: - Classification

    func testCastlingIsClassified() throws {
        let board = try XCTUnwrap(Board(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"))
        let kingSide = try play(board, "e1", "g1")
        XCTAssertEqual(LivePositionSync.moveKind(before: kingSide.before,
                                                 move: kingSide.move,
                                                 after: kingSide.after), .castleKingSide)

        let queenSide = try play(board, "e1", "c1")
        XCTAssertEqual(LivePositionSync.moveKind(before: queenSide.before,
                                                 move: queenSide.move,
                                                 after: queenSide.after), .castleQueenSide)
    }

    func testPromotionIsClassified() throws {
        let board = try XCTUnwrap(Board(fen: "8/P7/8/8/8/8/8/K6k w - - 0 1"))
        let step = try play(board, "a7", "a8", .queen)
        XCTAssertEqual(LivePositionSync.moveKind(before: step.before,
                                                 move: step.move,
                                                 after: step.after), .promotion(.queen))
        XCTAssertEqual(step.after[try XCTUnwrap(Square(name: "a8"))]?.kind, .queen)
    }

    func testEnPassantIsClassified() throws {
        let board = try XCTUnwrap(Board(fen: "8/8/8/3pP3/8/8/8/K6k w - d6 0 1"))
        let step = try play(board, "e5", "d6")
        XCTAssertEqual(LivePositionSync.moveKind(before: step.before,
                                                 move: step.move,
                                                 after: step.after), .enPassant)
        XCTAssertNil(step.after[try XCTUnwrap(Square(name: "d5"))])
    }

    func testCheckmateMarksSnapshotAsFinished() throws {
        let board = try XCTUnwrap(Board(fen: "7k/6pp/8/8/8/8/8/R5K1 w - - 0 1"))
        let step = try play(board, "a1", "a8")
        let sync = LivePositionSync()
        XCTAssertTrue(sync.publish(board: step.after, lastMove: step.move, sanHistory: ["Ra8#"], reason: .move,
                                   before: step.before, move: step.move))
        XCTAssertEqual(sync.snapshot?.isGameOver, true)
        XCTAssertEqual(sync.snapshot?.moveKind, .normal)
    }

    // MARK: - Validation

    func testPositionWithoutKingsIsRejected() {
        let sync = LivePositionSync()
        XCTAssertFalse(sync.publish(board: Board.empty, lastMove: nil, sanHistory: [], reason: .edit))
        XCTAssertEqual(sync.rejectedCount, 1)
        XCTAssertTrue(sync.validation.issues.contains(.kingCount))
        XCTAssertNil(sync.snapshot)
    }

    func testSideThatJustMovedMayNotBeInCheck() throws {
        let board = try XCTUnwrap(Board(fen: "4k3/8/8/8/8/8/8/4R1K1 w - - 0 1"))
        let validation = PositionValidation.validate(board)
        XCTAssertFalse(validation.isValid)
        XCTAssertTrue(validation.issues.contains(.opponentInCheck))
    }

    func testEnPassantConsistencyIsValidated() throws {
        let valid = try XCTUnwrap(Board(fen: "8/8/8/3pP3/8/8/8/K6k w - d6 0 1"))
        XCTAssertTrue(PositionValidation.validate(valid).isValid)

        let invalid = try XCTUnwrap(Board(fen: "8/8/8/4P3/8/8/8/K6k w - d6 0 1"))
        XCTAssertTrue(PositionValidation.validate(invalid).issues.contains(.enPassantMismatch))
    }

    func testPawnOnBackRankIsRejected() throws {
        let board = try XCTUnwrap(Board(fen: "P6k/8/8/8/8/8/8/K7 w - - 0 1"))
        XCTAssertTrue(PositionValidation.validate(board).issues.contains(.pawnOnBackRank))
    }

    func testStartPositionIsValid() {
        let validation = PositionValidation.validate(Board())
        XCTAssertTrue(validation.isValid, validation.summary)
        XCTAssertEqual(validation.summary, "FEN gültig")
    }
}
