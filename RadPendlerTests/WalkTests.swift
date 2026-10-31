import CoreLocation
import XCTest
@testable import RadPendler

/// Der Fußweg zur Haltestelle: über die Straßen geplant, mit Beleuchtung.
final class WalkTests: XCTestCase {
    private let alex = CLLocationCoordinate2D(latitude: 52.5210, longitude: 13.4130)
    private let stop = CLLocationCoordinate2D(latitude: 52.5250, longitude: 13.4180)
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func journey(at t0: Date? = nil) -> [Leg] {
        let t0 = t0 ?? self.t0
        return [Leg(kind: .walk, fromName: "Start", toName: "S Alexanderplatz",
             departure: t0, arrival: t0.addingTimeInterval(400), distance: 500, coordinates: [alex, stop]),
         Leg(kind: .transit(line: "S7", product: .suburban), fromName: "S Alexanderplatz", toName: "S Wannsee",
             departure: t0.addingTimeInterval(500), arrival: t0.addingTimeInterval(2500),
             coordinates: [stop, alex]),
         Leg(kind: .walk, fromName: "S Wannsee", toName: "Ziel",
             departure: t0.addingTimeInterval(2500), arrival: t0.addingTimeInterval(2700), distance: 250,
             coordinates: [alex, stop])]
    }

    /// 31.10.2026, Sonnenuntergang am Alexanderplatz 16:37 Uhr (15:37 UTC).
    private let dusk = Date(timeIntervalSince1970: 1_793_461_020)
    private var night: Date { dusk.addingTimeInterval(3 * 3600) }

    func testItIsDarkFromSunsetToSunrise() {
        XCTAssertFalse(Sun.isDark(at: dusk.addingTimeInterval(-15 * 60), alex))
        XCTAssertTrue(Sun.isDark(at: dusk.addingTimeInterval(15 * 60), alex))
        XCTAssertTrue(Sun.isDark(at: night, alex))
        // Mittag im Sommer: hoch oben.
        XCTAssertGreaterThan(Sun.elevation(at: Date(timeIntervalSince1970: 1_782_043_200), alex), 55)
    }

    func testLitPathsOnlyCountInTheDark() {
        let day = journey(at: dusk.addingTimeInterval(-4 * 3600))[0]
        let dark = journey(at: night)[0]
        XCTAssertEqual(TripPlanner.walk(day, onlyLit: true)?.lit, false, "bei Tag gilt der kurze Weg")
        XCTAssertEqual(TripPlanner.walk(dark, onlyLit: true)?.lit, true)
        XCTAssertEqual(TripPlanner.walk(dark, onlyLit: false)?.lit, false)
    }

    func testDarkMeansUnlitOrAPathWithoutAnyNote() {
        XCTAssertTrue(BRouterClient.isDark("highway=residential lit=no"))
        XCTAssertTrue(BRouterClient.isDark("highway=footway"))
        XCTAssertTrue(BRouterClient.isDark("highway=path surface=ground"))
        XCTAssertFalse(BRouterClient.isDark("highway=footway lit=yes"))
        XCTAssertFalse(BRouterClient.isDark("highway=residential"))
        XCTAssertFalse(BRouterClient.isDark("reversedirection=yes highway=steps lit=24/7"))
    }

    func testOnlyTheWalksToTheFirstAndFromTheLastTrainAreRouted() {
        var legs = journey()
        legs.insert(Leg(kind: .walk, fromName: "S Wannsee", toName: "S Wannsee",
                        departure: t0.addingTimeInterval(2500), arrival: t0.addingTimeInterval(2600),
                        coordinates: [alex, stop]), at: 2)
        legs.insert(Leg(kind: .transit(line: "RE1", product: .regional), fromName: "S Wannsee", toName: "Ziel",
                        departure: t0.addingTimeInterval(2600), arrival: t0.addingTimeInterval(2650),
                        coordinates: [stop, alex]), at: 3)
        XCTAssertEqual(TripPlanner.accessWalks(legs), [0, 4], "der Umsteigeweg bleibt")
    }

    func testALongerWalkStartsEarlierAtTheTimetablesPace() {
        let route = StreetRoute(distance: 750, expectedTravelTime: 540,
                                coordinates: [alex, stop, alex], darkMeters: 120)
        let legs = journey()
        let first = TripPlanner.walked(legs[0], on: route, before: true)
        XCTAssertEqual(first.arrival, legs[0].arrival, "der Zug fährt, wann er fährt")
        // 500 m in 400 s → 750 m in 600 s.
        XCTAssertEqual(first.departure.timeIntervalSince(legs[0].departure), -200, accuracy: 0.5)
        XCTAssertEqual(first.coordinates.count, 3)
        XCTAssertEqual(first.darkMeters, 120)

        let last = TripPlanner.walked(legs[2], on: route, before: false)
        XCTAssertEqual(last.departure, legs[2].departure)
        XCTAssertEqual(last.arrival.timeIntervalSince(legs[2].departure), 600, accuracy: 0.5)
    }

    func testWithoutBRouterTheWalkStaysAsTheTimetableSentIt() async {
        let walked = await TripPlanner.offline.walkedOnStreets([journey()], onlyLit: true)
        XCTAssertEqual(walked[0].map(\.coordinates.count), [2, 2, 2])
        XCTAssertNil(walked[0][0].darkMeters)
    }

    func testTheLitProfileIsTheFootProfileWithOnlyLitOn() throws {
        let url = try XCTUnwrap(Bundle(for: AppSettings.self).url(forResource: "radpendler-foot", withExtension: "brf"))
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("assign onlyLit = false"), "die App schaltet genau diese Zeile um")
        XCTAssertEqual(CustomProfile.Kind(profile: .footLit, withoutCobbles: true).resource, "radpendler-foot")
    }

    /// Echt gegen brouter.de: `TEST_RUNNER_WALK_LIVE=1 ./dev test`.
    func testLiveTheLitWalkHasNoDarkMetres() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["WALK_LIVE"] == "1", "set WALK_LIVE=1")
        var planner = TripPlanner()
        planner.brouter.cached = false
        let plain = await planner.walkedOnStreets([journey(at: night)], onlyLit: false)[0][0]
        let lit = await planner.walkedOnStreets([journey(at: night)], onlyLit: true)[0][0]
        print("Fußweg: \(plain.length ?? 0) m, dunkel \(plain.darkMeters ?? -1) m; beleuchtet: \(lit.length ?? 0) m, dunkel \(lit.darkMeters ?? -1) m")
        XCTAssertGreaterThan(plain.coordinates.count, 2)
        XCTAssertNotNil(lit.darkMeters)
        XCTAssertLessThanOrEqual(lit.darkMeters ?? .infinity, plain.darkMeters ?? 0)
    }
}
