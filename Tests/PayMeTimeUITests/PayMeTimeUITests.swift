import XCTest

@MainActor
final class PayMeTimeUITests: XCTestCase {
    func testSetupCopyMatchesBB69() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture=onboarding"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Your time is valuable."].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.staticTexts[
                "Research shows that even small explicit costs cause our brains to think instead of running on autopilot."
            ].exists
        )
        XCTAssertTrue(app.staticTexts["You start with $2.00 in credits"].exists)
        XCTAssertTrue(app.buttons["Choose apps that you'll pay for"].exists)
        XCTAssertTrue(app.staticTexts["Global grace period before payments start."].exists)
        XCTAssertTrue(app.staticTexts["You can turn off payments at any time."].exists)
        XCTAssertFalse(app.staticTexts["Apple keeps this private. Apps must be chosen by you in the Screen Time picker and cannot be silently preloaded."].exists)
        XCTAssertFalse(app.staticTexts["Set your friction"].exists)
        XCTAssertFalse(app.staticTexts["Default charge rate"].exists)
    }

    func testHomeUsesAttentionCreditWithoutDefaultRateRow() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture=home"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Screenbump"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["attention credit remaining"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Default rate"].exists)
    }

    func testHomeOffersRatingHalfwayThroughStarterCredit() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture=rating"]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["Halfway through your starter credit"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertEqual(app.buttons["home.rateApp"].label, "Rate Screenbump")
        XCTAssertTrue(app.buttons["home.dismissRating"].exists)
    }

    func testSettingsOffersStandaloneCreditPurchase() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture=settings"]
        app.launch()

        let buyCredits = app.buttons["settings.buyCredits"]
        XCTAssertTrue(buyCredits.waitForExistence(timeout: 3))
        XCTAssertFalse(app.switches["Share anonymous analytics"].exists)
        XCTAssertFalse(
            app.staticTexts[
                "Includes app interactions and aggregate Screen Time trends. App names and Screen Time tokens are never sent."
            ].exists
        )
        XCTAssertFalse(app.staticTexts["Credit never expires and has no cash value."].exists)

        buyCredits.tap()

        let title = app.staticTexts["Refill credit"]
        let cancel = app.buttons["refill.cancel"]
        let warning = app.staticTexts["refill.noValueWarning"]
        let confirm = app.buttons["refill.confirm"]

        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertTrue(cancel.exists)
        XCTAssertTrue(warning.exists)
        XCTAssertTrue(app.staticTexts["$0.99"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["$4.99"].exists)
        XCTAssertTrue(app.staticTexts["$9.99"].exists)
        XCTAssertTrue(app.staticTexts["$24.99"].exists)
        XCTAssertEqual(
            confirm.label,
            "Buy $1 credit for $0.99"
        )
        XCTAssertFalse(
            app.staticTexts[
                "Keep the money moment in front of mind. Credit never expires."
            ].exists
        )

        // SwiftUI's sheet presentation is not exposed as an XCUIElement of
        // type `.sheet`, so verify the same safe-area spacing against the
        // containing window.
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
        XCTAssertGreaterThan(cancel.frame.minX, title.frame.maxX)
        XCTAssertEqual(cancel.frame.midY, title.frame.midY, accuracy: 2)
        XCTAssertEqual(title.frame.midX, window.frame.midX, accuracy: 2)
        XCTAssertGreaterThanOrEqual(cancel.frame.minY - window.frame.minY, 24)
        XCTAssertGreaterThanOrEqual(
            window.frame.maxX - cancel.frame.maxX,
            16
        )
        XCTAssertGreaterThan(app.buttons["refill.100"].frame.minY, cancel.frame.maxY)
        XCTAssertEqual(
            warning.frame.midX,
            window.frame.midX,
            accuracy: 2
        )
        XCTAssertGreaterThan(confirm.frame.minY, warning.frame.maxY)
        XCTAssertLessThanOrEqual(confirm.frame.maxY, window.frame.maxY - 8)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "refill-sheet-layout"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testRefillFailureStopsLoadingAndOffersRetry() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--fixture=settings",
            "--purchase-fixture=failed",
        ]
        app.launch()

        XCTAssertTrue(app.buttons["settings.buyCredits"].waitForExistence(timeout: 3))
        app.buttons["settings.buyCredits"].tap()

        let error = app.descendants(matching: .any)["refill.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 3))
        let retry = app.buttons["refill.retry"]
        XCTAssertTrue(retry.exists)
        XCTAssertEqual(
            app.buttons["refill.confirm"].label,
            "Purchase options unavailable"
        )
        XCTAssertTrue(
            app.buttons["refill.100"].label.contains("Unavailable")
        )
        XCTAssertEqual(app.activityIndicators.count, 0)
        let window = app.windows.firstMatch
        XCTAssertEqual(error.frame.midX, window.frame.midX, accuracy: 2)
        XCTAssertEqual(retry.frame.midX, window.frame.midX, accuracy: 2)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "refill-failure-layout"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testRefillPartialCatalogKeepsAvailableOptionsPurchasable() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--fixture=settings",
            "--purchase-fixture=partial",
        ]
        app.launch()

        XCTAssertTrue(app.buttons["settings.buyCredits"].waitForExistence(timeout: 3))
        app.buttons["settings.buyCredits"].tap()

        let partial = app.descendants(matching: .any)["refill.partial"]
        XCTAssertTrue(partial.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["$0.99"].exists)
        XCTAssertTrue(app.staticTexts["$4.99"].exists)
        XCTAssertTrue(
            app.buttons["refill.1000"].label.contains("Unavailable")
        )
        XCTAssertTrue(
            app.buttons["refill.2500"].label.contains("Unavailable")
        )
        XCTAssertTrue(app.buttons["refill.100"].isEnabled)
        XCTAssertFalse(app.buttons["refill.1000"].isEnabled)
        XCTAssertEqual(
            app.buttons["refill.confirm"].label,
            "Buy $1 credit for $0.99"
        )

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "refill-partial-layout"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testHomeRefillUsesAlignedHeaderAndDismisses() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture=home"]
        app.launch()

        let refill = app.buttons["home.refill"]
        XCTAssertTrue(refill.waitForExistence(timeout: 3))
        refill.tap()

        let title = app.staticTexts["Refill credit"]
        let cancel = app.buttons["refill.cancel"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertTrue(cancel.exists)
        XCTAssertEqual(cancel.frame.midY, title.frame.midY, accuracy: 2)

        cancel.tap()

        XCTAssertTrue(app.navigationBars["Screenbump"].waitForExistence(timeout: 3))
        XCTAssertFalse(title.exists)
    }

    func testProtectionOmitsExplanatoryFooters() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture=protection"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Protection"].waitForExistence(timeout: 3))
        let globalRate = app.descendants(matching: .any)[
            "protection.globalRate"
        ]
        XCTAssertTrue(globalRate.exists)
        XCTAssertTrue(globalRate.label.contains("Global default"))
        XCTAssertTrue(globalRate.label.contains("5¢ / hour"))
        XCTAssertFalse(app.navigationBars["Protection"].buttons["Choose apps"].exists)
        XCTAssertFalse(app.staticTexts["The default starts at 5¢ per hour. Every rate is explicitly capped at 10¢."].exists)
        XCTAssertFalse(app.staticTexts["Apple keeps app identities private. Screenbump stores only opaque selection tokens."].exists)
        XCTAssertEqual(
            app.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "Time spent comes from Apple’s Device Activity report"
                )
            ).count,
            0
        )

        let addApps = app.buttons["protection.addApps"]
        for _ in 0..<3 where !addApps.exists {
            app.swipeUp()
        }
        XCTAssertTrue(addApps.exists)
        XCTAssertEqual(
            app.buttons["protection.app.Reddit"].frame.maxY,
            addApps.frame.minY,
            accuracy: 1
        )
    }

    func testAppRateEditorPresentsAndSavesCleanly() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture=protection"]
        app.launch()

        let appRow = app.buttons["protection.app.TikTok"]
        XCTAssertTrue(appRow.waitForExistence(timeout: 3))
        appRow.tap()

        let navigationBar = app.navigationBars["TikTok"]
        let cancel = app.buttons["Cancel"]
        let save = app.buttons["rate.save"]
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 3))
        XCTAssertTrue(cancel.exists)
        XCTAssertTrue(save.exists)
        XCTAssertEqual(cancel.frame.midY, save.frame.midY, accuracy: 2)
        XCTAssertTrue(app.switches["Use global default"].exists)
        XCTAssertTrue(
            app.staticTexts[
                "This app can never charge more than 10¢ per hour."
            ].exists
        )

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "app-rate-editor-layout"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        save.tap()

        XCTAssertTrue(app.staticTexts["Protection"].waitForExistence(timeout: 3))
        XCTAssertFalse(navigationBar.exists)
    }

    func testProgressShowsSevenDayTrendAndBaselineComparison() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture=home"]
        app.launch()

        let progressTab = app.tabBars.buttons["Progress"]
        XCTAssertTrue(progressTab.waitForExistence(timeout: 3))
        progressTab.tap()

        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["LAST 7 DAYS"].exists)
        XCTAssertTrue(app.staticTexts["Daily time"].exists)
        XCTAssertTrue(app.staticTexts["Compared with baseline"].exists)
        XCTAssertTrue(app.staticTexts["32% less than baseline"].exists)
    }

    func testExplicitShieldFixture() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture=shield"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Use your time carefully. It costs you!"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Proceed"].exists)
        XCTAssertTrue(app.buttons["I’ll pass"].exists)
    }

    func testEmptyShieldIncludesDisableEscape() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture=empty-shield"]
        app.launch()

        XCTAssertTrue(app.staticTexts["You spent all of your time credit"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["shield.disable"].exists)
    }
}
