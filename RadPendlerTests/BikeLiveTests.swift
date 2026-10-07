import CoreLocation
import XCTest
@testable import RadPendler

/// Fragt BRouter, Apple und Overpass wirklich. Aus, solange `BIKE_LIVE=1`
/// nicht gesetzt ist:
///
///     TEST_RUNNER_BIKE_LIVE=1 ./dev test   (xcodebuild reicht nur Variablen mit diesem Vorsatz durch)
final class BikeLiveTests: XCTestCase {
    func testLiveBikeVariants() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BIKE_LIVE"] == "1", "set BIKE_LIVE=1")
        // Dieselbe Strecke wie die Store-Aufnahmen: Alexanderplatz → Potsdam Hbf.
        let from = Place(name: "Start", latitude: 52.5210, longitude: 13.4130)
        let to = Place(name: "Ziel", latitude: 52.3914, longitude: 13.0672)
        let s = PlanSettings()
        let req = PlanRequest(origin: from, destination: to, target: .departAfter(.now), settings: s)
        let options = try await TripPlanner().bikeOptions(req)
        for o in options {
            let st = o.bikeRoute?.stats
            print("LIVE bike:", o.bikeRoute?.source.label ?? "?", o.bikeRoute?.variants.map(\.rawValue) ?? [],
                  "\(Int(o.totalDistance)) m", "\(Int(o.duration / 60)) min",
                  "Ampeln \(st?.signals ?? -1)", "Querungen \(st?.crossings.count ?? -1)",
                  "Hauptstr \(Int(st?.mainRoadMeters ?? -1)) m", o.note ?? "",
                  "Start:", o.legs.first?.coordinates.prefix(160).map { String(format: "%.6f,%.6f", $0.latitude, $0.longitude) }.joined(separator: " ") ?? "")
        }
        XCTAssertGreaterThan(options.count, 1)
    }
}
