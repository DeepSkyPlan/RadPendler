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
            sleep(4)
            // Ein Tipp auf den gewählten Kasten schaltet zur nächsten Linie —
            // und das kann eine „Alternative" sein, ein Weg ohne Rolle. Ins
            // Schaufenster gehört eine mit Namen: weiterschalten, bis eine dasteht.
            for _ in 0..<4 where bikeBoxShows("Alternative") {
                tap(button: "Fahrrad:")
                sleep(2)
            }
            sleep(6)
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

        // Das Menü selbst: die vier Seiten der Einstellungen, die Fahrten —
        // und die Sprachwahl, die es seit 1.4 gibt.
        guard app.buttons["Menü"].waitForExistence(timeout: 10) else { return }
        app.buttons["Menü"].tap()
        sleep(2)
        keep("menue")

        // Die Vorlieben: Reihenfolge der Verkehrsmittel, Routenvarianten,
        // Regenschwelle, und die zwei Geschwindigkeiten.
        if app.buttons["Verkehrsmittel"].waitForExistence(timeout: 5) {
            app.buttons["Verkehrsmittel"].tap()
            sleep(3)
            keep("vorlieben")
            if app.navigationBars.buttons["Fertig"].exists {
                app.navigationBars.buttons["Fertig"].tap()
                sleep(2)
            }
        }

        // Und was während einer Fahrt passiert: abdunkeln, anhalten, beenden.
        guard app.buttons["Menü"].waitForExistence(timeout: 10) else { return }
        app.buttons["Menü"].tap()
        sleep(1)
        guard app.buttons["Einstellungen"].waitForExistence(timeout: 5) else { return }
        app.buttons["Einstellungen"].tap()
        sleep(3)
        keep("einstellungen")
        if app.navigationBars.buttons["Fertig"].exists {
            app.navigationBars.buttons["Fertig"].tap()
            sleep(2)
        }

        // Der Fahrtmodus selbst — die Seite, auf die es unterwegs ankommt.
        // Sie lebt von Bewegung: ohne einen laufenden Ortungslauf
        // (`simctl location … start`) stünden hier lauter Nullen, und das Bild
        // wäre wertlos. Die Wartezeit ist die Fahrt, die gemessen wird.
        captureRide()
    }

    /// Zeichnet eine kurze Fahrt auf und hält sie fest, sobald Tempo,
    /// Schnitt und Restweg etwas zu sagen haben. Danach wird sie beendet —
    /// eine laufende Aufzeichnung würde den nächsten Lauf begrüßen.
    private func captureRide() {
        // Die reine Radfahrt, nicht Rad + Bahn: sonst steht neben dem
        // gefahrenen Schnitt der Schnitt einer Fahrt, in der ein Zug sitzt —
        // neununddreißig Kilometer in der Stunde, auf einem Fahrrad.
        //
        // Lang drücken springt auf die erste Linie des Kastens zurück — die
        // mit der frühesten Ankunft. An ihr entlang läuft das Ortungsskript
        // (`appstore/metadata.md`, „Neu aufnehmen"); jede andere läge nach
        // sechzig Metern daneben, und quer über dem Bild stünde ein rotes
        // „151 m neben der Route".
        if tap(button: "Fahrrad:") { sleep(3) }
        let box = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Fahrrad:")).firstMatch
        if box.exists { box.press(forDuration: 1.2); sleep(5) }
        let start = app.buttons["Fahrt aufzeichnen"]
        guard start.waitForExistence(timeout: 15), start.isHittable else { return }
        start.tap()
        // Lang genug, dass Tempo, Schnitt und Strecke etwas zu sagen haben —
        // und lang genug, dass die App eine Abweichung vom Weg, die nur dem
        // gerade laufenden Ortungsskript geschuldet ist, selbst wieder
        // eingefangen hat.
        sleep(70)
        // Steht das rote Band trotzdem da, plant die App gleich neu — darauf
        // warten, statt es zu fotografieren.
        let offRoute = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "neben der Route")).firstMatch
        for _ in 0..<12 where offRoute.exists { sleep(10) }
        keep("fahrtmodus")
        guard app.buttons["Fahrt beenden"].waitForExistence(timeout: 5) else { return }
        app.buttons["Fahrt beenden"].tap()
        sleep(1)
        // Der Rückfragedialog benutzt denselben Wortlaut wie der Knopf.
        let confirm = app.buttons.matching(identifier: "Fahrt beenden").element(boundBy: 1)
        if confirm.exists { confirm.tap() } else { app.buttons["Fahrt beenden"].tap() }
        sleep(3)
    }

    /// The first plan needs the timetable, BRouter, Overpass and the rain —
    /// the "los HH:MM" chip is the sign that all of it has landed.
    private func waitForPlan() {
        let chip = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "los ")).firstMatch
        _ = chip.waitForExistence(timeout: 180)
        // Der Chip steht da, sobald das erste Verkehrsmittel geplant ist; die
        // anderen Kästen zeigen dann noch „sucht …". Mit vier Radlinien dauert
        // das länger als früher — die Hauptseite soll vollständig sein.
        let searching = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "sucht")).firstMatch
        for _ in 0..<24 where searching.exists { sleep(5) }
        sleep(8)
    }

    @discardableResult
    private func tap(button prefix: String) -> Bool {
        let b = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        guard b.waitForExistence(timeout: 10), b.isHittable else { return false }
        b.tap()
        return true
    }

    private func bikeBoxShows(_ word: String) -> Bool {
        let box = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Fahrrad:")).firstMatch
        return box.exists && ((box.value as? String) ?? "").contains(word)
    }

    private func keep(_ name: String) {
        shot += 1
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = String(format: "%d-%@", shot, name)
        a.lifetime = .keepAlways
        add(a)
    }
}
