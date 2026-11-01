import CoreLocation
import XCTest
@testable import RadPendler

/// Leihroller und -räder zur Haltestelle — über Transitous, als Alternative zu Bus & Bahn.
final class RentalTests: XCTestCase {
    /// Eine Verbindung, wie Transitous sie schickt: zu Fuß zum Roller, Roller
    /// zur S-Bahn, S-Bahn. Gekürzt auf das, was gelesen wird.
    private let answer = """
    {"itineraries":[{"legs":[
     {"mode":"WALK","from":{"name":"START","lat":52.5210,"lon":13.4130},"to":{"name":"Dott berlin","lat":52.5200,"lon":13.4140},
      "startTime":"2026-11-01T20:26:00Z","endTime":"2026-11-01T20:30:00Z","distance":238},
     {"mode":"RENTAL","from":{"name":"Dott berlin","lat":52.5200,"lon":13.4140},"to":{"name":"","lat":52.5150,"lon":13.4000},
      "startTime":"2026-11-01T20:30:00Z","endTime":"2026-11-01T20:36:00Z","distance":1315,
      "rental":{"systemName":"Dott berlin","formFactor":"SCOOTER_STANDING",
                "rentalUriIOS":"https://go.ridedott.com/vehicles/abc?platform=ios"}},
     {"mode":"METRO","routeShortName":"S7","routeType":109,"from":{"name":"S Hackescher Markt","lat":52.5150,"lon":13.4000},
      "to":{"name":"S Wannsee","lat":52.4213,"lon":13.1794},
      "startTime":"2026-11-01T20:40:00Z","endTime":"2026-11-01T21:20:00Z"}
    ]}]}
    """

    private func legs() throws -> [Leg] {
        try XCTUnwrap(MotisParser.journeys(Data(answer.utf8)).first)
    }

    func testTheScooterIsALegOfItsOwnWithProviderAndAppLink() throws {
        let legs = try legs()
        XCTAssertEqual(legs.map(\.kind.short), ["walk", "rental", "transit"])
        let ride = legs[1]
        XCTAssertEqual(ride.kind, .rental(.scooter))
        XCTAssertEqual(ride.rental?.system, "Dott berlin")
        XCTAssertEqual(ride.rental?.appURL?.host, "go.ridedott.com")
        XCTAssertEqual(ride.fromName, "", "der Anbieter ist kein Ort")
        XCTAssertFalse(ride.isTransit, "ein Roller ist kein Zug")
    }

    func testAVehicleTheAppDoesNotKnowDropsTheWholeConnection() throws {
        let car = answer.replacingOccurrences(of: "SCOOTER_STANDING", with: "CAR")
        XCTAssertTrue(try MotisParser.journeys(Data(car.utf8)).isEmpty)
    }

    func testWithAScooterItIsTheAlternativeAndADifferentOption() throws {
        let rented = TripOption(mode: .transit, legs: try legs(), prep: 0)
        var walkingLegs = try legs()
        walkingLegs.remove(at: 1)
        let walking = TripOption(mode: .transit, legs: walkingLegs, prep: 0)
        XCTAssertTrue(rented.usesRental)
        XCTAssertTrue(rented.isAlternative)
        XCTAssertFalse(walking.isAlternative)
        XCTAssertNotEqual(rented.id, walking.id, "dieselbe S-Bahn, aber eine andere Möglichkeit")
        XCTAssertEqual(TripRules.ordered([rented, walking]).map(\.id), [walking.id, rented.id])
    }

    func testTheScooterIsNeverTheRecommendationWhileWalkingWorks() throws {
        // Der Roller kommt früher an — empfohlen wird trotzdem der Weg zu Fuß.
        let rented = TripOption(mode: .transit, legs: try legs(), prep: 0)
        var walkingLegs = try legs()
        walkingLegs.remove(at: 1)
        walkingLegs[1].arrival = walkingLegs[1].arrival.addingTimeInterval(600)
        let walking = TripOption(mode: .transit, legs: walkingLegs, prep: 0)
        let pick = TripPlanner.recommend([rented, walking], order: [.transit])
        XCTAssertEqual(pick?.optionID, walking.id)
    }

    func testTheRequestAsksForScootersAndBikesAtBothEnds() async throws {
        let spy = URLSessionConfiguration.ephemeral
        spy.protocolClasses = [CaptureProtocol.self]
        var client = MotisClient()
        client.session = URLSession(configuration: spy)
        _ = try? await client.journeys(from: .init(latitude: 52.5210, longitude: 13.4130),
                                       to: .init(latitude: 52.4213, longitude: 13.1794),
                                       at: .now, arriveBy: false, access: .rental)
        let query = try XCTUnwrap(CaptureProtocol.last?.url?.query)
        XCTAssertTrue(query.contains("preTransitModes=RENTAL"))
        XCTAssertTrue(query.contains("postTransitRentalFormFactors=SCOOTER_STANDING,BICYCLE"))
    }

    /// Echt gegen Transitous: `MOTIS_LIVE=1`.
    func testLiveRentalConnectionsParse() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MOTIS_LIVE"] == "1", "set MOTIS_LIVE=1")
        let journeys = try await MotisClient().journeys(
            from: .init(latitude: 52.4213, longitude: 13.1794), to: .init(latitude: 52.5210, longitude: 13.4130),
            at: .now.addingTimeInterval(600), arriveBy: false, access: .rental)
        XCTAssertFalse(journeys.isEmpty)
        print("LIVE Leih:", journeys.map { $0.map { $0.rental?.system ?? $0.lineName ?? "\($0.kind)" } })
    }
}

/// Merkt sich die letzte Anfrage und antwortet mit nichts.
final class CaptureProtocol: URLProtocol {
    nonisolated(unsafe) static var last: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.last = request
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
