import CoreLocation
import XCTest
@testable import Pendel

final class BikeRouteTests: XCTestCase {
    /// Metres → coordinates around the office (x east, y north).
    private func c(_ x: Double, _ y: Double) -> CLLocationCoordinate2D {
        let f = Flat(latitude: 52.5)
        return CLLocationCoordinate2D(latitude: 52.5 + y / f.ky, longitude: 13.3 + x / f.kx)
    }

    func testCrossingSignalAndAlongRoad() {
        // Route: 1 km due north. A main road crosses it east–west at y = 300
        // (with a signal), a second main road runs beside it (x = 10) from y = 600 to 900.
        let route = stride(from: 0.0, through: 1000, by: 20).map { c(0, $0) }
        let data = RoadData(
            signals: [c(3, 302), c(-4, 296), c(500, 500)],   // two nodes of one junction + one far away
            roads: [.init(name: "B 1", points: [c(-300, 300), c(300, 300)]),
                    .init(name: "Clayallee", points: [c(10, 600), c(10, 900)])])
        let st = RouteAnalyzer.analyze(route, roads: data)
        XCTAssertEqual(st.crossings, ["B 1"], "riding beside Clayallee is not a crossing")
        XCTAssertEqual(st.signals, 1, "signal nodes of one junction count once")
        XCTAssertEqual(st.mainRoadMeters, 340, accuracy: 60)   // ~300 m beside Clayallee + ~40 m at the B 1
    }

    func testDualCarriagewayCountsOnce() {
        let route = stride(from: 0.0, through: 1000, by: 20).map { c(0, $0) }
        let data = RoadData(signals: [], roads: [
            .init(name: "Potsdamer Chaussee", points: [c(-300, 400), c(300, 400)]),
            .init(name: "Potsdamer Chaussee", points: [c(-300, 425), c(300, 425)]),
        ])
        XCTAssertEqual(RouteAnalyzer.analyze(route, roads: data).crossings.count, 1)
    }

    func testCacheBoxSurvivesFloatNoise() {
        let box = RoadDataStore.Box(around: [c(0, 0), CLLocationCoordinate2D(latitude: 52.536, longitude: 13.361),
                                             CLLocationCoordinate2D(latitude: 52.409, longitude: 13.23)])
        XCTAssertEqual(box.key, "52.40_13.20_52.55_13.40")
        let fromDisk = RoadDataStore.Box(south: 52.4, west: 13.2, north: 52.55, east: 13.4)
        XCTAssertTrue(fromDisk.contains(box))
    }

    func testBRouterParse() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "brouter_bike_route", withExtension: "json"))
        let r = try BRouterClient.parse(Data(contentsOf: url))
        XCTAssertEqual(r.distance, 19663)
        XCTAssertGreaterThan(r.coordinates.count, 500)
        XCTAssertEqual(r.coordinates.first!.latitude, 52.536, accuracy: 0.002)
        XCTAssertEqual(r.coordinates.last!.latitude, 52.409, accuracy: 0.002)
    }

    private func candidate(_ name: String, km: Double, signals: Int, crossings: Int, mainKm: Double) -> BikeCandidate {
        BikeCandidate(source: name, route: StreetRoute(distance: km * 1000, expectedTravelTime: 0, coordinates: []),
                      stats: BikeRouteStats(signals: signals, crossings: Array(repeating: "B 1", count: crossings),
                                            mainRoadMeters: mainKm * 1000))
    }

    func testPickFastestBalancedQuiet() {
        let s = PlanSettings()
        // Fastest is not the shortest here: 19.7 km with 45 lights beats
        // 19.5 km with 50 at 20 s each.
        let short = candidate("fastbike", km: 19.5, signals: 55, crossings: 18, mainKm: 13.5)
        let middle = candidate("trekking", km: 19.7, signals: 45, crossings: 14, mainKm: 9)
        let quiet = candidate("safety", km: 24.0, signals: 43, crossings: 12, mainKm: 7.6)
        let picked = BikeCandidate.pick([quiet, short, middle], settings: s)
        XCTAssertLessThan(middle.time(s), short.time(s))
        // fastbike is the shortest by distance, trekking the fastest overall.
        XCTAssertEqual(picked.map(\.0.source), ["trekking", "fastbike", "safety"])
        XCTAssertEqual(picked.map(\.1), [[.fastest, .balanced], [.shortest], [.quiet]])
        // Signal waits are part of the riding time: 45 × 20 s = 15 min.
        XCTAssertEqual(middle.time(s), s.bikeTime(19_700) + 900, accuracy: 1)
    }

    func testOneRouteWinningEverythingIsListedOnce() {
        let best = candidate("safety", km: 19, signals: 10, crossings: 2, mainKm: 1)
        let worse = candidate("fastbike", km: 20, signals: 50, crossings: 18, mainKm: 13)
        let picked = BikeCandidate.pick([worse, best], settings: PlanSettings())
        XCTAssertEqual(picked.count, 1)
        XCTAssertEqual(picked[0].1, [.fastest, .shortest, .balanced, .quiet])
    }
}
