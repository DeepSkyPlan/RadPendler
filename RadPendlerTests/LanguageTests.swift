import XCTest
@testable import RadPendler

/// Dass die App überhaupt Englisch kann — und zwar sofort, ohne Neustart.
///
/// Der Weg dahin ist ungewöhnlich (siehe `AppLanguage`), und drei Dinge daran
/// können still kaputtgehen: das Sprachverzeichnis fehlt im Paket, der Katalog
/// kennt einen Schlüssel nicht, oder die Zahlen kommen weiter mit Komma. Alle
/// drei sieht man erst, wenn man die App auf Englisch stellt — also hier.
final class LanguageTests: XCTestCase {
    private var before = AppLanguage.current

    override func setUp() {
        before = AppLanguage.current
    }

    override func tearDown() {
        AppLanguage.current = before
    }

    func testTheEnglishFolderIsInTheBundle() {
        AppLanguage.current = .en
        XCTAssertNotNil(AppLanguage.bundle,
                        "kein en.lproj im Paket — dann findet L(…) nichts und alles bliebe deutsch")
    }

    func testTextsComeBackInEnglish() {
        AppLanguage.current = .en
        XCTAssertEqual(L("Abfahrt"), "Departure")
        XCTAssertEqual(L("Fahrt beenden"), "End ride")
        XCTAssertEqual(L("%d/%d Ampeln", 3, 9), "3/9 lights")
    }

    func testAMissingTranslationFallsBackToTheGermanKey() {
        AppLanguage.current = .en
        XCTAssertEqual(L("Diesen Satz gibt es im Katalog nicht"), "Diesen Satz gibt es im Katalog nicht")
    }

    func testNumbersFollowTheChosenLanguageNotThePhone() {
        AppLanguage.current = .en
        XCTAssertEqual(Fmt.km(1500), "1.5 km")
        XCTAssertEqual(Fmt.kmh(21.3), "21.3 km/h")
        AppLanguage.current = .de
        XCTAssertEqual(Fmt.km(1500), "1,5 km")
        XCTAssertEqual(Fmt.kmh(21.3), "21,3 km/h")
    }

    /// Zurück auf „wie das Telefon" heißt: nichts mehr selbst nachschlagen.
    func testSystemMeansNoBundleOfItsOwn() {
        AppLanguage.current = .system
        XCTAssertNil(AppLanguage.bundle)
    }
}
