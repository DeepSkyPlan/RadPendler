import CoreLocation
import MapKit

struct StreetRoute {
    var distance: Double
    /// Apple's own estimate. Used for the car; bike times come from the
    /// configured speed instead.
    var expectedTravelTime: TimeInterval
    var coordinates: [CLLocationCoordinate2D]
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

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = mode.transportType
        if mode == .car, let departure { request.departureDate = departure }
        let response = try await MKDirections(request: request).calculate()
        guard let r = response.routes.first else { throw MKError(.directionsNotFound) }

        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid,
                                              count: r.polyline.pointCount)
        r.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: r.polyline.pointCount))
        let route = StreetRoute(distance: r.distance, expectedTravelTime: r.expectedTravelTime,
                                coordinates: coords)
        if mode != .car { cache[key] = route }
        return route
    }
}
