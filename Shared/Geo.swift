import CoreLocation
import Foundation

/// What comes back from a foreign service is not a coordinate until someone has
/// looked at it. Every parse boundary in the app goes through here, because an
/// invalid, infinite or absurd value does not stay harmless: it reaches
/// `MKPolyline`, the flat projection in `RoadData` and `SegmentGrid`, where a
/// NaN turns into a trap and two far-apart points into eight hundred million
/// grid cells.
enum Geo {
    /// More points than any real route has. A longer answer is a bug or an
    /// attack, never a way from A to B.
    static let maxPoints = 100_000

    /// Guards against the whole family at once: out-of-range, infinite, NaN.
    static func valid(_ c: CLLocationCoordinate2D) -> Bool {
        c.latitude.isFinite && c.longitude.isFinite && CLLocationCoordinate2DIsValid(c)
    }

    /// Everything a parser hands on: bounded in length, every point real.
    static func validated(_ coords: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        coords.count <= maxPoints ? coords.filter(valid) : Array(coords.prefix(maxPoints)).filter(valid)
    }

    /// A decoded polyline delta must fit in the five-times-five bits the format
    /// allows; without the limit the accumulator can be driven past `Int`.
    static let maxPolylineShift = 32
}


/// Text that came from a foreign service and is about to be shown to the user.
/// It may be long, it may contain control characters, and it is not the app's
/// own voice — so it gets cut to one line and stripped before it appears.
func foreignText(_ s: String, limit: Int = 120) -> String {
    let clean = s.unicodeScalars
        .filter { !CharacterSet.controlCharacters.contains($0) }
        .reduce(into: "") { $0.unicodeScalars.append($1) }
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return clean.count <= limit ? clean : String(clean.prefix(limit)) + "…"
}
