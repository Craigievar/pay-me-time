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

        XCTAssertTrue(app.staticTexts["attention credit remaining"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Default rate"].exists)
    }

    func testSettingsOffersStandaloneCreditPurchase() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture=settings"]
        app.launch()

        XCTAssertTrue(app.buttons["settings.buyCredits"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Credit never expires and has no cash value."].exists)
    }

    func testProtectionOmitsExplanatoryFooters() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture=protection"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Protection"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["The default starts at 1¢ per hour. Every rate is explicitly capped at 5¢."].exists)
        XCTAssertFalse(app.staticTexts["Apple keeps app identities private. Pay Me Time stores only opaque selection tokens."].exists)
        XCTAssertEqual(
            app.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "Time spent comes from Apple’s Device Activity report"
                )
            ).count,
            0
        )
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
