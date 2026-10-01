import XCTest

/// Ein Rundgang vor dem Hochladen: Hauptseite, Menü, alle vier Seiten der
/// Einstellungen (jeweils heruntergescrollt) und die Fahrtenliste — als PNG in
/// ein Verzeichnis. Läuft nur mit `TEST_RUNNER_RP_QA_DIR=<verzeichnis>` vor
/// `xcodebuild … -scheme RadPendlerShots -only-testing:RadPendlerUITests/QAWalkthroughTests test`,
/// sonst wird er übersprungen. Die Adressen legt man vorher per `simctl defaults` an.
final class QAWalkthroughTests: XCTestCase {
    private var app: XCUIApplication!
    private var dir: URL!
    private var shot = 0

    override func setUpWithError() throws {
        guard let path = ProcessInfo.processInfo.environment["RP_QA_DIR"] else {
            throw XCTSkip("RP_QA_DIR nicht gesetzt")
        }
        dir = URL(fileURLWithPath: path)
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
    }

    func testWalkThroughMenusAndSettings() {
        let chip = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "los ", "leave ")).firstMatch
        _ = chip.waitForExistence(timeout: 180)
        sleep(4)
        keep("hauptseite")

        let pages = ProcessInfo.processInfo.environment["RP_QA_EN"] != nil
            ? ["Addresses", "Navigation", "Modes", "Settings", "Rides"]
            : ["Adressen", "Navigation", "Verkehrsmittel", "Einstellungen", "Fahrten"]
        for page in pages {
            guard openMenu() else { return }
            // Der erste Tipp schließt womöglich nur den Hinweis zum Doppeltipp.
            if !app.buttons[page].waitForExistence(timeout: 2) { _ = openMenu() }
            if page == pages[0] { keep("menue") }
            let b = app.buttons[page]
            guard b.waitForExistence(timeout: 5) else { continue }
            b.tap()
            sleep(2)
            keep(page.lowercased())
            for i in 1...4 {
                app.swipeUp()
                sleep(1)
                keep("\(page.lowercased())-\(i)")
            }
            close()
        }
    }

    private func openMenu() -> Bool {
        let menu = app.buttons.matching(NSPredicate(format: "label IN %@", ["Menü", "Menu"])).firstMatch
        guard menu.waitForExistence(timeout: 10) else { return false }
        menu.tap()
        sleep(1)
        return true
    }

    private func close() {
        let done = app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["Fertig", "Done"])).firstMatch
        if done.exists { done.tap() } else { app.swipeDown(velocity: .fast) }
        sleep(2)
    }

    private func keep(_ name: String) {
        shot += 1
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: dir.appendingPathComponent(String(format: "qa-%02d-%@.png", shot, name)))
    }
}
