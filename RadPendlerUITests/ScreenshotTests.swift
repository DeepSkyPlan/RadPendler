import XCTest

/// Drives the app through the scenes the App Store listing shows and keeps
/// every frame as an attachment. Not part of `./dev test` — it has its own
/// scheme (`RadPendlerShots`), because it needs the network and takes minutes.
///
/// The frames come out at the simulator's native size, so the device decides
/// the App Store slot: a 6.5" phone gives 1284 × 2778, an iPad Pro 13" gives
/// 2064 × 2752. Anything else is rejected on upload.
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!
    private var shot = 0

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
    }

    func testCaptureAppStoreScreenshots() {
        let pad = app.windows.firstMatch.frame.width > 700

        waitForPlan()
        keep("hauptseite")

        // The bike box: the map then draws the cycle route with its junctions.
        if tap(button: "Fahrrad:") {
            sleep(8)
            keep("rad")
        }

        // On the phone the timeline hides behind the chevron; on the iPad it
        // already stands in the left column, so there is nothing to open.
        if !pad {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.955))
                .tap()
            sleep(3)
            keep("fahrt")
            if app.navigationBars.buttons.firstMatch.exists {
                app.navigationBars.buttons.firstMatch.tap()
                sleep(2)
            }
        }

        // Rad + Bahn, which is what the app is named after.
        if tap(button: "Rad + Bahn:") {
            sleep(6)
            keep("radbahn")
        }

        guard app.buttons["Menü"].waitForExistence(timeout: 10) else { return }
        app.buttons["Menü"].tap()
        sleep(1)
        guard app.buttons["Einstellungen"].waitForExistence(timeout: 5) else { return }
        app.buttons["Einstellungen"].tap()
        sleep(3)
        // Unscrolled: the addresses and the three preference lists under them.
        keep("vorlieben")

        // The bike-carriage list, a few sections further down. Its row is a
        // LabeledContent, so the label carries the value too — match the head.
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Fahrradmitnahme")).firstMatch
        for _ in 0..<8 {
            if row.exists && row.isHittable { break }
            app.swipeUp()
            sleep(1)
        }
        if row.exists && row.isHittable {
            row.tap()
            sleep(3)
            keep("fahrradmitnahme")
        }
    }

    /// The first plan needs the timetable, BRouter, Overpass and the rain —
    /// the "los HH:MM" chip is the sign that all of it has landed.
    private func waitForPlan() {
        let chip = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "los ")).firstMatch
        _ = chip.waitForExistence(timeout: 180)
        sleep(6)
    }

    @discardableResult
    private func tap(button prefix: String) -> Bool {
        let b = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        guard b.waitForExistence(timeout: 10), b.isHittable else { return false }
        b.tap()
        return true
    }

    private func keep(_ name: String) {
        shot += 1
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = String(format: "%d-%@", shot, name)
        a.lifetime = .keepAlways
        add(a)
    }
}
