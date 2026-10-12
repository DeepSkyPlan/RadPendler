import CoreLocation
import Foundation

/// Alle Fahrten übereinander: welche Straßen wie oft gefahren wurden, und an
/// welchen Ampeln wie lange gestanden wurde.
///
/// Eine einzelne Fahrt sagt, wie dieser Tag war. Erst alle zusammen zeigen
/// den Weg, den man wirklich fährt — und die drei Ampeln, an denen die
/// meiste Zeit liegen bleibt. Gerechnet wird aus den gespeicherten Linien,
/// nichts davon verlässt das Gerät.
///
/// Rein und ohne Karte, damit es ohne Fahrt zu prüfen ist.
struct RideHeat {
    /// Ein Stück Linie, das in einem Zug gezeichnet wird: gleiche Häufigkeit
    /// von Anfang bis Ende.
    struct Run {
        var level: Level
        var coordinates: [CLLocationCoordinate2D]
    }

    /// Drei Stufen reichen: mehr unterscheidet auf einer Karte niemand.
    enum Level: Int, CaseIterable { case once, often, most }

    /// Eine Ampel, wie die Fahrten sie erlebt haben.
    struct Signal: Identifiable {
        var id: Int
        var coordinate: CLLocationCoordinate2D
        /// Wie oft dort gestanden wurde …
        var stops: Int
        /// … wie lange zusammen, und am längsten.
        var total: TimeInterval
        var longest: TimeInterval

        var mean: TimeInterval { stops > 0 ? total / Double(stops) : 0 }
    }

    var runs: [Run] = []
    /// Die Ampeln, die mit der meisten Wartezeit zuerst.
    var signals: [Signal] = []
    /// Wie viele Fahrten eine Linie beigetragen haben.
    var rides = 0
    /// So viele Fahrten liegen auf dem meistgefahrenen Stück.
    var most = 0

    /// Kantenlänge einer Zelle: so nah beieinander ist es dieselbe Straße.
    /// Breiter als die Ungenauigkeit der Ortung, schmaler als ein Häuserblock.
    static let cellMeters = 30.0
    /// Halte näher beieinander als das gehören zu derselben Ampel — auch der
    /// von der Gegenseite der Kreuzung.
    static let signalMeters = 45.0

    private struct Cell: Hashable {
        var x: Int32
        var y: Int32
    }

    private struct Edge: Hashable {
        var a: Cell
        var b: Cell

        init(_ a: Cell, _ b: Cell) {
            // Hin und zurück ist dieselbe Straße.
            if a.x < b.x || (a.x == b.x && a.y <= b.y) { (self.a, self.b) = (a, b) } else { (self.a, self.b) = (b, a) }
        }
    }

    static func build(_ tracks: [RideTrack]) -> RideHeat {
        // Je Fahrt ihre Stücke, in gleichmäßigen Schritten: der Empfänger
        // liefert einen Punkt je Sekunde, und das sind auf der Autobahn
        // vierzig Meter — zwei Fahrten über dieselbe Straße träfen sonst
        // selten dieselbe Zelle.
        let rides = tracks.map { resampled($0.coordinates) }.filter { !$0.isEmpty }
        guard let anchor = rides.first?.first?.first else {
            return RideHeat(signals: waits(in: tracks))
        }
        // Ein Gitter in Grad, an der ersten Fahrt ausgerichtet: über eine
        // Stadt hinweg ändert sich die Breite eines Längengrads kaum.
        let dy = cellMeters / 111_320
        let dx = cellMeters / (111_320 * Swift.max(0.2, cos(anchor.latitude * .pi / 180)))
        func cell(_ c: CLLocationCoordinate2D) -> Cell {
            Cell(x: Int32((c.longitude / dx).rounded(.down)), y: Int32((c.latitude / dy).rounded(.down)))
        }
        // Erst zählen: je Zelle, wie viele **Fahrten** hindurchgingen — nicht
        // wie viele Punkte, sonst zählte eine rote Ampel wie zehn Fahrten.
        var count: [Cell: Int] = [:]
        for pieces in rides {
            for c in Set(pieces.joined().map(cell)) { count[c, default: 0] += 1 }
        }
        let most = count.values.max() ?? 0
        // Dann zeichnen: jedes Stück Straße einmal, in Zügen gleicher Stufe.
        var drawn = Set<Edge>()
        var runs: [Run] = []
        for line in rides.joined() {
            var run: Run?
            func close() {
                if let r = run, r.coordinates.count > 1 { runs.append(r) }
                run = nil
            }
            for (from, to) in zip(line, line.dropFirst()) {
                let (a, b) = (cell(from), cell(to))
                // Innerhalb einer Zelle ist nichts zu zeichnen; der Zug läuft weiter.
                if a == b { continue }
                guard drawn.insert(Edge(a, b)).inserted else {
                    close()
                    continue
                }
                let l = level(Swift.min(count[a] ?? 0, count[b] ?? 0), most: most)
                if run?.level == l { run?.coordinates.append(to) } else {
                    close()
                    run = Run(level: l, coordinates: [from, to])
                }
            }
            close()
        }
        return RideHeat(runs: runs, signals: waits(in: tracks), rides: rides.count, most: most)
    }

    /// So weit auseinander liegen die Punkte, mit denen gerechnet wird — unter
    /// der Zellgröße, damit keine Zelle übersprungen wird.
    static let stepMeters = cellMeters / 2
    /// Eine Lücke über dem ist kein Stück Straße, sondern ein Tunnel oder ein
    /// Aussetzer: dort wird nichts gezählt und nichts gezeichnet.
    static let gapMeters = 1_000.0

    /// Die Linie in gleichmäßigen Schritten, an Lücken geteilt.
    static func resampled(_ line: [CLLocationCoordinate2D]) -> [[CLLocationCoordinate2D]] {
        guard var last = line.first else { return [] }
        var pieces: [[CLLocationCoordinate2D]] = []
        var piece = [last]
        for next in line.dropFirst() {
            let d = last.distance(to: next)
            if d > gapMeters {
                if piece.count > 1 { pieces.append(piece) }
                piece = [next]
                last = next
                continue
            }
            guard d >= stepMeters else { continue }
            let steps = Int(d / stepMeters)
            for i in 1...steps {
                let f = Double(i) * stepMeters / d
                piece.append(CLLocationCoordinate2D(latitude: last.latitude + (next.latitude - last.latitude) * f,
                                                    longitude: last.longitude + (next.longitude - last.longitude) * f))
            }
            last = piece[piece.count - 1]
        }
        if piece.count > 1 { pieces.append(piece) }
        return pieces
    }

    /// Einmal ist einmal. „Meist" ist die obere Hälfte dessen, was am
    /// häufigsten gefahren wurde — bei drei Fahrten also schon die zweite.
    static func level(_ rides: Int, most: Int) -> Level {
        if rides <= 1 { return .once }
        return Double(rides) >= Swift.max(2, Double(most) / 2) ? .most : .often
    }

    /// Halte an Ampeln, nach Ort zusammengelegt.
    static func waits(in tracks: [RideTrack]) -> [Signal] {
        var found: [Signal] = []
        for stop in tracks.flatMap(\.stops) where stop.atSignal {
            if let i = found.firstIndex(where: { $0.coordinate.distance(to: stop.coordinate) <= signalMeters }) {
                // Der Ort wandert mit: der Schwerpunkt aller Halte.
                let n = Double(found[i].stops)
                found[i].coordinate = CLLocationCoordinate2D(
                    latitude: (found[i].coordinate.latitude * n + stop.lat) / (n + 1),
                    longitude: (found[i].coordinate.longitude * n + stop.lon) / (n + 1))
                found[i].stops += 1
                found[i].total += stop.seconds
                found[i].longest = Swift.max(found[i].longest, stop.seconds)
            } else {
                found.append(Signal(id: found.count, coordinate: stop.coordinate, stops: 1,
                                    total: stop.seconds, longest: stop.seconds))
            }
        }
        return found.sorted { $0.total > $1.total }
    }
}
