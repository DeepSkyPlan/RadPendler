import CoreLocation
import Foundation

/// Fixed points a route should touch — a station one likes to change at, a
/// bakery on the way. A route passes one when any of its legs runs within
/// `radius` of it, or when a train stops there by name.
enum WaypointMatcher {
    static func passes(_ option: TripOption, waypoints: [Place], requireAll: Bool, radius: Double) -> Bool {
        guard !waypoints.isEmpty else { return true }
        let hits = waypoints.filter { passes(option, waypoint: $0, radius: radius) }
        return requireAll ? hits.count == waypoints.count : !hits.isEmpty
    }

    static func passes(_ option: TripOption, waypoint: Place, radius: Double) -> Bool {
        let name = normalise(waypoint.name)
        for leg in option.legs {
            if leg.isTransit, normalise(leg.fromName).contains(name) || normalise(leg.toName).contains(name) {
                return true
            }
            if leg.coordinates.contains(where: { $0.distance(to: waypoint.coordinate) <= radius }) { return true }
        }
        return false
    }

    /// "S+U Berlin Hauptbahnhof [Gleis 1-8]" and "Berlin Hbf" both reduce to
    /// something the other contains.
    private static func normalise(_ s: String) -> String {
        var t = s.lowercased()
        for token in ["s+u ", "s ", "u ", "bhf", "bahnhof", "berlin", "(", ")", "[", "]", ".", ","] {
            t = t.replacingOccurrences(of: token, with: " ")
        }
        return t.split(separator: " ").joined(separator: " ")
    }
}
