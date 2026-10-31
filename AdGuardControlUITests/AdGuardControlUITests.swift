import XCTest

/// Testy UI głównych przepływów. Aplikacja startuje z `-uitest` i rozmawia z wbudowanym serwerem testowym (bez sieci).
final class AdGuardControlUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(empty: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest"] + (empty ? ["-uitest-empty"] : [])
        app.launch()
        return app
    }

    func testDashboardShowsStatusAndProtectionCanBeSwitchedOff() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Ochrona włączona"].waitForExistence(timeout: 10))

        app.switches["Ochrona DNS"].tap()
        let confirm = app.alerts.buttons["Wyłącz"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "wyłączenie ochrony musi wymagać potwierdzenia")
        confirm.tap()

        XCTAssertTrue(app.staticTexts["Ochrona wyłączona"].waitForExistence(timeout: 10))
    }

    func testCancellingConfirmationKeepsProtectionOn() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Ochrona włączona"].waitForExistence(timeout: 10))
        app.switches["Ochrona DNS"].tap()
        XCTAssertTrue(app.alerts.buttons["Anuluj"].waitForExistence(timeout: 5))
        app.alerts.buttons["Anuluj"].tap()
        XCTAssertTrue(app.staticTexts["Ochrona włączona"].exists)
    }

    func testQueryLogListsAndSearchesDomains() {
        let app = launch()
        app.tabBars.buttons["Dziennik"].tap()
        XCTAssertTrue(app.staticTexts["ads.tracker.net"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["example.com"].exists)

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("apple")
        XCTAssertTrue(app.staticTexts["apple.com"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["ads.tracker.net"].exists)
    }

    func testTabsAreReachable() {
        let app = launch()
        for tab in ["Ochrona", "Filtry", "Więcej", "Przegląd"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.tabBars.buttons[tab].isSelected, "zakładka \(tab)")
        }
    }

    func testOnboardingValidatesAddressBeforeSaving() {
        let app = launch(empty: true)
        let address = app.textFields["http://adres[:port]"]
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        address.tap()
        address.typeText("http://8.8.8.8")          // publiczny adres po HTTP – musi być odrzucony
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'HTTPS'")).firstMatch
            .waitForExistence(timeout: 5), "pole adresu powinno pokazać błąd o HTTPS")
        XCTAssertFalse(app.buttons["Zapisz"].isEnabled)
    }
}
