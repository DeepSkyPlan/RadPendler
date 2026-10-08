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
        // Ohne Angabe dieselbe Strecke wie die Store-Aufnahmen: Alexanderplatz →
        // Potsdam Hbf. Eine andere kommt von außen und steht nie hier:
        //     TEST_RUNNER_BIKE_FROM=lat,lon TEST_RUNNER_BIKE_TO=lat,lon
        func place(_ key: String, _ name: String, _ lat: Double, _ lon: Double) -> Place {
            let parts = (ProcessInfo.processInfo.environment[key] ?? "").split(separator: ",").compactMap { Double($0) }
            return Place(name: name, latitude: parts.count == 2 ? parts[0] : lat, longitude: parts.count == 2 ? parts[1] : lon)
        }
        let from = place("BIKE_FROM", "Start", 52.5210, 13.4130)
        let to = place("BIKE_TO", "Ziel", 52.3914, 13.0672)
        let s = PlanSettings()
        let req = PlanRequest(origin: from, destination: to, target: .departAfter(.now), settings: s)
        let options = try await TripPlanner().bikeOptions(req)
        for o in options {
            let st = o.bikeRoute?.stats
            print("LIVE bike:", o.bikeRoute?.source.label ?? "?", o.bikeRoute?.variants.map(\.rawValue) ?? [],
                  "\(Int(o.totalDistance)) m", "\(Int(o.duration / 60)) min",
                  "Fahrradstr \(Int(o.bikeRoute?.cycleStreetMeters ?? -1)) m",
                  "Ampeln \(st?.signals ?? -1)", "Querungen \(st?.crossings.count ?? -1)",
                  "Hauptstr \(Int(st?.mainRoadMeters ?? -1)) m", o.note ?? "",
                  "Start:", o.legs.first?.coordinates.prefix(160).map { String(format: "%.6f,%.6f", $0.latitude, $0.longitude) }.joined(separator: " ") ?? "")
        }
        for e in Log.recent { print("LIVE stumm:", e.what, e.error) }
        XCTAssertGreaterThan(options.count, 1)
    }
}
