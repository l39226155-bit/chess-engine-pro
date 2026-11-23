//
//  StrategicExplainerTests.swift
//  CHESS ENGINE PRO
//
//  Tests for the transparent move descriptions of the natural move selection.
//

import XCTest
@testable import ChessEnginePro

final class StrategicExplainerTests: XCTestCase {

    func testRoleTitlesCoverTheThreeSuggestions() {
        XCTAssertEqual(StrategicExplainer.roleTitle(rank: 1), "Bester Zug")
        XCTAssertEqual(StrategicExplainer.roleTitle(rank: 2), "Gute Alternative")
        XCTAssertEqual(StrategicExplainer.roleTitle(rank: 3), "Interessante Variante")
        XCTAssertEqual(StrategicExplainer.roleTitle(rank: 4), "Weitere Variante")
    }

    func testCastlingExplanationMentionsKingSafetyAndEvaluation() {
        var features = MoveFeatures()
        features.isCastle = true
        features.isQuiet = true

        let text = StrategicExplainer.explain(features: features,
                                             quality: .excellent,
                                             score: .centipawns(20),
                                             best: .centipawns(20))

        XCTAssertTrue(text.contains("König"), text)
        XCTAssertTrue(text.contains("Bewertung"), text)
        XCTAssertTrue(text.contains("gleichwertig"), text)
        XCTAssertFalse(text.contains("unter dem besten Zug"), text)
    }

    func testEvaluationLossIsStatedInPawns() {
        var features = MoveFeatures()
        features.isQuiet = true

        let text = StrategicExplainer.explain(features: features,
                                             quality: .good,
                                             score: .centipawns(-30),
                                             best: .centipawns(20))

        XCTAssertTrue(text.contains("0.50 Bauern"), text)
        XCTAssertTrue(text.contains("Gut"), text)
    }

    func testCaptureExplanationNamesTheMaterial() {
        var features = MoveFeatures()
        features.isCapture = true
        features.capturedValue = 320
        features.isQuiet = false

        let text = StrategicExplainer.explain(features: features,
                                             quality: .excellent,
                                             score: .centipawns(300),
                                             best: .centipawns(300))

        XCTAssertTrue(text.contains("Springer"), text)
    }

    func testForkIsDescribedAsFork() {
        var features = MoveFeatures()
        features.createsFork = true
        features.isQuiet = false

        let text = StrategicExplainer.explain(features: features,
                                             quality: .veryGood,
                                             score: .centipawns(90),
                                             best: .centipawns(120))

        XCTAssertTrue(text.contains("Gabel"), text)
        XCTAssertTrue(text.contains("0.30 Bauern"), text)
    }
}
