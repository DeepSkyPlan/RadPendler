import CoreLocation
import MapKit
import XCTest
@testable import RadPendler

final class MotisTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testBikeToStationTrainBikeOnwards() throws {
        let journeys = try MotisParser.journeys(fixture("motis_bike_transit"))
        XCTAssertEqual(journeys.count, 2)
        let legs = try XCTUnwrap(journeys.first)
        XCTAssertEqual(legs.map(\.kind.short), ["bike", "transit", "bike"],
                       "MOTIS plans the whole way, stations included")
        let train = try XCTUnwrap(legs.first(where: \.isTransit))
        XCTAssertEqual(train.lineName, "S7")
        XCTAssertEqual(train.fromName, "S+U Alexanderplatz Bhf (Berlin)")
        XCTAssertEqual(train.direction, "S Potsdam Hauptbahnhof")
        XCTAssertEqual(train.departurePlatform, "4", "read out of „S-Bahnsteig Gleis 4“")
        XCTAssertEqual(train.arrivalPlatform, "2", "this end has it as a field")
        XCTAssertEqual(train.bikeCarriage, .yes, "this feed does say the S-Bahn takes bikes")
        if case .transit(_, let p) = train.kind { XCTAssertEqual(p, .suburban) } else { XCTFail() }
        // The first ride starts at the door, so it has a length and a line.
        XCTAssertEqual(legs.first?.distance ?? 0, 167, accuracy: 1)
        XCTAssertGreaterThan(legs.first!.coordinates.count, 2)
        XCTAssertEqual(legs.first!.coordinates[0].latitude, 52.521, accuracy: 0.01)
    }

    func testLongDistanceIsRecognisedAndItsBikeCarriageStaysOpen() throws {
        let journeys = try MotisParser.journeys(fixture("motis_long_distance"))
        let legs = try XCTUnwrap(journeys.first)
        let ice = try XCTUnwrap(legs.first { $0.lineName?.hasPrefix("ICE") == true })
        if case .transit(_, let p) = ice.kind { XCTAssertEqual(p, .express) } else { XCTFail() }
        XCTAssertEqual(ice.lineName, "ICE 870", "the line keeps its number, only the trip id is dropped")
        // The feed's bikes_allowed is false, which for GTFS means "unset" far
        // more often than "no" — so it must stay a question, not become a no.
        XCTAssertEqual(ice.bikeCarriage, .unknown)
        XCTAssertTrue(legs.contains { $0.kind == .walk }, "walking access when no bike was asked for")
    }

    func testPlatformComesFromTheFieldOrTheText() {
        XCTAssertEqual(MotisParser.track(["track": "7"]), "7")
        XCTAssertEqual(MotisParser.track(["scheduledTrack": "7a"]), "7a")
        XCTAssertEqual(MotisParser.track(["description": "S-Bahnsteig Gleis 4"]), "4")
        XCTAssertNil(MotisParser.track(["description": "Bussteig"]))
        XCTAssertNil(MotisParser.track([:]))
    }

    func testLineNamesAndProducts() {
        XCTAssertEqual(MotisParser.line(["routeShortName": "RE1 (73808)"]), "RE1")
        XCTAssertEqual(MotisParser.line(["routeShortName": "S7"]), "S7")
        XCTAssertNil(MotisParser.line(["routeShortName": ""]))
        XCTAssertEqual(MotisParser.product(["routeType": 109]), .suburban)
        XCTAssertEqual(MotisParser.product(["routeType": 106]), .regional)
        XCTAssertEqual(MotisParser.product(["routeType": 101]), .express)
        XCTAssertEqual(MotisParser.product(["routeType": 700]), .bus)
        XCTAssertEqual(MotisParser.product(["routeType": 900]), .tram)
        XCTAssertEqual(MotisParser.product(["routeType": 402]), .subway)
        // No route type: the mode word has to do, and it calls an S-Bahn METRO.
        XCTAssertEqual(MotisParser.product(["mode": "METRO"]), .suburban)
        XCTAssertEqual(MotisParser.product(["mode": "HIGHSPEED_RAIL"]), .express)
    }

    func testPolylineDecodesAtTheStatedPrecision() {
        // The classic example from Google's own documentation, at 1e-5.
        let five = MotisParser.polyline(["points": "_p~iF~ps|U_ulLnnqC_mqNvxq`@", "precision": 5])
        XCTAssertEqual(five.count, 3)
        XCTAssertEqual(five[0].latitude, 38.5, accuracy: 0.0001)
        XCTAssertEqual(five[0].longitude, -120.2, accuracy: 0.0001)
        XCTAssertEqual(five[2].latitude, 43.252, accuracy: 0.0001)
        // Same string at 1e-7 is a hundredth of the movement.
        let seven = MotisParser.polyline(["points": "_p~iF~ps|U_ulLnnqC_mqNvxq`@", "precision": 7])
        XCTAssertEqual(seven[0].latitude, 0.385, accuracy: 0.0001)
        XCTAssertTrue(MotisParser.polyline(nil).isEmpty)
    }

    func testTheUserAgentCarriesNameVersionAndContact() {
        let ua = MotisClient.userAgent
        XCTAssertTrue(ua.hasPrefix("RadPendler/"), ua)
        XCTAssertTrue(ua.contains("github.com/DeepSkyPlan/RadPendler"), "a way of contact, as the terms ask")
    }
}

private extension LegKind {
    var short: String {
        switch self {
        case .walk: "walk"
        case .bike: "bike"
        case .car: "car"
        case .transit: "transit"
        }
    }
}

extension MotisTests {
    func testAutomaticPicksTheSourceByWhereTheTripIs() {
        let berlin = CLLocationCoordinate2D(latitude: 52.52, longitude: 13.41)
        let potsdam = CLLocationCoordinate2D(latitude: 52.39, longitude: 13.07)
        let hamburg = CLLocationCoordinate2D(latitude: 53.55, longitude: 10.00)
        XCTAssertEqual(TimetableSource.automatic.resolved(from: berlin, to: potsdam), .vbb,
                       "inside the VBB area the VBB knows more")
        XCTAssertEqual(TimetableSource.automatic.resolved(from: berlin, to: hamburg), .transitous,
                       "one end outside is enough")
        XCTAssertEqual(TimetableSource.vbb.resolved(from: berlin, to: hamburg), .vbb,
                       "a fixed choice is not overruled")
        XCTAssertEqual(TimetableSource.transitous.resolved(from: berlin, to: potsdam), .transitous)
    }

    func testTheSourceSurvivesALaunch() {
        let suite = UUID().uuidString
        let s = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(s.timetableSource, .automatic)
        s.timetableSource = .transitous
        XCTAssertEqual(AppSettings(defaults: UserDefaults(suiteName: suite)!).timetableSource, .transitous)
    }
}

/// Talks to the real Transitous instance. Off unless `MOTIS_LIVE=1` is set, so
/// the usual test run stays offline and their server stays unbothered:
///
///     MOTIS_LIVE=1 ./dev test
extension MotisTests {
    func testLiveJourneyFromTransitous() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MOTIS_LIVE"] == "1",
                          "set MOTIS_LIVE=1 to call the real API")
        let berlin = CLLocationCoordinate2D(latitude: 52.5210, longitude: 13.4130)
        let hamburg = CLLocationCoordinate2D(latitude: 53.5527, longitude: 10.0065)
        let journeys = try await MotisClient().journeys(from: berlin, to: hamburg,
                                                        at: .now.addingTimeInterval(3600),
                                                        arriveBy: false, access: .bike, results: 3)
        XCTAssertFalse(journeys.isEmpty, "nationwide is the whole point")
        let legs = try XCTUnwrap(journeys.first)
        XCTAssertTrue(legs.contains(where: \.isTransit))
        XCTAssertTrue(legs.allSatisfy { $0.arrival >= $0.departure })
        XCTAssertTrue(legs.contains { $0.coordinates.count > 10 }, "geometry decoded")
        print("LIVE:", legs.map { "\($0.kind) \($0.lineName ?? "") \(Fmt.time($0.departure))" })
    }
}

extension MotisTests {
    func testAFixBecomesAnAddressWithItsPostalCode() {
        let c = CLLocationCoordinate2D(latitude: 52.5210, longitude: 13.4130)
        let full = MKPlacemark(coordinate: c, addressDictionary: [
            "Thoroughfare": "Musterstraße", "SubThoroughfare": "1",
            "ZIP": "10178", "City": "Berlin",
        ])
        let place = LocationService.place(from: full, at: c)
        XCTAssertEqual(place.shortName, "Musterstraße 1")
        XCTAssertEqual(place.areaLine, "10178 Berlin")
        XCTAssertEqual(place.postalCode, "10178")
        XCTAssertEqual(place.latitude, 52.5210, accuracy: 0.0001)

        // A field somewhere without a street still has to become something.
        let bare = MKPlacemark(coordinate: c, addressDictionary: ["City": "Beispielstadt"])
        XCTAssertEqual(LocationService.place(from: bare, at: c).shortName, "Beispielstadt")
    }
}
