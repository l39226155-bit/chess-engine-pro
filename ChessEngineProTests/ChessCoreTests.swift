//
//  ChessCoreTests.swift
//  CHESS ENGINE PRO
//
//  Rules engine verification: perft, FEN, SAN, PGN, evaluation classification.
//

import XCTest
@testable import ChessEnginePro

final class ChessCoreTests: XCTestCase {

    // MARK: - Perft

    private func perft(_ board: Board, _ depth: Int) -> Int {
        if depth == 0 { return 1 }
        let moves = board.legalMoves
        if depth == 1 { return moves.count }
        var total = 0
        for move in moves {
            total += perft(board.applying(move), depth - 1)
        }
        return total
    }

    func testPerftStartPosition() {
        let board = Board()
        XCTAssertEqual(perft(board, 1), 20)
        XCTAssertEqual(perft(board, 2), 400)
        XCTAssertEqual(perft(board, 3), 8_902)
    }

    func testPerftKiwipete() {
        let fen = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"
        guard let board = Board(fen: fen) else {
            return XCTFail("FEN konnte nicht geladen werden")
        }
        XCTAssertEqual(perft(board, 1), 48)
        XCTAssertEqual(perft(board, 2), 2_039)
    }

    func testPerftEnPassantAndPromotionPosition() {
        // Position 3 from the standard perft suite.
        let fen = "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1"
        guard let board = Board(fen: fen) else {
            return XCTFail("FEN konnte nicht geladen werden")
        }
        XCTAssertEqual(perft(board, 1), 14)
        XCTAssertEqual(perft(board, 2), 191)
    }

    // MARK: - FEN

    func testFENRoundTrip() {
        let fen = "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 2 3"
        guard let board = Board(fen: fen) else {
            return XCTFail("FEN konnte nicht geladen werden")
        }
        XCTAssertEqual(board.fen, fen)
        XCTAssertEqual(board.sideToMove, .white)
        XCTAssertTrue(board.castling.whiteKingSide)
        // The FEN grants all four rights ("KQkq").
        XCTAssertTrue(board.castling.blackKingSide)
        XCTAssertTrue(board.castling.blackQueenSide)
        XCTAssertEqual(board.halfmoveClock, 2)
        XCTAssertEqual(board.fullmoveNumber, 3)
    }

    func testFENWithEnPassantSquare() {
        let fen = "rnbqkbnr/ppp1pppp/8/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 3"
        guard let board = Board(fen: fen) else {
            return XCTFail("FEN konnte nicht geladen werden")
        }
        XCTAssertEqual(board.enPassant?.name, "d6")
        XCTAssertTrue(board.legalMoves.contains { $0.uci == "e5d6" })
    }

    func testInvalidFENReturnsNil() {
        XCTAssertNil(Board(fen: "not a fen"))
        XCTAssertNil(Board(fen: "8/8/8/8/8/8/8 w - - 0 1"))
    }

    // MARK: - Special moves

    func testCastlingMoves() {
        let fen = "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"
        guard let board = Board(fen: fen) else {
            return XCTFail("FEN konnte nicht geladen werden")
        }
        let moves = board.legalMoves(from: Square(name: "e1")!)
        XCTAssertTrue(moves.contains { $0.uci == "e1g1" })
        XCTAssertTrue(moves.contains { $0.uci == "e1c1" })
    }

    func testCastlingIsIllegalThroughCheck() {
        let fen = "4k3/8/8/8/8/8/5r2/R3K2R w KQ - 0 1"
        guard let board = Board(fen: fen) else {
            return XCTFail("FEN konnte nicht geladen werden")
        }
        let moves = board.legalMoves(from: Square(name: "e1")!)
        XCTAssertFalse(moves.contains { $0.uci == "e1g1" }, "Rochade durch ein bedrohtes Feld ist illegal")
    }

    func testEnPassantCaptureRemovesPawn() {
        let fen = "8/8/8/3pP3/8/8/8/K6k w - d6 0 1"
        guard var board = Board(fen: fen) else {
            return XCTFail("FEN konnte nicht geladen werden")
        }
        guard let move = board.legalMoves(from: Square(name: "e5")!).first(where: { $0.uci == "e5d6" }) else {
            return XCTFail("En-passant-Zug fehlt")
        }
        board.apply(move)
        XCTAssertNil(board[Square(name: "d5")!])
        XCTAssertNotNil(board[Square(name: "d6")!])
    }

    func testPromotionGeneratesFourMoves() {
        let fen = "8/P7/8/8/8/8/8/K6k w - - 0 1"
        guard let board = Board(fen: fen) else {
            return XCTFail("FEN konnte nicht geladen werden")
        }
        let promotions = board.legalMoves(from: Square(name: "a7")!).filter { $0.to.name == "a8" }
        XCTAssertEqual(promotions.count, 4)
        XCTAssertTrue(board.san(for: promotions[0]).contains("=Q"))
    }

    func testCheckmateDetection() {
        var board = Board()
        for san in ["f3", "e5", "g4", "Qh4#"] {
            guard let move = board.move(matchingSan: san) else {
                return XCTFail("Zug \(san) nicht gefunden")
            }
            board.apply(move)
        }
        XCTAssertEqual(board.status, .checkmate(winner: .black))
        XCTAssertTrue(board.isGameOver)
    }

    func testStalemateDetection() {
        guard let board = Board(fen: "7k/5Q2/8/8/8/8/8/K7 b - - 0 1") else {
            return XCTFail("FEN konnte nicht geladen werden")
        }
        XCTAssertEqual(board.status, .stalemate)
    }

    // MARK: - SAN

    func testSANDisambiguation() {
        // Two rooks on the same file must be disambiguated by rank.
        let fen = "4k3/8/8/R7/8/8/8/R3K3 w - - 0 1"
        guard let board = Board(fen: fen) else {
            return XCTFail("FEN konnte nicht geladen werden")
        }
        guard let move = board.legalMoves.first(where: { $0.uci == "a1a3" }) else {
            return XCTFail("Zug fehlt")
        }
        XCTAssertEqual(board.san(for: move), "R1a3")
        XCTAssertEqual(board.move(matchingSan: "R1a3"), move)
        XCTAssertEqual(board.move(matchingSan: "R5a3"), board.legalMoves.first(where: { $0.uci == "a5a3" }))
    }

    func testSANRoundTrip() {
        let fen = "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 2 3"
        guard let board = Board(fen: fen) else {
            return XCTFail("FEN konnte nicht geladen werden")
        }
        for move in board.legalMoves {
            let san = board.san(for: move)
            XCTAssertEqual(board.move(matchingSan: san), move, "SAN \(san) ist nicht eindeutig")
        }
    }

    // MARK: - PGN

    func testPGNParseAndExport() throws {
        let text = """
        [Event "Testpartie"]
        [Site "?"]
        [Date "2026.01.01"]
        [Round "1"]
        [White "Weiß"]
        [Black "Schwarz"]
        [Result "1-0"]

        1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 1-0
        """
        let game = try PGN.parseGame(text)
        XCTAssertEqual(game.moves.count, 10)
        XCTAssertEqual(game.moves.first?.san, "e4")
        XCTAssertEqual(game.result, "1-0")
        XCTAssertEqual(game.startFEN, Board.startFEN)

        let exported = PGN.export(game)
        let reparsed = try PGN.parseGame(exported)
        XCTAssertEqual(reparsed.moves.map { $0.san }, game.moves.map { $0.san })
    }

    func testPGNIgnoresCommentsAndVariations() throws {
        let text = """
        1. e4 {Kommentar} e5 (1... c5 2. Nf3) 2. Nf3 Nc6 *
        """
        let game = try PGN.parseGame(text)
        XCTAssertEqual(game.moves.map { $0.san }, ["e4", "e5", "Nf3", "Nc6"])
    }

    func testPGNRejectsIllegalMove() {
        XCTAssertThrowsError(try PGN.parseGame("1. e4 e5 2. Qxf7"))
    }

    // MARK: - Quality / styles

    func testQualityClassificationUsesEvaluationLoss() {
        XCTAssertEqual(MoveQuality.classify(loss: 0), .excellent)
        XCTAssertEqual(MoveQuality.classify(loss: 300), .mistake)
        XCTAssertEqual(MoveQuality.classify(loss: 900), .blunder)

        // A losing move can never be labelled excellent.
        XCTAssertEqual(MoveQuality.classify(best: .centipawns(0), candidate: .centipawns(-600)), .blunder)
        XCTAssertEqual(MoveQuality.classify(best: .mate(2), candidate: .centipawns(0)), .blunder)
    }

    func testStyleFitPenalisesBadMoves() {
        let features = MoveFeatures(isCheck: true, isSacrifice: true)
        let best = EvalScore.centipawns(20)
        let bad = EvalScore.centipawns(-700)
        let quality = MoveQuality.classify(best: best, candidate: bad)
        for style in MoveStyle.allCases {
            let fit = NaturalMoveSelector.styleFit(style: style,
                                                   features: features,
                                                   quality: quality,
                                                   score: bad,
                                                   bestScore: best)
            XCTAssertLessThan(fit, 40, "Stil \(style) darf einen Patzer nicht gut bewerten")
        }
    }

    func testArrowColoursFollowRankAndQuality() {
        XCTAssertEqual(NaturalMoveSelector.arrowKind(rank: 1, quality: .excellent), .best)
        XCTAssertEqual(NaturalMoveSelector.arrowKind(rank: 2, quality: .veryGood), .alternative)
        XCTAssertEqual(NaturalMoveSelector.arrowKind(rank: 3, quality: .interesting), .interesting)
        XCTAssertEqual(NaturalMoveSelector.arrowKind(rank: 1, quality: .blunder), .critical)
    }

    func testMoveFeaturesDetectCastlingAndDevelopment() {
        let fen = "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 2 3"
        guard let board = Board(fen: fen),
              let castle = board.legalMoves.first(where: { $0.uci == "e1g1" }) else {
            return XCTFail("Stellung oder Rochade fehlt")
        }
        let features = MoveFeatures.make(for: castle, on: board)
        XCTAssertTrue(features.isCastle)
        XCTAssertTrue(features.isQuiet)
        XCTAssertFalse(features.isSacrifice)
    }

    // MARK: - Bundled training data

    @MainActor
    func testBundledPuzzlesHaveLegalSolutions() {
        let puzzles = PuzzleLibrary.shared.puzzles
        XCTAssertFalse(puzzles.isEmpty, "Trainingsdaten fehlen im Bundle")
        for puzzle in puzzles {
            guard var board = Board(fen: puzzle.fen) else {
                XCTFail("Ungültige Puzzle-FEN: \(puzzle.id)")
                continue
            }
            XCTAssertFalse(puzzle.solution.isEmpty)
            for uci in puzzle.solution {
                guard let move = Move(uci: uci), board.isLegal(move) else {
                    XCTFail("Illegaler Lösungszug in \(puzzle.id): \(uci)")
                    break
                }
                board.apply(move)
            }
        }
    }

    @MainActor
    func testBundledOpeningsAreLegal() {
        let openings = OpeningLibrary.shared.openings
        XCTAssertFalse(openings.isEmpty, "Eröffnungsdaten fehlen im Bundle")
        for line in openings {
            var board = Board()
            for san in line.moves {
                guard let move = board.move(matchingSan: san) else {
                    XCTFail("Illegaler Zug \(san) in \(line.name)")
                    break
                }
                board.apply(move)
            }
        }
    }
}
