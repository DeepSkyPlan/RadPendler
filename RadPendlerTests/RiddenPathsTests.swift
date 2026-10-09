import CoreLocation
import XCTest
@testable import RadPendler

/// Aus den eigenen Fahrten lernen, welche Straßen man nimmt. Neutrale
/// Geometrie — keine Adresse des Nutzers in diesem Repository.
final class RiddenPathsTests: XCTestCase {
    private let base = CLLocationCoordinate2D(latitude: 52.50, longitude: 13.40)

    /// Metres north and east of `base`.
    private func p(_ north: Double, _ east: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: base.latitude + north / 111_320,
                               longitude: base.longitude + east / (111_320 * cos(base.latitude * .pi / 180)))
    }

    /// Nach Norden, auf der Straße `east` Meter östlich — alle 100 m ein Punkt.
    private func street(_ east: Double, length: Double = 5_000) -> [CLLocationCoordinate2D] {
        stride(from: 0.0, through: length, by: 100).map { p($0, east) }
    }

    func testFamiliarShareCountsMetresOnRiddenWays() {
        let ridden = [street(0)]
        XCTAssertEqual(RiddenPaths.familiarShare(street(10), ridden: ridden), 1, accuracy: 0.01,
                       "zehn Meter daneben ist dieselbe Straße")
        XCTAssertEqual(RiddenPaths.familiarShare(street(300), ridden: ridden), 0, accuracy: 0.01)
        // Halb auf der gefahrenen, halb eine Parallelstraße.
        let half = street(0, length: 2_500) + street(300, length: 5_000).filter { $0.latitude > p(2_500, 0).latitude }
        XCTAssertEqual(RiddenPaths.familiarShare(half, ridden: ridden), 0.5, accuracy: 0.1)
    }

    func testTheTypicalRideIsTheOneTheOthersAgreeWith() {
        let usual = street(0)
        let again = street(15)
        let detour = street(0, length: 2_000) + street(800, length: 5_000).dropFirst(21)
        XCTAssertEqual(RiddenPaths.typical([detour, usual, again])?.first?.longitude, usual.first?.longitude)
        XCTAssertNil(RiddenPaths.typical([usual]), "eine Fahrt ist noch keine Gewohnheit")
    }

    func testRidesMatchTheTripInBothDirections() {
        let there = street(0)
        let back = Array(street(20).reversed())
        let elsewhere = street(3_000)
        let found = RiddenPaths.matching([there, back, elsewhere], from: p(0, 0), to: p(5_000, 0))
        XCTAssertEqual(found.count, 2)
        XCTAssertTrue(found.allSatisfy { $0.first!.distance(to: p(0, 0)) < 100 }, "die Rückfahrt kommt umgedreht")
    }

    func testViaPointsSitAlongTheLine() {
        let via = RiddenPaths.via(street(0))
        XCTAssertEqual(via.count, 4)
        XCTAssertEqual(via[0].distance(to: p(1_000, 0)), 0, accuracy: 60)
        XCTAssertEqual(via[3].distance(to: p(4_000, 0)), 0, accuracy: 60)
    }

    func testOnlyBikeRidesAreKeptAndDeletingForgets() async {
        let file = URL.temporaryDirectory.appending(path: "ridden-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let paths = RiddenPaths(file: file)
        func ride(_ mode: String) -> (Ride, RideTrack) {
            let id = UUID()
            let r = Ride(id: id, started: .now, ended: .now.addingTimeInterval(900), origin: "A", destination: "B",
                         mode: mode, meters: 5_000, movingSeconds: 800, maxKmh: 30, signalStops: 0,
                         otherStops: 0, signalWaitTotal: 0)
            let t = RideTrack(id: id, points: street(0).map { RidePoint(lat: $0.latitude, lon: $0.longitude, t: .now, v: 6) })
            return (r, t)
        }
        let bike = ride("bike"), car = ride("car")
        await paths.add(bike.0, track: bike.1)
        await paths.add(car.0, track: car.1)
        let count = await paths.count
        XCTAssertEqual(count, 1)
        // Und von der Platte, nicht aus dem Speicher.
        let reread = await RiddenPaths(file: file).matching(from: p(0, 0), to: p(5_000, 0))
        XCTAssertEqual(reread.count, 1)
        await paths.remove(bike.0.id)
        let after = await paths.count
        XCTAssertEqual(after, 0)
    }

    /// Die gewohnte Linie steht für sich: sie nimmt keiner der vier ihre
    /// Rolle, und sie ist immer da, wenn es sie gibt. Bis 1.17 gewann sie
    /// „optimal" oder füllte einen freien Platz — je nachdem, und damit sah
    /// der Rad-Kasten bei jeder Planung anders aus (Nutzer, 09.10.2026).
    func testTheHabitualLineStandsForItself() {
        let s = PlanSettings()
        func cand(_ name: BikeLineSource, km: Double, mainKm: Double, familiar: Double,
                  east: Double = 0) -> BikeCandidate {
            // Eine eigene Linie je Kandidat, damit zwei nicht als dieselbe gelten.
            let line = (0...20).map { CLLocationCoordinate2D(latitude: 52.42 + Double($0) * 0.005, longitude: 13.18 + east) }
            return BikeCandidate(source: name, route: StreetRoute(distance: km * 1000, expectedTravelTime: 0, coordinates: line),
                                 stats: BikeRouteStats(signals: 30, crossings: [], mainRoadMeters: mainKm * 1000),
                                 familiar: familiar)
        }
        let direct = cand(.brouter(.shortest), km: 19, mainKm: 3, familiar: 0.2)
        let mix = cand(.brouter(.trekking), km: 19.8, mainKm: 5, familiar: 0.1, east: 0.01)
        let usual = cand(.habit, km: 20.5, mainKm: 12, familiar: 0.95, east: 0.02)
        let picked = BikeCandidate.pick([direct, usual, mix], settings: s)
        XCTAssertEqual(picked.first { $0.1.contains(.balanced) }?.0.source, .brouter(.trekking),
                       "„optimal“ bleibt die Mischlinie, auch wenn man sonst anders fährt")
        XCTAssertEqual(picked.last?.0.source, .habit)
        XCTAssertEqual(picked.last?.1, [.alternative], "ohne Rolle — auf dem Bildschirm heißt das „gewohnt“")
        let info = BikeRouteInfo(variants: [.alternative], stats: nil, source: .habit)
        XCTAssertEqual(info.shortTitle, L("gewohnt"), "keine „Alternative“, sondern die eigene")

        // Fährt man ohnehin eine der vier, steht sie nicht zweimal da.
        let same = cand(.habit, km: 19.8, mainKm: 5, familiar: 0.95, east: 0.01)
        let once = BikeCandidate.pick([direct, same, mix], settings: s)
        XCTAssertFalse(once.contains { $0.0.source == .habit })
        XCTAssertEqual(once.count, 2)

        // Und über die vier Plätze hinaus: sie kostet keiner Rolle den ihren.
        var full = s
        full.bikeOptions = 2
        XCTAssertEqual(BikeCandidate.pick([direct, usual, mix], settings: full).count, 3)
    }
}

// MARK: Fixpunkte je Strecke

final class RouteWaypointTests: XCTestCase {
    private func settings() -> (AppSettings, UserDefaults, String) {
        let suite = "wp-\(UUID())"
        let d = UserDefaults(suiteName: suite)!
        return (AppSettings(defaults: d), d, suite)
    }
    private let home = Place(name: "A", latitude: 52.42, longitude: 13.18)
    private let work = Place(name: "B", latitude: 52.52, longitude: 13.41)
    private let bakery = Place(name: "C", latitude: 52.45, longitude: 13.30)
    private let korso = Place(name: "Korso", latitude: 52.47, longitude: 13.32)

    func testAFixedPointBelongsToItsRouteInBothDirections() {
        let (s, _, suite) = settings()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        s.origin = home; s.destination = work
        s.waypoints = [korso]
        s.swapDirection()
        XCTAssertEqual(s.waypoints, [korso], "zurück über denselben Korso")
        s.destination = bakery
        XCTAssertEqual(s.waypoints, [], "zum Bäcker gilt er nicht")
        // Jetzt wieder B → A, nur 150 m neben der Haustür.
        s.destination = Place(name: "A, ein Stück weiter", latitude: 52.421, longitude: 13.181)
        XCTAssertEqual(s.waypoints, [korso], "150 m neben dem Ziel ist dasselbe Ziel")
    }

    func testTheOldGlobalFixedPointsMoveToTheCurrentRoute() throws {
        let suite = "wp-\(UUID())"
        let d = UserDefaults(suiteName: suite)!
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        d.set(try JSONEncoder().encode(home), forKey: "origin")
        d.set(try JSONEncoder().encode(work), forKey: "destination")
        d.set(try JSONEncoder().encode([korso]), forKey: "waypoints")
        let s = AppSettings(defaults: d)
        XCTAssertEqual(s.waypoints, [korso])
        XCTAssertNil(d.data(forKey: "waypoints"))
        XCTAssertEqual(AppSettings(defaults: d).waypoints, [korso], "und bleiben nach dem nächsten Start")
    }
}
