//
//  ChessComBrowserLifecycleTests.swift
//  CHESS ENGINE PRO
//
//  The Chess.com web view must be initialised exactly once and must never be
//  reloaded by tab switches, session refreshes or live snapshots.
//

import XCTest
@testable import ChessEnginePro

@MainActor
final class ChessComBrowserLifecycleTests: XCTestCase {

    func testStartIfNeededLoadsThePageOnlyOnce() {
        let browser = ChessComBrowser()
        XCTAssertEqual(browser.navigationCount, 0)

        browser.startIfNeeded()
        XCTAssertEqual(browser.navigationCount, 1, "Der erste Besuch muss laden")

        browser.startIfNeeded()
        browser.startIfNeeded()
        XCTAssertEqual(browser.navigationCount, 1, "Weitere Besuche dürfen nicht nachladen")
    }

    func testTabSwitchHelpersNeverNavigate() {
        let browser = ChessComBrowser()
        browser.startIfNeeded()
        let before = browser.navigationCount

        // Exactly what PlayView does on every tab change.
        browser.prepareForDisplay()
        browser.refreshSessionState()
        browser.requestLiveSnapshot()
        _ = browser.hasSession
        _ = browser.currentURL

        XCTAssertEqual(browser.navigationCount, before)
    }

    func testOnlyExplicitUserActionsNavigate() {
        let browser = ChessComBrowser()
        browser.startIfNeeded()
        let before = browser.navigationCount

        browser.openLogin()
        XCTAssertEqual(browser.navigationCount, before + 1)

        browser.goHome()
        XCTAssertEqual(browser.navigationCount, before + 2)
    }
}
