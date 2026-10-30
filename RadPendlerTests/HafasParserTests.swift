import CoreLocation
import XCTest
@testable import RadPendler

final class HafasParserTests: XCTestCase {
    private func fixture(_ name: String) throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try HafasParser.answer(Data(contentsOf: url))
    }

    private func berlin(_ day: String, _ time: String) -> Date {
        HafasTime.date(day: day, time: time)!
    }

    func testBikeJourneysAreAllRailWithBikeCarriage() throws {
        let journeys = HafasParser.journeys(try fixture("vbb_trip_bike_stations"))
        XCTAssertEqual(journeys.count, 5)
        for legs in journeys {
            let transit = legs.filter(\.isTransit)
            XCTAssertFalse(transit.isEmpty)
            XCTAssertTrue(transit.allSatisfy { $0.bikeCarriage == .yes }, "every train must carry bikes")
            XCTAssertTrue(transit.allSatisfy { $0.coordinates.count > 2 }, "polyline decoded")
        }
        let first = journeys[0].filter(\.isTransit)
        XCTAssertEqual(first.first?.fromName, "S+U Alexanderplatz Bhf (Berlin)")
        XCTAssertEqual(first.last?.toName, "S Potsdam Hauptbahnhof")
        XCTAssertGreaterThanOrEqual(first.first!.departure, berlin("2026-10-13", "08:15:00"))
    }

    func testAddressJourneyKeepsWalksAndMarksBusWithoutBikeCarriage() throws {
        let journeys = HafasParser.journeys(try fixture("vbb_trip_address_bus"))
        XCTAssertGreaterThanOrEqual(journeys.count, 3)
        let legs = journeys[0]
        XCTAssertEqual(legs.first?.kind, .walk)
        XCTAssertEqual(legs.last?.kind, .walk)
        XCTAssertNotNil(legs.first?.distance)
        let buses = journeys.flatMap { $0 }.filter {
            if case .transit(_, .bus) = $0.kind { true } else { false }
        }
        XCTAssertFalse(buses.isEmpty, "the last mile of this one is a bus, and buses take no bikes")
        XCTAssertTrue(buses.allSatisfy { $0.bikeCarriage == .unknown },
                      "no FK remark is not a no — it is an open question for the user")
        // Legs are chronological.
        for legs in journeys {
            for (a, b) in zip(legs, legs.dropFirst()) {
                XCTAssertLessThanOrEqual(a.departure, b.departure)
            }
        }
    }

    func testNearbyStationsAreRailOnlyDedupedAndSorted() throws {
        let stations = HafasParser.stations(try fixture("vbb_nearby_stations"), productMask: TransitProduct.bikeStationMask)
        XCTAssertFalse(stations.isEmpty)
        XCTAssertEqual(stations.map(\.distance), stations.map(\.distance).sorted())
        XCTAssertEqual(Set(stations.map { HafasParser.baseName($0.name) }).count, stations.count)
        XCTAssertTrue(stations.allSatisfy { $0.productMask & TransitProduct.bikeStationMask != 0 })
        XCTAssertTrue(stations.contains { $0.name.contains("Alexanderplatz") })
    }

    func testTramStopsComeFromTheirOwnMask() throws {
        let stops = HafasParser.stations(try fixture("vbb_nearby_stations"), productMask: TransitProduct.tram.rawValue)
        XCTAssertFalse(stops.isEmpty)
        XCTAssertTrue(stops.allSatisfy { $0.productMask & TransitProduct.tram.rawValue != 0 })
        XCTAssertEqual(stops.map(\.distance), stops.map(\.distance).sorted())
    }

    func testAStopPastMidnightCarriesItsOwnDate() {
        let late = HafasTime.date(day: "2026-09-21", time: "23:50:00")!
        let next = HafasTime.date(day: "2026-09-22", time: "00:25:00")!
        XCTAssertEqual(next.timeIntervalSince(late), 35 * 60)
        XCTAssertNil(HafasTime.date(day: "20260921", time: "235000"), "die Schreibweise der alten Schnittstelle")
    }

    func testRealTimeAndPlatformsComeFromTheStops() throws {
        let legs = try XCTUnwrap(HafasParser.journeys(try fixture("vbb_trip_bike_stations")).first)
        let train = try XCTUnwrap(legs.first(where: \.isTransit))
        XCTAssertEqual(train.lineName, "S7")
        XCTAssertEqual(train.kind, .transit(line: "S7", product: .suburban))
        XCTAssertEqual(train.plannedDeparture, berlin("2026-10-13", "08:20:00"))
        XCTAssertNotNil(train.departurePlatform)
        XCTAssertEqual(train.direction, "S Potsdam Hauptbahnhof")
        XCTAssertFalse(train.cancelled)
        // Die Linie beginnt am Bahnhof, nicht irgendwo: richtig entschlüsselt.
        let start = try XCTUnwrap(train.coordinates.first)
        XCTAssertEqual(start.latitude, 52.5215, accuracy: 0.001)
        XCTAssertEqual(start.longitude, 13.4113, accuracy: 0.001)
    }

    func testErrorsAreReadFromTheAnswer() throws {
        func answer(_ code: String) -> Data {
            Data(#"{"errorCode":"\#(code)","errorText":"x","internalErrorTextOut":"Es wurde keine Verbindung gefunden"}"#.utf8)
        }
        XCTAssertThrowsError(try HafasParser.answer(answer("API_AUTH"))) {
            guard case HafasClient.HafasError.denied = $0 else { return XCTFail("\($0)") }
        }
        XCTAssertThrowsError(try HafasParser.answer(answer("SVC_NO_RESULT"))) {
            guard case HafasClient.HafasError.server(let code, let text) = $0 else { return XCTFail("\($0)") }
            XCTAssertTrue(HafasParser.emptyCodes.contains(code))
            XCTAssertEqual(text, "Es wurde keine Verbindung gefunden")
        }
    }

    /// Der Schlüssel reist im Kopf der Anfrage, nie in der Adresse — und ohne
    /// Schlüssel geht gar nichts hinaus.
    func testAccessIdTravelsInTheHeaderNotTheURL() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordingProtocol.self]
        var client = HafasClient()
        client.session = URLSession(configuration: config)
        client.endpoint = HafasClient.cloudEndpoint
        client.accessID = "geheim-123"
        RecordingProtocol.seen = nil
        let there = HafasClient.Location.address(name: "Ziel", coordinate: .init(latitude: 52.4213, longitude: 13.1794))
        _ = try? await client.journeys(from: .station(lid: "900100003"), to: there,
                                       departing: Date(timeIntervalSince1970: 1_790_003_700),
                                       arriveBy: true, bikeCarriage: true, productMask: 65, results: 2)
        let request = try XCTUnwrap(RecordingProtocol.seen)
        let url = try XCTUnwrap(request.url?.absoluteString)
        XCTAssertTrue(url.hasPrefix("https://vbb.hafas.cloud/api/fahrinfo/latest/trip?"), url)
        XCTAssertFalse(url.contains("CoordName"), "mit Namen findet das neue System nichts")
        XCTAssertFalse(url.contains("geheim-123"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer geheim-123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), AppIdentity.userAgent)
        for part in ["originId=900100003", "destCoordLat=52.421300", "date=2026-09-21", "time=17:15",
                     "searchForArrival=1", "bikeCarriage=1", "products=65", "numF=2", "polyEnc=GPA"] {
            XCTAssertTrue(url.contains(part), "\(part) fehlt in \(url)")
        }

        client.accessID = nil
        RecordingProtocol.seen = nil
        do {
            _ = try await client.journeys(from: there, to: there, departing: .now, bikeCarriage: false)
            XCTFail("ohne Schlüssel darf nichts gelingen")
        } catch HafasClient.HafasError.denied {
            XCTAssertNil(RecordingProtocol.seen, "ohne Schlüssel keine Anfrage")
        }
    }

    /// Der VBB stellt am 30.11.2026 um; eine Fassung von heute wechselt dann
    /// von selbst, um Mitternacht Berliner Zeit.
    func testEndpointMovesToTheCloudOnTheThirtiethOfNovember() {
        XCTAssertEqual(HafasClient.endpoint(on: berlin("2026-11-29", "23:59:00")), HafasClient.legacyEndpoint)
        XCTAssertEqual(HafasClient.endpoint(on: berlin("2026-11-30", "00:00:00")), HafasClient.cloudEndpoint)
        XCTAssertEqual(HafasClient.endpoint(on: berlin("2027-03-01", "08:00:00")), HafasClient.cloudEndpoint)
    }

    /// Mastscharf: sechs Masten heißen „S+U Alexanderplatz Bhf", gefragt und
    /// verglichen wird aber der Haltestellenbereich 900100003.
    func testMastsCollapseIntoTheirStopArea() throws {
        let stations = HafasParser.stations(try fixture("vbb_nearby_masts"), productMask: TransitProduct.bikeStationMask)
        let alex = try XCTUnwrap(stations.first { $0.name == "S+U Alexanderplatz Bhf (Berlin)" })
        XCTAssertEqual(alex.lid, "900100003")
        XCTAssertEqual(alex.coordinate.latitude, 52.521508, accuracy: 1e-6, "Mittelpunkt des Bereichs, nicht ein Mast")
        XCTAssertEqual(Set(stations.map(\.lid)).count, stations.count)
        XCTAssertTrue(stations.allSatisfy { $0.lid.hasPrefix("9") }, "\(stations.map(\.lid))")
        XCTAssertEqual(stations.map(\.distance), stations.map(\.distance).sorted())
    }

    /// Das neue System schickt Umstiege als echten Fußweg durch den Bahnhof und
    /// nennt Adressen nach ihren Koordinaten.
    func testMastJourneyKeepsTheWalkInsideTheStationAndTheAddressNames() throws {
        let journeys = HafasParser.journeys(try fixture("vbb_trip_masts"))
            .map { HafasParser.named($0, from: "Start", to: "Ziel") }
        XCTAssertEqual(journeys.count, 2)
        XCTAssertTrue(journeys.allSatisfy { $0.first?.fromName == "Start" && $0.last?.toName == "Ziel" })
        let change = try XCTUnwrap(journeys[1].first {
            $0.kind == .walk && $0.fromName == "S Charlottenburg Bhf (Berlin)" && $0.toName == $0.fromName
        })
        XCTAssertEqual(change.distance, 238)
        XCTAssertEqual(change.arrival.timeIntervalSince(change.departure), 180, accuracy: 60)
        XCTAssertEqual(journeys[1].filter(\.isTransit).count, 2)
    }

    func testFormatIsBerlinLocalTime() {
        // 2026-09-21 15:15 UTC = 17:15 CEST
        let d = Date(timeIntervalSince1970: 1_790_003_700)   // 2026-09-21 15:15 UTC
        let (day, time) = HafasTime.format(d)
        XCTAssertEqual(day, "2026-09-21")
        XCTAssertEqual(time, "17:15")
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
        XCTAssertTrue(HafasParser.bikeCarriage([["key": "FK", "txtN": "Fahrradmitnahme möglich (S Ostbahnhof)"]]))
        XCTAssertFalse(HafasParser.bikeCarriage([["key": "OPERATOR", "txtN": "BVG"]]))
        XCTAssertFalse(HafasParser.bikeCarriage([["key": "FK", "txtN": "Fahrradmitnahme möglich"],
                                                 ["key": "XX", "txtN": "Keine Fahrradmitnahme 6–9 Uhr"]]))
    }
}

/// Merkt sich die Anfrage und antwortet mit „kein Netz".
final class RecordingProtocol: URLProtocol {
    nonisolated(unsafe) static var seen: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.seen = request
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

/// Fragt die echte VBB-API, mit der Access-ID aus dem Paket. Aus, solange
/// `VBB_LIVE=1` nicht gesetzt ist — der übliche Lauf bleibt ohne Netz:
///
///     TEST_RUNNER_VBB_LIVE=1 ./dev test
extension HafasParserTests {
    func testLiveStationsAndBikeJourneysFromTheVBB() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["VBB_LIVE"] == "1",
                          "set TEST_RUNNER_VBB_LIVE=1 to call the real API")
        try XCTSkipUnless(HafasClient().isConfigured, "keine VBB_ACCESS_ID in Secrets.xcconfig")
        for endpoint in [HafasClient.legacyEndpoint, HafasClient.cloudEndpoint] {
            var client = HafasClient()
            client.endpoint = endpoint
            await StationCache.shared.clear()
            try await liveStationsAndBikeJourneys(client)
        }
    }

    private func liveStationsAndBikeJourneys(_ client: HafasClient) async throws {
        let alex = CLLocationCoordinate2D(latitude: 52.5210, longitude: 13.4130)
        let wannsee = CLLocationCoordinate2D(latitude: 52.4213, longitude: 13.1794)
        let from = try await client.nearbyStations(around: alex, radius: 5000)
        let to = try await client.nearbyStations(around: wannsee, radius: 5000)
        let a = try XCTUnwrap(from.first(where: \.hasBikeCompartment))
        let b = try XCTUnwrap(to.first(where: \.hasBikeCompartment))
        let soon = Date.now.addingTimeInterval(600)
        let byBike = try await client.journeys(from: .station(lid: a.lid), to: .station(lid: b.lid), departing: soon,
                                               bikeCarriage: true, productMask: TransitProduct.bikeCompartmentMask,
                                               results: 2)
        XCTAssertFalse(byBike.isEmpty)
        XCTAssertTrue(byBike.flatMap { $0 }.filter(\.isTransit).allSatisfy { $0.bikeCarriage == .yes })
        let doorToDoor = try await client.journeys(from: .address(name: "Start", coordinate: alex),
                                                   to: .address(name: "Ziel", coordinate: wannsee),
                                                   departing: soon, arriveBy: true, bikeCarriage: false)
        XCTAssertFalse(doorToDoor.isEmpty)
        XCTAssertTrue(doorToDoor.allSatisfy { ($0.last?.arrival ?? .distantFuture) <= soon.addingTimeInterval(60) })
        let same = try await client.journeys(from: .station(lid: a.lid), to: .station(lid: a.lid), departing: soon,
                                             bikeCarriage: false)
        XCTAssertTrue(same.isEmpty, "Start gleich Ziel ist keine Fehlermeldung")
    }

    /// Dieselbe Strecke durch den ganzen Planer: Bahn allein und Rad + Bahn.
    func testLivePlanThroughTheVBB() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["VBB_LIVE"] == "1",
                          "set TEST_RUNNER_VBB_LIVE=1 to call the real API")
        try XCTSkipUnless(TripPlanner().hafas.isConfigured, "keine VBB_ACCESS_ID in Secrets.xcconfig")
        for endpoint in [HafasClient.legacyEndpoint, HafasClient.cloudEndpoint] {
            var planner = TripPlanner()
            planner.hafas.endpoint = endpoint
            await StationCache.shared.clear()
            try await livePlan(planner, endpoint.host() ?? "?")
        }
    }

    private func livePlan(_ planner: TripPlanner, _ host: String) async throws {
        let req = PlanRequest(origin: Place(name: "Start", latitude: 52.5210, longitude: 13.4130),
                              destination: Place(name: "Ziel", latitude: 52.4213, longitude: 13.1794),
                              target: .departAfter(.now), settings: PlanSettings())
        XCTAssertEqual(planner.source(req), .vbb)
        let transit = try await planner.transitOptions(req)
        XCTAssertFalse(transit.isEmpty)
        let started = Date.now
        let bikeRail = try await planner.bikeTransitOptions(req)
        print("LIVE \(host): Rad + Bahn", bikeRail.count, "Vorschläge in",
              String(format: "%.1f s", Date.now.timeIntervalSince(started)),
              bikeRail.map { $0.legs.compactMap(\.lineName).joined(separator: "+") })
        XCTAssertFalse(bikeRail.isEmpty)
        XCTAssertTrue(bikeRail.allSatisfy { $0.legs.contains { $0.kind == .bike } && $0.legs.contains(where: \.isTransit) })
    }
}
