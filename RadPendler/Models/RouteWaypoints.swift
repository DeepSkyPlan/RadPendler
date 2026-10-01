import CoreLocation
import Foundation

/// Die Fixpunkte einer Strecke. Eine Strecke sind zwei Enden, in beiden
/// Richtungen dieselbe — wer abends über den Korso heimfährt, will morgens
/// auch über ihn hin. Ein Ende gilt als dasselbe, solange es höchstens
/// `radius` entfernt liegt: „hier" aus der Ortung liegt nie genau auf der
/// Hausnummer.
struct RouteWaypoints: Codable, Equatable {
    var a: TrackPoint
    var b: TrackPoint
    var points: [Place]

    static let radius = 500.0

    func matches(_ from: CLLocationCoordinate2D, _ to: CLLocationCoordinate2D) -> Bool {
        let (x, y) = (a.coordinate, b.coordinate)
        return (x.distance(to: from) <= Self.radius && y.distance(to: to) <= Self.radius)
            || (y.distance(to: from) <= Self.radius && x.distance(to: to) <= Self.radius)
    }

    static func find(_ all: [RouteWaypoints], _ from: CLLocationCoordinate2D,
                     _ to: CLLocationCoordinate2D) -> RouteWaypoints? {
        all.first { $0.matches(from, to) }
    }

    static func setting(_ points: [Place], in all: [RouteWaypoints], _ from: CLLocationCoordinate2D,
                        _ to: CLLocationCoordinate2D) -> [RouteWaypoints] {
        var out = all.filter { !$0.matches(from, to) }
        if !points.isEmpty { out.append(RouteWaypoints(a: TrackPoint(from), b: TrackPoint(to), points: points)) }
        return out
    }
}
