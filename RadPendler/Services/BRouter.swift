import CoreLocation
import Foundation

/// Bike routes from the public BRouter server (brouter.de), which routes on
/// OpenStreetMap with selectable profiles. Apple Maps has exactly one bike
/// route and no notion of quiet streets; BRouter gives several distinct
/// candidates per request (`alternativeidx` 0…3).
struct BRouterClient {
    enum Profile: String {
        case trekking, safety, fastbike, shortest
    }

    var session: URLSession = .shared

    func route(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
               profile: Profile, alternative: Int = 0) async throws -> StreetRoute {
        var c = URLComponents(string: "https://brouter.de/brouter")!
        c.queryItems = [
            .init(name: "lonlats", value: String(format: "%.6f,%.6f|%.6f,%.6f",
                                                 from.longitude, from.latitude, to.longitude, to.latitude)),
            .init(name: "profile", value: profile.rawValue),
            .init(name: "alternativeidx", value: String(alternative)),
            .init(name: "format", value: "geojson"),
        ]
        var request = URLRequest(url: c.url!, timeoutInterval: 20)
        request.setValue("RadPendler iOS (private commute planner)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw BRouterError.server(String(data: data.prefix(200), encoding: .utf8) ?? "HTTP \(http.statusCode)")
        }
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> StreetRoute {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let feature = (root["features"] as? [[String: Any]])?.first,
              let geometry = feature["geometry"] as? [String: Any],
              let coords = geometry["coordinates"] as? [[Double]],
              let props = feature["properties"] as? [String: Any] else { throw BRouterError.malformed }
        let points = Geo.validated(coords.filter { $0.count >= 2 }
            .map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) })
        let length = Double(props["track-length"] as? String ?? "") ?? 0
        let time = Double(props["total-time"] as? String ?? "") ?? 0
        guard points.count > 1 else { throw BRouterError.malformed }
        return StreetRoute(distance: length, expectedTravelTime: time, coordinates: points)
    }

    enum BRouterError: LocalizedError {
        case server(String), malformed
        var errorDescription: String? {
            switch self {
            case .server(let s): "BRouter: \(foreignText(s))"
            case .malformed: "BRouter: unerwartete Antwort"
            }
        }
    }
}

/// Bike legs through BRouter's "safety" profile (bike paths and quiet streets
/// first), falling back to Apple Maps; the car always through Apple Maps.
actor CompositeRouter: StreetRouting {
    private let apple = MapKitRouter()
    private let brouter = BRouterClient()
    private var cache: [String: StreetRoute] = [:]

    func route(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
               mode: StreetMode, departure: Date?) async throws -> StreetRoute {
        guard mode == .bike else { return try await apple.route(from: from, to: to, mode: mode, departure: departure) }
        let key = String(format: "%.5f,%.5f|%.5f,%.5f", from.latitude, from.longitude, to.latitude, to.longitude)
        if let hit = cache[key] { return hit }
        let r: StreetRoute
        do {
            r = try await brouter.route(from: from, to: to, profile: .safety)
        } catch {
            r = try await apple.route(from: from, to: to, mode: .bike, departure: nil)
        }
        cache[key] = r
        return r
    }
}
