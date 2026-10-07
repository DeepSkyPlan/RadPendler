import XCTest
@testable import RadPendler

/// Was die App im Hintergrund darf, steht in der Info.plist — und dort fällt
/// ein Fehler nicht auf: eine Kennung mit einem Tippfehler lehnt iOS stumm ab,
/// ein Modus zu viel ist eine Frage im App Review, einer zu wenig eine Fahrt
/// ohne Aufzeichnung, sobald der Bildschirm ausgeht.
///
/// Die Tests laufen in der App selbst, `Bundle.main` ist also ihre Info.plist.
final class BackgroundModeTests: XCTestCase {
    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    /// Genau diese drei, jeder mit seinem Grund: `location` für die
    /// Aufzeichnung (`RideTracker`), `fetch` für das Nachstellen der Warnungen
    /// (`BackgroundReplan`), `audio` für die Abbiegetöne (`RideSounds`). Wer
    /// einen vierten braucht, schreibt hier den Grund dazu — und in die
    /// Hinweise für die App-Prüfung (`appstore/metadata.md`).
    func testExactlyTheBackgroundModesThatHaveAReason() {
        let modes = Set(info["UIBackgroundModes"] as? [String] ?? [])
        XCTAssertEqual(modes, ["location", "fetch", "audio"])
    }

    func testTheWakeUpTaskIsRegisteredUnderTheNameTheCodeUses() {
        let permitted = info["BGTaskSchedulerPermittedIdentifiers"] as? [String] ?? []
        XCTAssertEqual(permitted, [BackgroundReplan.taskID])
    }

    /// „Beim Verwenden", nie „Immer": die App verfolgt niemanden außerhalb
    /// einer Fahrt, also fragt sie auch nicht danach.
    func testTheAppOnlyEverAsksForLocationWhileInUse() {
        let why = info["NSLocationWhenInUseUsageDescription"] as? String ?? ""
        XCTAssertFalse(why.isEmpty, "ohne Begründung stürzt die erste Abfrage ab")
        XCTAssertNil(info["NSLocationAlwaysAndWhenInUseUsageDescription"])
        XCTAssertNil(info["NSLocationAlwaysUsageDescription"])
    }

    /// Geweckt ohne etwas zu zählen: nichts fragen, nichts stellen, fertig.
    @MainActor func testWokenWithoutAQuestionTheAppDoesNothing() async {
        let before = BackgroundReplan.remembered
        defer { BackgroundReplan.remember(before) }
        BackgroundReplan.remember(nil)
        let clock = ContinuousClock()
        let took = await clock.measure { await BackgroundReplan.run() }
        XCTAssertLessThan(took, .seconds(1), "keine Frage, also auch kein Netz")
    }

    /// Der Zwischenspeicher der Straßendaten muss lesbar sein, während das
    /// Telefon gesperrt in der Tasche steckt — genau dann wird neu geplant.
    func testTheRoadCacheCanBeReadWhileTheDeviceIsLocked() {
        XCTAssertEqual(RoadDataStore.protection, .completeFileProtectionUntilFirstUserAuthentication)
    }
}
