import CoreLocation
import Foundation
@testable import RadPendler

// Was nur Tests brauchen, um ohne Netz zu planen. Lag bis 1.9.1 im
// App-Ziel und fuhr dort in jedem Build mit.

extension TripPlanner {
    /// A planner that cannot reach anything: every client gets a session that
    /// refuses at once, so a test using it fails fast instead of calling
    /// five live services. Used by the tests that only care about the state a
    /// search leaves behind, not about its result.
    static var offline: TripPlanner {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1
        config.protocolClasses = [BlockedProtocol.self]
        let session = URLSession(configuration: config)
        var planner = TripPlanner()
        planner.hafas.session = session
        planner.motis.session = session
        planner.brouter.session = session
        planner.brouter.cached = false
        planner.rain.session = session
        // Die beiden, die bis 1.4 trotzdem ins Netz liefen: Overpass hing an
        // einem fest verdrahteten `URLSession.shared`, und Apple Karten ist
        // MapKit — das lässt sich nicht umlenken, also antwortet hier gar
        // niemand. „Offline" hieß vorher „fast offline", und das ist bei einem
        // Test die unangenehmste Sorte von fast.
        planner.roads = RoadDataStore(session: session)
        planner.apple = DeadRouter()
        planner.streets = DeadRouter()
        // Und keine eigenen Fahrten: die des Simulators gehören nicht in einen Test.
        planner.habits = RiddenPaths(file: URL.temporaryDirectory.appending(path: "ridden-\(UUID()).json"))
        return planner
    }
}

/// Refuses every request. Lets a test run a real planner without a network:
/// jede Anfrage endet sofort mit „kein Netz", ohne DNS.
final class BlockedProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

/// Ein Router, der nichts findet — für den Planer, der offline sein soll.
/// MapKit lässt sich nicht umlenken; also fragt ihn dort niemand.
struct DeadRouter: StreetRouting {
    struct Offline: Error {}

    func route(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
               mode: StreetMode, departure: Date?) async throws -> StreetRoute {
        throw Offline()
    }
}
