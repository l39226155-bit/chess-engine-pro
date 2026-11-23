//
//  LiveAnalysisPolicyTests.swift
//  CHESS ENGINE PRO
//
//  Engine assistance is only allowed in training, analysis and finished games.
//

import XCTest
@testable import ChessEnginePro

final class LiveAnalysisPolicyTests: XCTestCase {

    func testAnalysisBoardIsAllowed() {
        let permission = LiveAnalysisPolicy.permission(url: "https://www.chess.com/analysis?tab=analysis",
                                                       isGameOver: false)
        XCTAssertTrue(permission.isAllowed)
        XCTAssertEqual(permission.contextLabel, "Analysebrett")
    }

    func testPuzzlesAndTrainingAreAllowed() {
        XCTAssertTrue(LiveAnalysisPolicy.permission(url: "https://www.chess.com/puzzles", isGameOver: false).isAllowed)
        XCTAssertTrue(LiveAnalysisPolicy.permission(url: "https://www.chess.com/puzzles/rush", isGameOver: false).isAllowed)
        XCTAssertTrue(LiveAnalysisPolicy.permission(url: "https://www.chess.com/training", isGameOver: false).isAllowed)
        XCTAssertTrue(LiveAnalysisPolicy.permission(url: "https://www.chess.com/lessons", isGameOver: false).isAllowed)
    }

    func testComputerGameIsTreatedAsTraining() {
        let permission = LiveAnalysisPolicy.permission(url: "https://www.chess.com/play/computer",
                                                       isGameOver: false)
        XCTAssertTrue(permission.isAllowed)
        XCTAssertEqual(permission.contextLabel, "Partie gegen den Computer")
    }

    func testRunningOnlineGameIsBlocked() {
        for url in ["https://www.chess.com/game/live/123456",
                    "https://www.chess.com/play/online",
                    "https://www.chess.com/game/daily/42"] {
            let permission = LiveAnalysisPolicy.permission(url: url, isGameOver: false)
            XCTAssertFalse(permission.isAllowed, url)
            XCTAssertNotNil(permission.blockedReason, url)
            XCTAssertTrue(permission.blockedReason?.contains("nicht erlaubt") ?? false, url)
        }
    }

    func testFinishedOnlineGameIsAllowed() {
        let permission = LiveAnalysisPolicy.permission(url: "https://www.chess.com/game/live/123456",
                                                       isGameOver: true)
        XCTAssertTrue(permission.isAllowed)
        XCTAssertEqual(permission.contextLabel, "Partie beendet")
    }

    func testUnknownPageIsBlockedUntilTheGameIsOver() {
        XCTAssertFalse(LiveAnalysisPolicy.permission(url: "https://www.chess.com/home", isGameOver: false).isAllowed)
        XCTAssertTrue(LiveAnalysisPolicy.permission(url: "https://www.chess.com/home", isGameOver: true).isAllowed)
        XCTAssertFalse(LiveAnalysisPolicy.permission(url: "", isGameOver: false).isAllowed)
    }

    func testQueryStringDoesNotGrantPermission() {
        let permission = LiveAnalysisPolicy.permission(url: "https://www.chess.com/game/live/1?next=/analysis",
                                                       isGameOver: false)
        XCTAssertFalse(permission.isAllowed)
    }
}
