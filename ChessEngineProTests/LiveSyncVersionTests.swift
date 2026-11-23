//
//  LiveSyncVersionTests.swift
//  CHESS ENGINE PRO
//
//  Tests for versioning, duplicate and stale handling and for the event
//  classification of the live position pipeline.
//

import XCTest
@testable import ChessEnginePro

final class LiveSyncVersionTests: XCTestCase {

    private func play(_ board: Board, _ from: String, _ to: String) throws -> (move: Move, board: Board) {
        let origin = try XCTUnwrap(Square(name: from))
        let target = try XCTUnwrap(Square(name: to))
        let move = try XCTUnwrap(board.move(from: origin, to: target), "Illegal: \(from)\(to)")
        return (move, board.applying(move))
    }

    // MARK: - Versions

    func testExternalVersionsAreMonotonicAndStaleUpdatesAreDropped() throws {
        let sync = LivePositionSync()
        let start = Board()

        XCTAssertTrue(sync.publish(board: start,
                                   lastMove: nil,
                                   sanHistory: [],
                                   reason: .edit,
                                   externalVersion: 5))
        XCTAssertEqual(sync.version, 5)
        XCTAssertEqual(sync.snapshot?.version, 5)

        XCTAssertFalse(sync.publish(board: start,
                                    lastMove: nil,
                                    sanHistory: [],
                                    reason: .detected,
                                    externalVersion: 4))
        XCTAssertEqual(sync.stats.stale, 1)
        XCTAssertEqual(sync.changeCount, 1)

        let step = try play(start, "e2", "e4")
        XCTAssertTrue(sync.publish(board: step.board,
                                   lastMove: step.move,
                                   sanHistory: ["e4"],
                                   reason: .detected,
                                   externalVersion: 6,
                                   userColor: .black))
        XCTAssertEqual(sync.version, 6)
        XCTAssertEqual(sync.snapshot?.eventKind, .opponentMove)
    }

    func testLowerExternalVersionIsRejectedEvenForANewPosition() throws {
        let sync = LivePositionSync()
        let start = Board()
        XCTAssertTrue(sync.publish(board: start,
                                   lastMove: nil,
                                   sanHistory: [],
                                   reason: .detected,
                                   externalVersion: 12))
        XCTAssertEqual(sync.version, 12)

        // A page reload restarts its counter at 1; the caller rebases it, so a
        // raw lower version must never replace the current position.
        let step = try play(start, "d2", "d4")
        XCTAssertFalse(sync.publish(board: step.board,
                                    lastMove: step.move,
                                    sanHistory: ["d4"],
                                    reason: .detected,
                                    externalVersion: 1))
        XCTAssertEqual(sync.stats.stale, 1)
        XCTAssertEqual(sync.snapshot?.ply, 0)
        XCTAssertEqual(sync.version, 12)
    }

    func testDuplicatesAreCountedSeparatelyFromRejections() {
        let sync = LivePositionSync()
        let start = Board()

        XCTAssertTrue(sync.publish(board: start, lastMove: nil, sanHistory: [], reason: .edit))
        XCTAssertFalse(sync.publish(board: start, lastMove: nil, sanHistory: [], reason: .edit))

        XCTAssertEqual(sync.stats.duplicates, 1)
        XCTAssertEqual(sync.stats.rejected, 0)
        XCTAssertEqual(sync.changeCount, 1)
        XCTAssertEqual(sync.stats.accepted, 1)
        XCTAssertEqual(sync.stats.received, 2)
    }

    func testInvalidPositionIsRejectedAndCounted() {
        let sync = LivePositionSync()
        XCTAssertFalse(sync.publish(board: Board.empty, lastMove: nil, sanHistory: [], reason: .detected))
        XCTAssertEqual(sync.stats.rejected, 1)
        XCTAssertEqual(sync.stats.accepted, 0)
        XCTAssertNil(sync.snapshot)
    }

    // MARK: - Events

    func testMoveEventsNameTheSideThatMoved() throws {
        let sync = LivePositionSync()
        var board = Board()
        var history: [String] = []

        let first = try play(board, "e2", "e4")
        history.append(board.san(for: first.move))
        board = first.board
        XCTAssertTrue(sync.publish(board: board,
                                   lastMove: first.move,
                                   sanHistory: history,
                                   reason: .detected))
        XCTAssertEqual(sync.snapshot?.eventKind, .whiteMove)

        let second = try play(board, "e7", "e5")
        history.append(board.san(for: second.move))
        board = second.board
        XCTAssertTrue(sync.publish(board: board,
                                   lastMove: second.move,
                                   sanHistory: history,
                                   reason: .detected))
        XCTAssertEqual(sync.snapshot?.eventKind, .blackMove)
    }

    func testOpponentMoveIsDerivedFromTheUserColour() throws {
        let sync = LivePositionSync()
        let start = Board()
        let first = try play(start, "e2", "e4")
        XCTAssertTrue(sync.publish(board: first.board,
                                   lastMove: first.move,
                                   sanHistory: ["e4"],
                                   reason: .detected,
                                   userColor: .white))
        XCTAssertEqual(sync.snapshot?.eventKind, .whiteMove)

        let second = try play(first.board, "c7", "c5")
        XCTAssertTrue(sync.publish(board: second.board,
                                   lastMove: second.move,
                                   sanHistory: ["e4", "c5"],
                                   reason: .detected,
                                   userColor: .white))
        XCTAssertEqual(sync.snapshot?.eventKind, .opponentMove)
    }

    func testResetToStartIsReportedAsNewGame() throws {
        let sync = LivePositionSync()
        var board = Board()
        var history: [String] = []

        for (from, to) in [("e2", "e4"), ("e7", "e5"), ("g1", "f3"), ("b8", "c6")] {
            let step = try play(board, from, to)
            history.append(board.san(for: step.move))
            board = step.board
        }

        XCTAssertTrue(sync.publish(board: board, lastMove: nil, sanHistory: history, reason: .detected))
        XCTAssertTrue(sync.publish(board: Board(), lastMove: nil, sanHistory: [], reason: .detected))
        XCTAssertEqual(sync.snapshot?.eventKind, .newGame)
        XCTAssertEqual(sync.version, 2)
    }

    func testFinishedGameRaisesGameOverEvent() throws {
        let board = try XCTUnwrap(Board(fen: "7k/6pp/8/8/8/8/8/R5K1 w - - 0 1"))
        let step = try play(board, "a1", "a8")
        let sync = LivePositionSync()

        XCTAssertTrue(sync.publish(board: step.board,
                                   lastMove: step.move,
                                   sanHistory: ["Ra8#"],
                                   reason: .detected))
        XCTAssertEqual(sync.snapshot?.eventKind, .gameOver)
        XCTAssertEqual(sync.snapshot?.isGameOver, true)
    }

    func testEventLogKeepsTheLatestVersion() throws {
        let sync = LivePositionSync()
        let start = Board()
        sync.publish(board: start, lastMove: nil, sanHistory: [], reason: .edit)
        let step = try play(start, "g1", "f3")
        sync.publish(board: step.board, lastMove: step.move, sanHistory: ["Nf3"], reason: .detected)

        XCTAssertEqual(sync.events.count, 2)
        XCTAssertEqual(sync.events.last?.version, 2)
        XCTAssertEqual(sync.events.last?.kind, .whiteMove)
        XCTAssertEqual(sync.events.last?.source, .local)
    }
}
