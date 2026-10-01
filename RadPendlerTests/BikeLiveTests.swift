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
        let req = PlanRequest(origin: from, destination: to, target: .departAfter(.now), settings: s)
        let options = try await TripPlanner().bikeOptions(req)
        for o in options {
            let st = o.bikeRoute?.stats
            print("LIVE bike:", o.bikeRoute?.source.label ?? "?", o.bikeRoute?.variants.map(\.rawValue) ?? [],
                  "\(Int(o.totalDistance)) m", "\(Int(o.duration / 60)) min",
                  "Ampeln \(st?.signals ?? -1)", "Querungen \(st?.crossings.count ?? -1)",
                  "Hauptstr \(Int(st?.mainRoadMeters ?? -1)) m", o.note ?? "")
        }
        XCTAssertGreaterThan(options.count, 1)
    }
}
