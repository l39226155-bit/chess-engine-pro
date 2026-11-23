//
//  ChessComDetectionTests.swift
//  CHESS ENGINE PRO
//
//  Tests for the Chess.com position detection: payload decoding, FEN building,
//  move list verification, the structural fallback and its honesty markers.
//

import XCTest
@testable import ChessEnginePro

final class ChessComDetectionTests: XCTestCase {

    private func replay(_ moves: [String]) -> (board: Board, applied: [String]) {
        var board = Board()
        var applied: [String] = []
        for san in moves {
            guard let move = board.move(matchingSan: san) else { break }
            applied.append(san)
            board.apply(move)
        }
        return (board, applied)
    }

    private func payload(placement: String,
                         side: String,
                         moves: [String] = [],
                         gameOver: Bool = false,
                         user: String? = nil,
                         boardID: String = "game:1") -> ChessComPositionPayload {
        ChessComPositionPayload(session: "session-1",
                                sequence: 1,
                                placement: placement,
                                sideToMove: side,
                                moves: moves,
                                userColor: user,
                                isGameOver: gameOver,
                                boardID: boardID)
    }

    // MARK: - FEN building

    func testStartPlacementIsDetectedStructurally() throws {
        let detected = try XCTUnwrap(ChessComPositionDetector.detect(
            payload(placement: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR", side: "w")
        ))

        XCTAssertEqual(detected.origin, .structure)
        XCTAssertTrue(detected.validation.isValid, detected.validation.summary)
        XCTAssertEqual(detected.board.sideToMove, .white)
        XCTAssertEqual(detected.board.castling.fen, "KQkq")
        XCTAssertEqual(detected.board.halfmoveClock, 0)
        XCTAssertEqual(detected.board.fullmoveNumber, 1)
    }

    func testStructuralFallbackReadsSideToMove() throws {
        let detected = try XCTUnwrap(ChessComPositionDetector.detect(
            payload(placement: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR", side: "b")
        ))
        XCTAssertEqual(detected.board.sideToMove, .black)
        XCTAssertEqual(detected.board.fullmoveNumber, 1)
        XCTAssertTrue(detected.validation.isValid)
    }

    // MARK: - Honesty of the fallback

    func testStructuralFallbackNeverClaimsExactCounters() throws {
        let detected = try XCTUnwrap(ChessComPositionDetector.detect(
            payload(placement: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR", side: "b")
        ))

        XCTAssertTrue(detected.confidence.sideToMove)
        XCTAssertFalse(detected.confidence.castling)
        XCTAssertFalse(detected.confidence.isExact)
        XCTAssertTrue(detected.confidence.estimatedFields.contains("Rochaderechte"))
        XCTAssertTrue(detected.confidence.estimatedFields.contains("En-passant-Feld"))
        XCTAssertTrue(detected.confidence.estimatedFields.contains("Halbzugzähler"))
        XCTAssertTrue(detected.confidence.note.contains("Geschätzt"))
    }

    func testVerifiedHistoryIsMarkedExact() throws {
        let moves = ["e4", "e5", "Nf3"]
        let expected = replay(moves)
        let detected = try XCTUnwrap(ChessComPositionDetector.detect(
            payload(placement: ChessComPositionDetector.placementString(expected.board),
                    side: "b",
                    moves: moves)
        ))

        XCTAssertEqual(detected.origin, .history)
        XCTAssertEqual(detected.confidence, .exact)
        XCTAssertTrue(detected.confidence.isExact)
        XCTAssertEqual(detected.confidence.note, "FEN vollständig verifiziert")
        // Halfmove clock after e4 (0), e5 (0) and Nf3 (1): exact, not guessed.
        XCTAssertEqual(detected.board.halfmoveClock, 1)
        XCTAssertEqual(detected.board.fullmoveNumber, 2)
        XCTAssertNil(detected.board.enPassant)
    }

    func testMoveListProducesExactCountersAndRights() throws {
        let moves = ["e4", "e5", "Nf3", "Nc6", "Bc4", "Nf6", "O-O"]
        let expected = replay(moves)
        XCTAssertEqual(expected.applied.count, moves.count)

        let detected = try XCTUnwrap(ChessComPositionDetector.detect(
            payload(placement: ChessComPositionDetector.placementString(expected.board),
                    side: "b",
                    moves: moves,
                    user: "w")
        ))

        XCTAssertEqual(detected.origin, .history)
        XCTAssertEqual(detected.board.fen, expected.board.fen)
        XCTAssertEqual(detected.board.castling.fen, "kq")
        XCTAssertEqual(detected.board.fullmoveNumber, 4)
        XCTAssertEqual(detected.uciMoves.count, 7)
        XCTAssertEqual(detected.lastMove?.uci, "e1g1")
        XCTAssertEqual(detected.userColor, .white)
        XCTAssertTrue(detected.validation.isValid)
    }

    func testEnPassantFieldComesFromVerifiedHistory() throws {
        let moves = ["e4", "a6", "e5", "d5"]
        let expected = replay(moves)

        let detected = try XCTUnwrap(ChessComPositionDetector.detect(
            payload(placement: ChessComPositionDetector.placementString(expected.board),
                    side: "w",
                    moves: moves)
        ))

        XCTAssertEqual(detected.origin, .history)
        XCTAssertEqual(detected.board.enPassant?.name, "d6")
        XCTAssertEqual(detected.board.fen, expected.board.fen)
        XCTAssertTrue(detected.confidence.enPassant)
    }

    func testMismatchedMoveListFallsBackToBoard() throws {
        let detected = try XCTUnwrap(ChessComPositionDetector.detect(
            payload(placement: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR",
                    side: "w",
                    moves: ["e4"])
        ))

        XCTAssertEqual(detected.origin, .structure)
        XCTAssertTrue(detected.validation.isValid)
        XCTAssertFalse(detected.confidence.isExact)
    }

    func testMissingTurnIndicatorIsReportedAsEstimatedSideToMove() throws {
        let detected = try XCTUnwrap(ChessComPositionDetector.detect(
            payload(placement: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR", side: "")
        ))
        XCTAssertFalse(detected.confidence.sideToMove)
        XCTAssertTrue(detected.confidence.estimatedFields.contains("Zugrecht"))
    }

    func testStructuralCastlingInference() throws {
        let detected = try XCTUnwrap(ChessComPositionDetector.detect(
            payload(placement: "r3k2r/8/8/8/8/8/8/R3K2R", side: "b")
        ))
        XCTAssertEqual(detected.origin, .structure)
        XCTAssertEqual(detected.board.castling.fen, "KQkq")
    }

    func testCastlingRightsDisappearWhenRookIsGone() throws {
        let detected = try XCTUnwrap(ChessComPositionDetector.detect(
            payload(placement: "4k3/8/8/8/8/8/8/4K3", side: "w")
        ))
        XCTAssertEqual(detected.board.castling.fen, "-")
    }

    // MARK: - Rejection

    func testKinglessPlacementIsReportedInvalid() throws {
        let detected = try XCTUnwrap(ChessComPositionDetector.detect(
            payload(placement: "8/8/8/8/8/8/8/8", side: "w")
        ))
        XCTAssertFalse(detected.validation.isValid)
        XCTAssertTrue(detected.validation.issues.contains(.kingCount))
    }

    func testMissingBoardIsIgnored() {
        XCTAssertNil(ChessComPositionDetector.detect(payload(placement: "", side: "w")))
    }

    func testUnreadablePlacementIsIgnored() {
        XCTAssertNil(ChessComPositionDetector.detect(payload(placement: "9/8/8/8/8/8/8/8", side: "w")))
    }

    func testNinePawnsAreRejected() throws {
        let detected = try XCTUnwrap(ChessComPositionDetector.detect(
            payload(placement: "7k/8/8/8/PPPPPPPP/PPPPPP2/8/K7", side: "w")
        ))
        XCTAssertFalse(detected.validation.isValid)
        XCTAssertTrue(detected.validation.issues.contains(.pieceCount))
    }

    func testAdjacentKingsAreRejected() throws {
        let detected = try XCTUnwrap(ChessComPositionDetector.detect(
            payload(placement: "8/8/8/8/8/8/8/Kk6", side: "w")
        ))
        XCTAssertFalse(detected.validation.isValid)
        XCTAssertTrue(detected.validation.issues.contains(.kingsAdjacent), detected.validation.summary)
    }

    // MARK: - Decoding

    func testDecodingToleratesMissingFields() throws {
        let json = "{\"placement\":\"8/8/8/8/8/8/8/K6k\",\"sequence\":3}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ChessComPositionPayload.self, from: json)
        XCTAssertEqual(decoded.placement, "8/8/8/8/8/8/8/K6k")
        XCTAssertEqual(decoded.sequence, 3)
        XCTAssertTrue(decoded.moves.isEmpty)
        XCTAssertTrue(decoded.sideToMove.isEmpty)
        XCTAssertNil(decoded.userColor)
        XCTAssertEqual(decoded.boardID, "")
    }
}
