import CoreLocation
import MapKit

struct StreetRoute {
    var distance: Double
    /// Apple's own estimate. Used for the car; bike times come from the
    /// configured speed instead.
    var expectedTravelTime: TimeInterval
    var coordinates: [CLLocationCoordinate2D]
    /// Signalised junctions on the route, once known from OpenStreetMap.
    var signals = 0
    /// Von diesen Kreuzungen die, an denen dieser Fahrer schon gemessen hat.
    /// Sie sind in `signals` mitgezählt und kosten ihre gemessene Zeit statt
    /// des eingestellten Mittelwerts.
    var learnedSignals: [LearnedSignal] = []
    /// Metres per road class, where the router said — BRouter does, Apple
    /// does not. Empty means nobody told us, not that the route is all main road.
    var mix = RoadMix()
    /// The same knowledge with positions, so a recorded ride can be attributed
    /// to it afterwards.
    var roadPoints: [RoadPoint] = []
    /// Summierter Anstieg in Metern — alles Bergauf der Strecke zusammen, das
    /// Bergab zählt nicht dagegen. nil heißt **unbekannt**, nicht flach:
    /// BRouter kennt die Höhen, Apple Karten liefert keine.
    var ascent: Double? = nil
}

enum StreetMode: Hashable {
    case bike, car, walk

    var transportType: MKDirectionsTransportType {
        switch self {
        case .bike: .cycling
        case .car: .automobile
        case .walk: .walking
        }
    }
}

protocol StreetRouting: Sendable {
    func route(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
               mode: StreetMode, departure: Date?) async throws -> StreetRoute
}

/// Apple Maps directions. Bike and walk routes are cached for the life of the
/// app: the station legs from the two default addresses repeat on every refresh,
/// and MKDirections throttles clients that ask too often (~50 requests/min).
actor MapKitRouter: StreetRouting {
    private var cache: [String: StreetRoute] = [:]

    func route(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
               mode: StreetMode, departure: Date?) async throws -> StreetRoute {
        let key = String(format: "%d|%.5f,%.5f|%.5f,%.5f", mode.hashValue,
                         from.latitude, from.longitude, to.latitude, to.longitude)
        if mode != .car, let hit = cache[key] { return hit }

        let response = try await ask(from: from, to: to, mode: mode, departure: departure, alternatives: false)
        guard let route = response.first else { throw MKError(.directionsNotFound) }
        if mode != .car { cache[key] = route }
        return route
    }

    /// Every line Apple offers, alternates included. Not cached: the car is the
    /// only caller and its times follow the traffic.
    func routes(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
                mode: StreetMode, departure: Date?) async throws -> [StreetRoute] {
        let found = try await ask(from: from, to: to, mode: mode, departure: departure, alternatives: true)
        guard !found.isEmpty else { throw MKError(.directionsNotFound) }
        return found
    }

    private func ask(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, mode: StreetMode,
                     departure: Date?, alternatives: Bool) async throws -> [StreetRoute] {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = mode.transportType
        request.requestsAlternateRoutes = alternatives
        if mode == .car, let departure { request.departureDate = departure }
        let response = try await MKDirections(request: request).calculate()
        return response.routes.map { r in
            var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid,
                                                  count: r.polyline.pointCount)
            r.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: r.polyline.pointCount))
            return StreetRoute(distance: r.distance, expectedTravelTime: r.expectedTravelTime,
                               coordinates: coords)
        }
    }
}
