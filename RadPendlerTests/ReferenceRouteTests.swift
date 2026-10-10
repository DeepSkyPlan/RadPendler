import CoreLocation
import XCTest
@testable import RadPendler

/// Referenzrouten: was die Planung auf bekannten Strecken ergeben **muss**.
///
/// Die Regeln der Radlinien sind Zahlen in einem Profil — ein Faktor für die
/// Fahrradstraße, ein Aufschlag fürs Pflaster —, und ob sie tun, was sie
/// sollen, zeigt sich nur auf der Straße. Zweimal ist eine Fassung
/// hinausgegangen, in der „optimal" nicht mehr über die Fahrradstraße führte
/// (1.16: Faktor zu klein; 1.17: die Linie stand als namenlose „Alternative"
/// an vierter Stelle). Hier steht fest, was gelten muss, und `./dev testflight`
/// lädt nichts hoch, solange es nicht gilt.
///
/// Fragt BRouter wirklich und ist deshalb sonst aus:
///
///     ./dev routes
///
/// Die Strecken stehen in `Fixtures/referenzrouten.json` — nur öffentliche
/// Orte. Die eigene (der Arbeitsweg) liegt in
/// `~/.config/radpendler/referenzrouten.json`, im selben Format, und kommt
/// über `TEST_RUNNER_REF_PRIVATE` dazu; sie steht nie im Repository.
final class ReferenceRouteTests: XCTestCase {
    struct Rule: Decodable {
        /// So viele Meter der Linie müssen an dieser Straße liegen (`streets`).
        var along: String?
        var alongMeters: Double?
        var minCycleStreetMeters: Double?
        var maxCobbleMeters: Double?
        var maxKm: Double?
    }

    struct Reference: Decodable {
        var name: String
        var from: [Double]
        var to: [Double]
        /// Für die Linie mit der Rolle „optimal".
        var optimal: Rule?
        /// Für die Linie mit der Rolle „ruhig".
        var quiet: Rule?
        /// Für jede Linie, die gezeigt wird.
        var every: Rule?
    }

    struct File: Decodable {
        var streets: [String: [[Double]]]?
        var routes: [Reference]
    }

    func testReferenceRoutes() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["REF_ROUTES"] == "1", "nur über ./dev routes")
        var files = [try load(XCTUnwrap(Bundle(for: Self.self).url(forResource: "referenzrouten", withExtension: "json")))]
        if let path = env["REF_PRIVATE"], !path.isEmpty, FileManager.default.fileExists(atPath: path) {
            files.append(try load(URL(fileURLWithPath: path)))
        }
        let streets = files.reduce(into: [String: [CLLocationCoordinate2D]]()) { all, file in
            for (name, points) in file.streets ?? [:] {
                all[name] = points.compactMap { $0.count == 2 ? CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) : nil }
            }
        }
        // Frisch gefragt, nicht aus dem Zwischenspeicher: geprüft wird, was
        // der Server **heute** auf die Profile dieser Fassung antwortet.
        var planner = TripPlanner()
        planner.brouter.cached = false
        planner.habits = RiddenPaths(file: URL.temporaryDirectory.appending(path: "ridden-\(UUID()).json"))

        for (n, reference) in files.flatMap(\.routes).enumerated() {
            guard reference.from.count == 2, reference.to.count == 2 else { XCTFail("\(reference.name): Start oder Ziel fehlt"); continue }
            // Eigene Strecken ohne ihren Namen im Protokoll: der steht in der
            // privaten Datei, und was hier gedruckt wird, landet in Ausgaben.
            let title = n < files[0].routes.count ? reference.name : "eigene Strecke \(n - files[0].routes.count + 1)"
            let req = PlanRequest(origin: Place(name: "Start", latitude: reference.from[0], longitude: reference.from[1]),
                                  destination: Place(name: "Ziel", latitude: reference.to[0], longitude: reference.to[1]),
                                  target: .departAfter(.now), settings: PlanSettings())
            // Der öffentliche Server ist ein Geschenk: zwischen zwei Strecken
            // eine Pause, damit sechs Strecken nicht als Ansturm ankommen
            // (10.10.2026: drei Läufe kurz hintereinander, und er lehnte die
            // Profile ab).
            if n > 0 { try? await Task.sleep(for: .seconds(2)) }
            let options: [TripOption]
            do {
                options = try await planner.bikeOptions(req)
            } catch {
                XCTFail("\(title): keine Radroute — \(error.localizedDescription)")
                continue
            }
            print("REF == \(title)")
            for option in options {
                guard let info = option.bikeRoute else { continue }
                let line = option.legs.flatMap(\.coordinates)
                let roles = info.variants.map(\.title).joined(separator: " · ")
                var notes: [String] = []
                func check(_ rule: Rule?, _ whose: String) {
                    guard let rule else { return }
                    if let street = rule.along, let need = rule.alongMeters {
                        let got = Self.meters(of: line, along: streets[street] ?? [])
                        notes.append("\(Int(got)) m an \(street)")
                        XCTAssertGreaterThanOrEqual(got, need, "\(title), \(whose): nur \(Int(got)) m an \(street), verlangt \(Int(need))")
                    }
                    if let need = rule.minCycleStreetMeters {
                        XCTAssertGreaterThanOrEqual(info.cycleStreetMeters, need,
                                                    "\(title), \(whose): nur \(Int(info.cycleStreetMeters)) m Fahrradstraße, verlangt \(Int(need))")
                    }
                    if let most = rule.maxCobbleMeters {
                        XCTAssertLessThanOrEqual(info.cobbleMeters, most,
                                                 "\(title), \(whose): \(Int(info.cobbleMeters)) m Kopfsteinpflaster, erlaubt \(Int(most))")
                    }
                    if let most = rule.maxKm {
                        XCTAssertLessThanOrEqual(option.totalDistance / 1000, most,
                                                 "\(title), \(whose): \(String(format: "%.1f", option.totalDistance / 1000)) km, erlaubt \(most)")
                    }
                }
                check(reference.every, "„\(roles)“")
                if info.variants.contains(.balanced) { check(reference.optimal, "optimal") }
                if info.variants.contains(.quiet) { check(reference.quiet, "ruhig") }
                print(String(format: "REF   %@: %.1f km · Fahrradstraße %.1f km · Pflaster %d m%@",
                             roles.padding(toLength: 22, withPad: " ", startingAt: 0), option.totalDistance / 1000,
                             info.cycleStreetMeters / 1000, Int(info.cobbleMeters),
                             notes.isEmpty ? "" : " · " + notes.joined(separator: ", ")))
            }
            if reference.optimal != nil {
                XCTAssertTrue(options.contains { $0.bikeRoute?.variants.contains(.balanced) ?? false }, "\(title): keine Linie heißt „optimal“")
            }
            if reference.quiet != nil {
                XCTAssertTrue(options.contains { $0.bikeRoute?.variants.contains(.quiet) ?? false }, "\(title): keine Linie heißt „ruhig“")
            }
        }
        // Was dabei stumm scheiterte — ein Profil, das sich nicht hochladen
        // ließ, verfälscht jede Zahl darüber.
        for entry in Log.recent where entry.what.hasPrefix("BRouter") || entry.what.hasPrefix("Radroute") {
            XCTFail("BRouter: \(entry.what) (\(entry.error)) — die Linien oben sind nicht die dieser Fassung")
        }
    }

    private func load(_ url: URL) throws -> File {
        try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
    }

    /// Wie viele Meter der Linie höchstens 45 m neben der Straße liegen. Die
    /// Straße ist eine Punktwolke im Abstand von rund 40 m.
    static func meters(of line: [CLLocationCoordinate2D], along street: [CLLocationCoordinate2D]) -> Double {
        guard !street.isEmpty else { return 0 }
        var total = 0.0
        for (a, b) in zip(line, line.dropFirst()) {
            let mid = CLLocationCoordinate2D(latitude: (a.latitude + b.latitude) / 2, longitude: (a.longitude + b.longitude) / 2)
            if street.contains(where: { $0.distance(to: mid) <= 45 }) { total += a.distance(to: b) }
        }
        return total
    }

    /// Das Maß selbst, ohne Netz: eine Linie auf der Straße zählt, eine
    /// daneben nicht.
    func testMetresAlongAStreet() {
        let street = (0...10).map { CLLocationCoordinate2D(latitude: 52.48 + Double($0) * 0.00036, longitude: 13.333) }
        let on = (0...40).map { CLLocationCoordinate2D(latitude: 52.48 + Double($0) * 0.00009, longitude: 13.3331) }
        let beside = on.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: 13.330) }   // 200 m westlich
        XCTAssertEqual(Self.meters(of: on, along: street), 400, accuracy: 15)
        XCTAssertEqual(Self.meters(of: beside, along: street), 0)
    }
}
