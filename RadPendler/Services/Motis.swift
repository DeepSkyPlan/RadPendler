import CoreLocation
import Foundation

/// Journeys from Transitous, the community-run MOTIS 2 instance. Unlike the
/// VBB's HAFAS this is not one region's timetable: it routes on the nationwide
/// DELFI dataset and beyond, and it plans **intermodally** — bike to the
/// station, train, bike onwards — in a single request. The app therefore does
/// not have to pick the stations itself, as it does with HAFAS.
///
/// Usage terms (https://transitous.org/api/): the project is open source, it is
/// not commercial, every request carries a `User-Agent` with name, version and
/// a way to reach us, and the app links to https://transitous.org/sources/
/// where the data sources are visible. See `HelpView` and the menu.
struct MotisClient {
    var endpoint = URL(string: "https://api.transitous.org/api/v1/plan")!
    var session: URLSession = .shared

    /// What the access and egress legs may use.
    enum Access: String {
        case walk = "WALK"
        case bike = "BIKE"
    }

    /// One plan request. `access` is how the traveller gets to the first stop
    /// and away from the last one; everything between is up to the router.
    func journeys(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
                  at date: Date, arriveBy: Bool, access: Access, results: Int = 4) async throws -> [[Leg]] {
        var c = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        c.queryItems = [
            .init(name: "fromPlace", value: Self.place(from)),
            .init(name: "toPlace", value: Self.place(to)),
            .init(name: "time", value: ISO8601DateFormatter().string(from: date)),
            .init(name: "arriveBy", value: arriveBy ? "true" : "false"),
            .init(name: "numItineraries", value: String(results)),
            .init(name: "preTransitModes", value: access.rawValue),
            .init(name: "postTransitModes", value: access.rawValue),
            // The app has its own bike and car routing; MOTIS is asked for the
            // timetable, not for a ride it would rate differently.
            .init(name: "directModes", value: "WALK"),
        ]
        var request = URLRequest(url: c.url!, timeoutInterval: 25)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw MotisError.server(http.statusCode, String(data: data.prefix(200), encoding: .utf8) ?? "")
        }
        return try MotisParser.journeys(data)
    }

    /// Name, version and a way of contact, as the usage policy asks for.
    static var userAgent: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        return "RadPendler/\(version) (+https://github.com/DeepSkyPlan/RadPendler)"
    }

    private static func place(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.6f,%.6f", c.latitude, c.longitude)
    }

    enum MotisError: LocalizedError {
        case server(Int, String)
        case malformed
        var errorDescription: String? {
            switch self {
            case .server(let code, let body): "Transitous: HTTP \(code) \(foreignText(body))"
            case .malformed: "Transitous: unerwartete Antwort"
            }
        }
    }
}

/// Turns a MOTIS answer into the app's own legs.
enum MotisParser {
    static func journeys(_ data: Data) throws -> [[Leg]] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let itineraries = root["itineraries"] as? [[String: Any]] else {
            throw MotisClient.MotisError.malformed
        }
        return itineraries.compactMap { legs($0) }.filter { !$0.isEmpty }
    }

    static func legs(_ itinerary: [String: Any]) -> [Leg]? {
        guard let raw = itinerary["legs"] as? [[String: Any]] else { return nil }
        return raw.compactMap(leg)
    }

    static func leg(_ l: [String: Any]) -> Leg? {
        guard let mode = l["mode"] as? String,
              let from = l["from"] as? [String: Any], let to = l["to"] as? [String: Any],
              let start = date(l["startTime"]), let end = date(l["endTime"]) else { return nil }
        let line = Self.line(l)
        let kind: LegKind
        switch mode {
        case "WALK": kind = .walk
        case "BIKE": kind = .bike
        case "CAR": kind = .car
        default: kind = .transit(line: line ?? mode, product: product(l))
        }
        var leg = Leg(kind: kind,
                      fromName: name(from), toName: name(to),
                      departure: start, arrival: end,
                      plannedDeparture: date(l["scheduledStartTime"]),
                      plannedArrival: date(l["scheduledEndTime"]),
                      distance: (l["distance"] as? Double).flatMap { $0 > 0 ? $0 : nil },
                      coordinates: polyline(l["legGeometry"]),
                      departurePlatform: track(from),
                      arrivalPlatform: track(to),
                      direction: l["headsign"] as? String)
        // `bikesAllowed` is GTFS's `bikes_allowed`, and most feeds leave it at
        // its default. A `false` therefore means "nobody said", not "no" — the
        // no comes from the user's own line list.
        leg.bikeCarriage = (l["bikesAllowed"] as? Bool == true) ? .yes : .unknown
        leg.cancelled = l["cancelled"] as? Bool ?? false
        return leg
    }

    /// "RE1 (73808)" is a line plus a train number; only the line is a name.
    static func line(_ l: [String: Any]) -> String? {
        guard let raw = (l["routeShortName"] as? String) ?? (l["displayName"] as? String), !raw.isEmpty else { return nil }
        return raw.components(separatedBy: " (").first?.trimmingCharacters(in: .whitespaces)
    }

    /// GTFS extended route types — the number says more than the mode word,
    /// which calls an S-Bahn "METRO".
    static func product(_ l: [String: Any]) -> TransitProduct {
        switch l["routeType"] as? Int ?? -1 {
        case 100...102, 105: return .express
        case 103, 104, 106...110, 2: return routeTypeIsSuburban(l) ? .suburban : .regional
        case 400...405, 1: return .subway
        case 900...906, 0: return .tram
        case 700...717, 3, 200...209: return .bus
        case 1000...1099, 4: return .ferry
        default: break
        }
        switch l["mode"] as? String ?? "" {
        case "SUBURBAN", "METRO": return .suburban
        case "SUBWAY": return .subway
        case "TRAM": return .tram
        case "BUS", "COACH": return .bus
        case "FERRY": return .ferry
        case "HIGHSPEED_RAIL", "LONG_DISTANCE", "NIGHT_RAIL": return .express
        default: return .regional
        }
    }

    private static func routeTypeIsSuburban(_ l: [String: Any]) -> Bool {
        (l["routeType"] as? Int) == 109 || (l["mode"] as? String) == "METRO"
    }

    /// The platform, either as its own field or out of the plain-text
    /// description some feeds put it in ("S-Bahnsteig Gleis 4").
    static func track(_ place: [String: Any]) -> String? {
        if let t = (place["track"] as? String) ?? (place["scheduledTrack"] as? String), !t.isEmpty { return t }
        guard let text = place["description"] as? String,
              let range = text.range(of: "Gleis ") else { return nil }
        let rest = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : rest
    }

    private static func name(_ place: [String: Any]) -> String {
        let n = place["name"] as? String ?? ""
        // MOTIS calls the two ends of the trip START and END.
        return (n == "START" || n == "END") ? "" : n
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(_ any: Any?) -> Date? {
        guard let s = any as? String else { return nil }
        return iso.date(from: s)
    }

    /// Google's encoded polyline, at the precision the answer names. The
    /// decoder itself lives once, next to the other one that needed it.
    static func polyline(_ any: Any?) -> [CLLocationCoordinate2D] {
        guard let g = any as? [String: Any], let points = g["points"] as? String else { return [] }
        return Polyline.decode(points, precision: pow(10.0, Double(g["precision"] as? Int ?? 5)))
    }

}
