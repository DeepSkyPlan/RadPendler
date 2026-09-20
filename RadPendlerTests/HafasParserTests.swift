import CoreLocation
import XCTest
@testable import RadPendler

final class HafasParserTests: XCTestCase {
    private func fixture(_ name: String) throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try HafasParser.serviceResult(Data(contentsOf: url))
    }

    private func berlin(_ day: String, _ time: String) -> Date {
        HafasTime.date(day: day, time: time)!
    }

    func testBikeJourneysAreAllRailWithBikeCarriage() throws {
        let journeys = try HafasParser.journeys(fixture("trip_bike_stations"))
        XCTAssertEqual(journeys.count, 2)
        for legs in journeys {
            let transit = legs.filter(\.isTransit)
            XCTAssertFalse(transit.isEmpty)
            XCTAssertTrue(transit.allSatisfy(\.bikeCarriage), "every train must carry bikes")
            XCTAssertTrue(transit.allSatisfy { $0.lineName?.hasPrefix("S") == true }, "\(transit.map(\.lineName))")
            XCTAssertTrue(transit.allSatisfy { $0.coordinates.count > 2 }, "polyline decoded")
        }
        let first = journeys[0].filter(\.isTransit)
        XCTAssertEqual(first.first?.fromName, "S+U Berlin Hauptbahnhof")
        XCTAssertEqual(first.last?.toName, "S Beispielplatz (Berlin)")
        XCTAssertEqual(first.first?.departure, berlin("20260921", "171700"))
    }

    func testAddressJourneyKeepsWalksAndMarksBusWithoutBikeCarriage() throws {
        let journeys = try HafasParser.journeys(fixture("trip_address_plain"))
        XCTAssertGreaterThanOrEqual(journeys.count, 3)
        let legs = journeys[0]
        XCTAssertEqual(legs.first?.kind, .walk)
        XCTAssertEqual(legs.last?.kind, .walk)
        XCTAssertNotNil(legs.first?.distance)
        let buses = journeys.flatMap { $0 }.filter {
            if case .transit(_, .bus) = $0.kind { true } else { false }
        }
        XCTAssertFalse(buses.isEmpty, "Musterort is reached by bus without a bike")
        XCTAssertTrue(buses.allSatisfy { !$0.bikeCarriage })
        // Legs are chronological.
        for legs in journeys {
            for (a, b) in zip(legs, legs.dropFirst()) {
                XCTAssertLessThanOrEqual(a.departure, b.departure)
            }
        }
    }

    func testNearbyStationsAreRailOnlyDedupedAndSorted() throws {
        let stations = HafasParser.stations(try fixture("nearby_suburb"), productMask: TransitProduct.bikeStationMask)
        XCTAssertFalse(stations.isEmpty)
        XCTAssertEqual(stations.map(\.distance), stations.map(\.distance).sorted())
        XCTAssertEqual(Set(stations.map { HafasParser.baseName($0.name) }).count, stations.count)
        XCTAssertTrue(stations.allSatisfy { $0.productMask & TransitProduct.bikeStationMask != 0 })
        XCTAssertTrue(stations.contains { $0.name.contains("Beispielplatz") })
    }

    func testDayOffsetRollsOverMidnight() {
        let late = HafasTime.date(day: "20260921", time: "235000")!
        let next = HafasTime.date(day: "20260921", time: "01002500")!
        XCTAssertEqual(next.timeIntervalSince(late), 35 * 60)
    }

    func testFormatIsBerlinLocalTime() {
        // 2026-09-21 15:15 UTC = 17:15 CEST
        let d = Date(timeIntervalSince1970: 1_790_003_700)   // 2026-09-21 15:15 UTC
        let (day, time) = HafasTime.format(d)
        XCTAssertEqual(day, "20260921")
        XCTAssertEqual(time, "171500")
    }

    func testPolylineDecodesGoogleReferenceExample() {
        let c = Polyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        XCTAssertEqual(c.count, 3)
        XCTAssertEqual(c[0].latitude, 38.5, accuracy: 1e-6)
        XCTAssertEqual(c[0].longitude, -120.2, accuracy: 1e-6)
        XCTAssertEqual(c[2].latitude, 43.252, accuracy: 1e-6)
        XCTAssertEqual(c[2].longitude, -126.453, accuracy: 1e-6)
    }

    func testBikeCarriageRemarks() {
        XCTAssertTrue(HafasParser.bikeCarriage([["code": "FK", "txtN": "Fahrradmitnahme möglich (S Ostbahnhof)"]]))
        XCTAssertFalse(HafasParser.bikeCarriage([["code": "OPERATOR", "txtN": "BVG"]]))
        XCTAssertFalse(HafasParser.bikeCarriage([["code": "FK", "txtN": "Fahrradmitnahme möglich"],
                                                 ["code": "XX", "txtN": "Keine Fahrradmitnahme 6–9 Uhr"]]))
    }
}
