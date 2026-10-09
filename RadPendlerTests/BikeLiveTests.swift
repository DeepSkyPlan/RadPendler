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

    /// Was eine Planung ans Netz schickt, kalt und gleich noch einmal:
    ///
    ///     TEST_RUNNER_PLAN_LIVE=1 [TEST_RUNNER_BIKE_FROM=… TEST_RUNNER_BIKE_TO=…] ./dev test
    func testWhatAPlanAsksTheNetwork() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PLAN_LIVE"] == "1", "set PLAN_LIVE=1")
        func place(_ key: String, _ name: String, _ lat: Double, _ lon: Double) -> Place {
            let parts = (ProcessInfo.processInfo.environment[key] ?? "").split(separator: ",").compactMap { Double($0) }
            return Place(name: name, latitude: parts.count == 2 ? parts[0] : lat, longitude: parts.count == 2 ? parts[1] : lon)
        }
        let req = PlanRequest(origin: place("BIKE_FROM", "Start", 52.5210, 13.4130),
                              destination: place("BIKE_TO", "Ziel", 52.3914, 13.0672),
                              target: .departAfter(.now), settings: PlanSettings())
        let planner = TripPlanner()
        for (round, only) in [("Rad, kalt", TravelMode.bike), ("Rad, gleich noch einmal", .bike),
                              ("alle vier, danach", nil)] as [(String, TravelMode?)] {
            RequestSpy.start()
            let began = Date()
            let result = await planner.plan(req, only: only)
            let seconds = Date().timeIntervalSince(began)
            let log = RequestSpy.stop()
            print(String(format: "PLAN == %@: %.1f s, %d Anfragen, %d kB, %d Möglichkeiten", round, seconds, log.count,
                         log.map(\.bytes).reduce(0, +) / 1000, result.options.count))
            for e in log.sorted(by: { $0.at < $1.at }) {
                print(String(format: "PLAN   +%4.1f s  %4.1f s  %3d  %5d kB  %@  %@", e.at, e.seconds, e.status,
                             e.bytes / 1000, e.host, e.what))
            }
            for o in result.options where o.mode == .bike {
                print("PLAN   Rad:", o.bikeRoute?.source.label ?? "?", o.bikeRoute?.variants.map(\.rawValue) ?? [],
                      "Ampeln \(o.bikeRoute?.stats?.signals ?? -1)")
            }
        }
        // Die App bleibt nach dem Planen offen; was neben der Planung noch
        // geholt wird, soll ankommen dürfen, bevor der Prozess endet.
        RequestSpy.start()
        try? await Task.sleep(for: .seconds(Double(ProcessInfo.processInfo.environment["PLAN_LINGER"] ?? "0") ?? 0))
        for e in RequestSpy.stop() {
            print(String(format: "PLAN   danach: %4.1f s  %3d  %5d kB  %@  %@", e.seconds, e.status, e.bytes / 1000, e.host, e.what))
        }
        for e in Log.recent { print("PLAN stumm:", e.what, e.error) }
    }
}
