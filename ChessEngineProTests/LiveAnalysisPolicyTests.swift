//
//  LiveAnalysisPolicyTests.swift
//  CHESS ENGINE PRO
//
//  The panel may only show engine suggestions in supported analysis modes.
//  These tests pin the URL classification and the resulting gate.
//

import XCTest
@testable import ChessEnginePro

final class LiveAnalysisPolicyTests: XCTestCase {

    private func url(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            XCTFail("Ungültige Test-URL: \(string)")
            return URL(fileURLWithPath: "/")
        }
        return url
    }

    // MARK: - Supported modes

    func testComputerGamesAllowSuggestions() {
        let mode = ChessComPageMode.classify(url("https://www.chess.com/play/computer"))
        XCTAssertEqual(mode, .computer)
        XCTAssertTrue(LiveAnalysisPolicy.allowsSuggestions(in: mode, engineEnabled: true))
        XCTAssertNil(LiveAnalysisPolicy.blockNote(for: mode))
    }

    func testAnalysisBoardAllowsSuggestions() {
        let mode = ChessComPageMode.classify(url("https://www.chess.com/analysis?tab=analysis"))
        XCTAssertEqual(mode, .analysis)
        XCTAssertTrue(LiveAnalysisPolicy.allowsSuggestions(in: mode, engineEnabled: true))
    }

    func testPuzzlesAndTrainingAllowSuggestions() {
        XCTAssertEqual(ChessComPageMode.classify(url("https://www.chess.com/puzzles")), .training)
        XCTAssertEqual(ChessComPageMode.classify(url("https://www.chess.com/practice")), .training)
        XCTAssertTrue(LiveAnalysisPolicy.allowsSuggestions(in: .training, engineEnabled: true))
    }

    // MARK: - Rated online games

    func testRatedLiveGameBlocksSuggestions() {
        let mode = ChessComPageMode.classify(url("https://www.chess.com/game/live/123456789"))
        XCTAssertEqual(mode, .onlineGame)
        XCTAssertFalse(LiveAnalysisPolicy.allowsSuggestions(in: mode, engineEnabled: true))
        XCTAssertNotNil(LiveAnalysisPolicy.blockNote(for: mode))
    }

    func testDailyGameBlocksSuggestions() {
        let mode = ChessComPageMode.classify(url("https://www.chess.com/game/daily/987654"))
        XCTAssertEqual(mode, .onlineGame)
        XCTAssertFalse(mode.allowsEngineSuggestions)
    }

    func testOnlineLobbyBlocksSuggestions() {
        // The online play area is not a supported analysis mode, even while its
        // address is still the lobby.
        XCTAssertEqual(ChessComPageMode.classify(url("https://www.chess.com/play/online")), .onlineGame)
        XCTAssertEqual(ChessComPageMode.classify(url("https://www.chess.com/play")), .onlineGame)
        XCTAssertEqual(ChessComPageMode.classify(url("https://www.chess.com/live")), .onlineGame)
    }

    // MARK: - Other cases

    func testDisabledEngineBlocksEvenSupportedModes() {
        XCTAssertFalse(LiveAnalysisPolicy.allowsSuggestions(in: .analysis, engineEnabled: false))
        XCTAssertFalse(LiveAnalysisPolicy.allowsSuggestions(in: .computer, engineEnabled: false))
    }

    func testUnknownPageFallsBackToTheChessComHomeMode() {
        XCTAssertEqual(ChessComPageMode.classify(nil), .home)
        XCTAssertEqual(ChessComPageMode.classify(url("https://www.chess.com/")), .home)
        XCTAssertEqual(ChessComPageMode.classify(url("https://www.chess.com/member/player")), .home)
        XCTAssertEqual(ChessComPageMode.classify(url("https://example.com/game/live/1")), .home)
        XCTAssertTrue(LiveAnalysisPolicy.allowsSuggestions(in: .home, engineEnabled: true))
    }

    // MARK: - Finished games and availability

    func testFinishedOnlineGameAllowsAnalysis() {
        XCTAssertTrue(LiveAnalysisPolicy.allowsSuggestions(in: .onlineGame,
                                                           engineEnabled: true,
                                                           isGameOver: true))
        XCTAssertEqual(LiveAnalysisPolicy.availability(in: .onlineGame,
                                                       engineEnabled: true,
                                                       isGameOver: true),
                       .enabled)
    }

    func testRunningOnlineGameStaysBlocked() {
        XCTAssertFalse(LiveAnalysisPolicy.allowsSuggestions(in: .onlineGame,
                                                            engineEnabled: true,
                                                            isGameOver: false))
        let availability = LiveAnalysisPolicy.availability(in: .onlineGame,
                                                           engineEnabled: true,
                                                           isGameOver: false)
        XCTAssertFalse(availability.isEnabled)
        XCTAssertNotNil(availability.reason)
    }

    func testFinishedGameDoesNotUnlockWhenTheEngineIsOff() {
        XCTAssertFalse(LiveAnalysisPolicy.allowsSuggestions(in: .onlineGame,
                                                            engineEnabled: false,
                                                            isGameOver: true))
        XCTAssertEqual(LiveAnalysisPolicy.availability(in: .onlineGame,
                                                       engineEnabled: false,
                                                       isGameOver: true),
                       .blocked(reason: "Die Engine ist in den Einstellungen deaktiviert."))
    }
}
