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

    /// Der Punkt `meters` voraus in Richtung `course`. Flach gerechnet: über
    /// ein paar hundert Meter ist die Erdkrümmung nicht das, was zählt.
    ///
    /// Gebraucht, wo ein Router die Fahrtrichtung wissen müsste und nicht
    /// danach fragt — er bekommt sie als Startpunkt.
    static func ahead(_ from: CLLocationCoordinate2D, course: CLLocationDirection,
                      meters: Double) -> CLLocationCoordinate2D {
        guard valid(from), course >= 0, meters.isFinite else { return from }
        let rad = course * .pi / 180
        let mPerDegLat = 111_320.0
        let mPerDegLon = mPerDegLat * cos(from.latitude * .pi / 180)
        guard mPerDegLon > 1 else { return from }
        let next = CLLocationCoordinate2D(latitude: from.latitude + cos(rad) * meters / mPerDegLat,
                                          longitude: from.longitude + sin(rad) * meters / mPerDegLon)
        return valid(next) ? next : from
    }

    /// Eine Linie auf das, was man auf einer Karte unterscheiden kann: jeder
    /// Punkt, der weiter als `step` vom zuletzt behaltenen entfernt liegt,
    /// plus der letzte. Für die geplante Linie, die neben der gefahrenen
    /// gespeichert wird — 1 300 Punkte sind 40 kB JSON je Fahrt, 300 sind 9.
    static func thinned(_ coords: [CLLocationCoordinate2D], step: Double = 25) -> [CLLocationCoordinate2D] {
        // Eigene flache Rechnung: `Geo` liegt im geteilten Teil, und die Uhr
        // hat die Erweiterung auf `CLLocationCoordinate2D` nicht.
        func apart(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
            let mPerDegLat = 111_320.0
            let dy = (b.latitude - a.latitude) * mPerDegLat
            let dx = (b.longitude - a.longitude) * mPerDegLat * cos(a.latitude * .pi / 180)
            return (dx * dx + dy * dy).squareRoot()
        }
        var out: [CLLocationCoordinate2D] = []
        for c in coords where valid(c) {
            guard let last = out.last else { out.append(c); continue }
            if apart(last, c) >= step { out.append(c) }
        }
        if let last = coords.last(where: valid), let kept = out.last, apart(kept, last) > 0 {
            out.append(last)
        }
        return out
    }
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
