import CoreLocation
import Foundation

/// Where the next turn is, and how far. Derived from the drawn route itself —
/// no router tells us, and none needs to: a turn is a place where the line
/// changes direction, and the line is already on the screen.
///
/// Deliberately crude. This is not turn-by-turn navigation with street names;
/// it is the one arrow one wants on a handlebar: *next: left, in 120 m*. It
/// never speaks, never reroutes and never claims to know better than the rider.
///
/// Pure, so it can be driven from a test with a made-up polyline — a wrong
/// turn arrow is exactly the kind of thing that looks plausible while being
/// backwards.
enum TurnGuide {
    enum Turn: String, Equatable {
        case sharpLeft, left, slightLeft, straight, slightRight, right, sharpRight, arrive

        var symbol: String {
            switch self {
            case .sharpLeft: "arrow.uturn.left"
            case .left: "arrow.turn.up.left"
            case .slightLeft: "arrow.up.left"
            case .straight: "arrow.up"
            case .slightRight: "arrow.up.right"
            case .right: "arrow.turn.up.right"
            case .sharpRight: "arrow.uturn.right"
            case .arrive: "flag.checkered"
            }
        }

        var title: String {
            switch self {
            case .sharpLeft: L("scharf links")
            case .left: L("links")
            case .slightLeft: L("halb links")
            case .straight: L("geradeaus")
            case .slightRight: L("halb rechts")
            case .right: L("rechts")
            case .sharpRight: L("scharf rechts")
            case .arrive: L("Ziel")
            }
        }

        /// From a signed change of bearing: negative is left, positive right.
        static func from(_ degrees: Double) -> Turn {
            switch degrees {
            case ..<(-110): .sharpLeft
            case ..<(-40): .left
            case ..<(-20): .slightLeft
            case 20...40: .slightRight
            case 40...110: .right
            case 110...: .sharpRight
            default: .straight
            }
        }
    }

    struct Step: Equatable {
        var turn: Turn
        var at: CLLocationCoordinate2D
        /// Metres from the start of the route.
        var distance: Double

        static func == (a: Step, b: Step) -> Bool {
            a.turn == b.turn && a.distance == b.distance
                && a.at.latitude == b.at.latitude && a.at.longitude == b.at.longitude
        }
    }

    /// Less than this is the line wobbling, not the road bending.
    static let minAngle = 22.0
    /// Two bends closer than this are one corner drawn in three points.
    static let minGap = 25.0
    /// How far to look either side of a point when measuring its bearing. A
    /// single pair of points is noise; twenty-five metres is a road.
    static let window = 25.0

    /// Every turn on a route, in riding order, with the last one being arrival.
    static func steps(on route: [CLLocationCoordinate2D]) -> [Step] {
        guard route.count >= 3 else {
            guard let last = route.last else { return [] }
            return [Step(turn: .arrive, at: last, distance: length(route))]
        }
        let cum = cumulative(route)
        var out: [Step] = []
        for i in 1..<(route.count - 1) {
            guard let before = bearing(route, around: i, cum: cum, back: true),
                  let after = bearing(route, around: i, cum: cum, back: false) else { continue }
            let change = signedDifference(from: before, to: after)
            guard abs(change) >= minAngle else { continue }
            // The same corner drawn in three points is one turn, and the
            // sharpest of them is the one worth showing.
            if let last = out.last, cum[i] - last.distance < minGap {
                if abs(change) > abs(angle(of: last.turn)) {
                    out[out.count - 1] = Step(turn: Turn.from(change), at: route[i], distance: cum[i])
                }
                continue
            }
            out.append(Step(turn: Turn.from(change), at: route[i], distance: cum[i]))
        }
        out.append(Step(turn: .arrive, at: route[route.count - 1], distance: cum[cum.count - 1]))
        return out
    }

    /// The next turn ahead of a position, and how far it is.
    ///
    /// The position is matched to the route by the nearest point on it, so a
    /// rider three metres beside the line is still on it. Being far off the
    /// route is not an error either — the guide simply keeps pointing at the
    /// next turn of the route that was planned.
    ///
    /// `cum` and `from` are why this is cheap enough to run on every fix. The
    /// cumulative lengths are computed once when the route is frozen, and the
    /// search starts where the last one ended: a ride does not go backwards,
    /// and scanning ten thousand points once a second is how a map starts to
    /// stutter under one's thumb.
    static func next(after position: CLLocationCoordinate2D, on route: [CLLocationCoordinate2D],
                     steps: [Step], cum: [Double]? = nil,
                     from: Int = 0) -> (step: Step, meters: Double, index: Int)? {
        guard !steps.isEmpty, route.count > 1 else { return nil }
        let lengths = cum ?? cumulative(route)
        guard lengths.count == route.count else { return nil }
        // Look forward from where we were, and only far enough to find the
        // nearest point again — plus a window backwards, in case the last
        // match was a lucky outlier or the rider turned round.
        let lo = Swift.max(0, from - 20)
        var bestIndex = lo
        var bestDistance = Double.infinity
        var i = lo
        while i < route.count {
            let d = route[i].distance(to: position)
            if d < bestDistance { bestDistance = d; bestIndex = i }
            // Once we are clearly moving away again, stop: the route ahead is
            // long, and the nearest point is behind us.
            if d > bestDistance + 500, i > bestIndex + 50 { break }
            i += 1
        }
        let travelled = lengths[bestIndex]
        guard let step = steps.first(where: { $0.distance > travelled + 5 }) ?? steps.last else { return nil }
        return (step, max(0, step.distance - travelled), bestIndex)
    }

    // MARK: Geometry

    static func cumulative(_ route: [CLLocationCoordinate2D]) -> [Double] {
        var out = [0.0]
        for (a, b) in zip(route, route.dropFirst()) { out.append(out[out.count - 1] + a.distance(to: b)) }
        return out
    }

    static func length(_ route: [CLLocationCoordinate2D]) -> Double { cumulative(route).last ?? 0 }

    /// Direction of the road `window` metres before or after a point.
    private static func bearing(_ route: [CLLocationCoordinate2D], around i: Int,
                                cum: [Double], back: Bool) -> Double? {
        let target = back ? cum[i] - window : cum[i] + window
        var j = i
        while back ? (j > 0 && cum[j] > target) : (j < route.count - 1 && cum[j] < target) {
            j += back ? -1 : 1
        }
        guard j != i else { return nil }
        return back ? bearing(from: route[j], to: route[i]) : bearing(from: route[i], to: route[j])
    }

    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    /// −180…180: how far one has to turn to get from one bearing to another.
    static func signedDifference(from a: Double, to b: Double) -> Double {
        ((b - a + 540).truncatingRemainder(dividingBy: 360)) - 180
    }

    /// Rough size of a turn, for picking the sharpest of several close together.
    private static func angle(of turn: Turn) -> Double {
        switch turn {
        case .sharpLeft: -140
        case .left: -75
        case .slightLeft: -30
        case .straight, .arrive: 0
        case .slightRight: 30
        case .right: 75
        case .sharpRight: 140
        }
    }
}
