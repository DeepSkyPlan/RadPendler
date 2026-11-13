import CoreLocation
import Foundation
import simd

/// **Nie gegen die Kreisverkehrsrichtung** (Rad; Nutzer, 13.11.2026: „fordert
/// er jedesmal Umfahren des [Kreisverkehrs] im Uhrzeigersinn, also gegen die
/// Verkehrsrichtung — das ist gefährlich").
///
/// Die Ursache liegt in der Karte, nicht im Profil: um einen großen
/// Kreisverkehr führt oft ein eigener Radweg (`cycleway:right=separate` an der
/// Fahrbahn), und der ist als `oneway=no` erfasst. Für BRouter ist er damit in
/// beiden Richtungen frei, und wo die eine Hälfte des Rings die besseren
/// Merkmale hat, nimmt er sie — auch rechts herum. Gemessen am 13.11.2026 auf
/// der Teststrecke, abends: „optimal“, „kürzest“ und „ruhig“ fuhren 90° bis
/// 150° im Uhrzeigersinn um den Ring; mit einem Zwischenpunkt auf der anderen
/// Seite fuhren alle drei richtig herum, gleich lang (−0,4 bis +0,2 km).
///
/// Erkennen lässt es sich nur mit dem Wissen, wo ein Kreisverkehr liegt: die
/// Fahrbahn trägt `junction=roundabout|circular` (aus Overpass, zusammen mit
/// Ampeln und Hauptstraßen, `RoadData.rings`). Fährt eine Linie in dessen
/// Umfeld um den Mittelpunkt im Uhrzeigersinn, fährt sie gegen den Verkehr —
/// bei Rechtsverkehr läuft jeder Kreisverkehr links herum.
enum RoundaboutRule {
    /// Ein Kreisverkehr: Mittelpunkt und Halbmesser seiner Fahrbahn.
    struct Ring: Equatable {
        var center: CLLocationCoordinate2D
        var radius: Double

        static func == (a: Ring, b: Ring) -> Bool {
            a.center.latitude == b.center.latitude && a.center.longitude == b.center.longitude && a.radius == b.radius
        }
    }

    /// Eine Durchfahrt einer Linie durch das Umfeld eines Rings.
    struct Passage {
        var ring: Ring
        /// Winkel beim Hineinfahren, in Grad, mathematisch (0 = Osten, 90 = Norden).
        var entry: Double
        /// Wie weit die Linie um den Mittelpunkt läuft: positiv links herum
        /// (richtig), negativ im Uhrzeigersinn (falsch).
        var sweep: Double
        /// Abstand zum Mittelpunkt, auf dem die Linie dabei fährt (Median).
        var distance: Double
    }

    /// Kleine Kreisel fährt das Rad auf der Fahrbahn mit — und die ist für
    /// BRouter ohnehin eine Einbahnstraße. Das Problem sind die großen mit
    /// eigenem Radweg drumherum.
    static let minRadius = 20.0
    /// Ab so viel Grad im Uhrzeigersinn gilt eine Durchfahrt als falsch herum.
    /// Eine Gerade, die nur am Ring vorbeiführt, überstreicht im Umfeld
    /// weniger; die gemessenen Falschfahrten lagen bei 91° bis 149°.
    static let wrongSweep = 75.0

    /// Das Umfeld, in dem eine Linie zum Ring gehört: vom halben Halbmesser
    /// bis zum Radweg außen herum (am gemessenen Ring 17 bis 49 m außerhalb
    /// der Fahrbahn).
    static func band(_ ring: Ring) -> ClosedRange<Double> {
        (0.5 * ring.radius)...(ring.radius + Swift.max(30, 0.7 * ring.radius))
    }

    /// Fügt die Stücke eines Kreisverkehrs zu Ringen zusammen. In OpenStreetMap
    /// ist einer meist aus mehreren Wegen gestückelt (an jeder Einmündung ein
    /// neuer); Stücke, die sich ein Ende teilen, gehören zum selben.
    static func rings(_ pieces: [[CLLocationCoordinate2D]]) -> [Ring] {
        let pieces = pieces.filter { $0.count >= 2 }
        guard !pieces.isEmpty else { return [] }
        var parent = Array(pieces.indices)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        func key(_ c: CLLocationCoordinate2D) -> String { String(format: "%.6f,%.6f", c.latitude, c.longitude) }
        var owner: [String: Int] = [:]
        for (i, p) in pieces.enumerated() {
            for end in [p[0], p[p.count - 1]] {
                if let j = owner[key(end)] { parent[root(i)] = root(j) } else { owner[key(end)] = i }
            }
        }
        var groups: [Int: [CLLocationCoordinate2D]] = [:]
        for (i, p) in pieces.enumerated() { groups[root(i), default: []] += p }
        return groups.values.compactMap { points in
            let flat = Flat(latitude: points[0].latitude)
            let xy = points.map(flat.point)
            let center = xy.reduce(SIMD2<Double>(0, 0), +) / Double(xy.count)
            let radius = xy.map { simd_length($0 - center) }.reduce(0, +) / Double(xy.count)
            guard radius >= minRadius else { return nil }
            return Ring(center: flat.coordinate(center), radius: radius)
        }
        .sorted { ($0.center.latitude, $0.center.longitude) < ($1.center.latitude, $1.center.longitude) }
    }

    /// Jede zusammenhängende Strecke der Linie im Umfeld eines Rings.
    static func passages(_ route: [CLLocationCoordinate2D], rings: [Ring]) -> [Passage] {
        guard route.count > 1 else { return [] }
        var out: [Passage] = []
        for ring in rings {
            let flat = Flat(latitude: ring.center.latitude)
            let c = flat.point(ring.center)
            let band = band(ring)
            var run: (entry: Double, last: Double, sweep: Double, distances: [Double])?
            func close() {
                if let r = run {
                    let sorted = r.distances.sorted()
                    out.append(Passage(ring: ring, entry: r.entry, sweep: r.sweep, distance: sorted[sorted.count / 2]))
                }
                run = nil
            }
            for point in route {
                let v = flat.point(point) - c
                let d = simd_length(v)
                guard band.contains(d) else { close(); continue }
                let angle = atan2(v.y, v.x) * 180 / .pi
                if var r = run {
                    r.sweep += remainder(angle - r.last, 360)
                    r.last = angle
                    r.distances.append(d)
                    run = r
                } else {
                    run = (angle, angle, 0, [d])
                }
            }
            close()
        }
        return out
    }

    /// Die Durchfahrten im Uhrzeigersinn — gegen den Verkehr.
    static func wrongWay(_ route: [CLLocationCoordinate2D], rings: [Ring]) -> [Passage] {
        passages(route, rings: rings).filter { $0.sweep <= -wrongSweep }
    }

    /// Wohin ein Zwischenpunkt muss, damit dieselbe Durchfahrt richtig herum
    /// läuft: auf die andere Seite des Rings, in der Mitte des Bogens, den man
    /// links herum vom Hinein- zum Hinausfahren fährt, im selben Abstand vom
    /// Mittelpunkt wie die falsche Linie — dort liegt derselbe Radweg.
    static func detour(_ p: Passage) -> CLLocationCoordinate2D {
        let angle = (p.entry + (360 + p.sweep) / 2) * .pi / 180
        let flat = Flat(latitude: p.ring.center.latitude)
        return flat.coordinate(flat.point(p.ring.center) + SIMD2(cos(angle), sin(angle)) * p.distance)
    }
}
