// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

final class GokanSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchLoadsSGFAndShowsAnalysis() throws {
        let app = XCUIApplication()
        app.launchEnvironment["GOKAN_UI_TEST_SGF"] = "(;GM[1]FF[4]SZ[9]PB[Smoke Black]PW[Smoke White]KM[6.5];B[ee])"
        app.launchEnvironment["GOKAN_UI_TEST_FORCE_MOCK_ENGINE"] = "1"
        app.launch()

        let moveCount = app.staticTexts["gokan.move-count"]
        XCTAssertTrue(moveCount.waitForExistence(timeout: 30))
        XCTAssertTrue(waitFor(moveCount, toContain: "Move 1 / 1"))
        XCTAssertTrue(app.textFields["gokan.metadata.black-player"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.textFields["gokan.metadata.black-player"].value as? String, "Smoke Black")
        let diagnosticsStatus = app.staticTexts["gokan.analysis-diagnostics-status"]
        XCTAssertTrue(scrollUntilExists(diagnosticsStatus, in: app))
        XCTAssertTrue(waitFor(diagnosticsStatus, toContain: "Succeeded"))
        let completedVisits = app.staticTexts["gokan.analysis-diagnostics-completed-visits"]
        XCTAssertTrue(scrollUntilExists(completedVisits, in: app))
        XCTAssertTrue(app.buttons["Play Candidate"].waitForExistence(timeout: 30))
    }

    @MainActor
    private func scrollUntilExists(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 6) -> Bool {
        if element.waitForExistence(timeout: 3) {
            return true
        }

        let scrollTarget = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app
        for _ in 0..<attempts {
            scrollTarget.swipeUp()
            if element.waitForExistence(timeout: 2) {
                return true
            }
        }

        return false
    }

    @MainActor
    private func waitFor(_ element: XCUIElement, toContain text: String, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.label.contains(text) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline

        return false
    }

}
