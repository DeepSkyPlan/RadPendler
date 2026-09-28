import CoreLocation
import XCTest
@testable import RadPendler

/// Fragt BRouter, Apple und Overpass wirklich. Aus, solange `BIKE_LIVE=1`
/// nicht gesetzt ist:
///
///     BIKE_LIVE=1 ./dev test
final class BikeLiveTests: XCTestCase {
    func testLiveBikeVariants() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BIKE_LIVE"] == "1", "set BIKE_LIVE=1")
        let from = Place(name: "Start", latitude: 52.4020, longitude: 13.2600)
        let to = Place(name: "Ziel", latitude: 52.5363, longitude: 13.3610)
        var s = PlanSettings()
        s.optionsPerMode = 3
        s.bikeVariantOrder = [.quiet, .lowTraffic, .balanced, .fastest, .shortest]
        let req = PlanRequest(origin: from, destination: to, target: .departAfter(.now), settings: s)
        var b = BRouterClient(); b.cached = false
        for p in [BRouterClient.Profile.quiet, .lowTraffic, .trekking] {
            do { let r = try await b.route(from: from.coordinate, to: to.coordinate, profile: p); print("LIVE direct", p.rawValue, Int(r.distance)) }
            catch { print("LIVE direct", p.rawValue, "ERROR", error) }
        }
        let options = try await TripPlanner().bikeOptions(req)
        for o in options {
            print("LIVE bike:", o.bikeRoute?.source ?? "?", o.bikeRoute?.variants.map(\.rawValue) ?? [],
                  Int(o.totalDistance), o.note ?? "")
        }
        XCTAssertGreaterThan(options.count, 1)
    }
}
