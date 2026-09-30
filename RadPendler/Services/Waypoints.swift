import CoreLocation
import Foundation
import simd

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

/// Welche Fixpunkte eine Radlinie **anfahren** soll, und in welcher Reihenfolge.
///
/// Bis 1.8 sortierten Fixpunkte nur aus: eine Linie, die nicht vorbeikam, war
/// grau. Nimmt aber kein Profil die Straße, die man fahren will — die
/// Prinzregentenstraße (Fahrt 30.09.2026) —, ist dann eben alles grau. Jetzt
/// fährt BRouter sie an.
///
/// Nur, was am Weg liegt: ein Fixpunkt, der die Luftlinie um mehr als
/// `maxDetour` verlängern würde, gehört zu einer anderen Frage — die S-Bahn-
/// Station für Rad + Bahn, der Bäcker auf dem Heimweg — und bleibt bei dieser
/// Strecke ein reiner Filter. Die Reihenfolge ist die entlang der Luftlinie:
/// dieselben Fixpunkte gelten so auf dem Hin- wie auf dem Rückweg.
enum WaypointRouting {
    static let maxDetour = 0.25

    static func via(_ waypoints: [Place], from: CLLocationCoordinate2D,
                    to: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        let direct = from.distance(to: to)
        guard direct > 0 else { return [] }
        return ordered(waypoints.map(\.coordinate)
            .filter { from.distance(to: $0) + $0.distance(to: to) <= direct * (1 + maxDetour) },
                       from: from, to: to)
    }

    /// In Fahrtrichtung, entlang der Luftlinie.
    static func ordered(_ points: [CLLocationCoordinate2D], from: CLLocationCoordinate2D,
                        to: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        let flat = Flat(latitude: from.latitude)
        let a = flat.point(from), ab = flat.point(to) - a
        return points.sorted { simd_dot(flat.point($0) - a, ab) < simd_dot(flat.point($1) - a, ab) }
    }

    /// Unterwegs: nur die, die noch vor einem liegen — näher am Ziel als man
    /// selbst und nicht schon im Vorbeifahren erreicht.
    static func ahead(_ via: [CLLocationCoordinate2D], from here: CLLocationCoordinate2D,
                      to destination: CLLocationCoordinate2D, passed radius: Double = 150) -> [CLLocationCoordinate2D] {
        let left = here.distance(to: destination)
        return via.filter { $0.distance(to: destination) < left && $0.distance(to: here) > radius }
    }
}
