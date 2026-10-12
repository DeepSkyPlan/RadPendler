import CoreLocation
import Foundation

/// Alle Fahrten übereinander: eine Punktwolke, die dort dicht wird, wo oft
/// gefahren wurde, und die Ampeln, an denen gestanden wurde.
///
/// Eine einzelne Fahrt sagt, wie dieser Tag war. Erst alle zusammen zeigen
/// den Weg, den man wirklich fährt — und die drei Ampeln, an denen die
/// meiste Zeit liegen bleibt. Gerechnet wird aus den gespeicherten Linien,
/// nichts davon verlässt das Gerät.
///
/// Rein und ohne Karte, damit es ohne Fahrt zu prüfen ist.
struct RideHeat {
    /// Ein Punkt der Wolke: wo gefahren wurde und von wie vielen Fahrten.
    struct Dot {
        var coordinate: CLLocationCoordinate2D
        var rides: Int
        /// Wie schnell dort im Mittel gefahren wurde, in km/h — über alle
        /// Fahrten, nur im Rollen: wer an der Ampel steht, hinterlässt hier
        /// keinen Punkt.
        var kmh = 0.0
        /// Womit dort gefahren wurde (`TravelMode.rawValue`) — jedes
        /// Verkehrsmittel hat seine eigene Wolke in seiner Farbe. Leer, wo
        /// niemand es angegeben hat.
        var mode = ""
    }

    /// Die Wolke in einer Auflösung. Aus der Nähe sieht man jede Spur, von
    /// weitem die Stadt — und eine Karte, die für beides dieselben Punkte
    /// zeichnet, ist aus der Nähe leer oder von weitem ein roter Balken.
    struct Layer {
        /// Kantenlänge der Zellen, in Metern.
        var meters: Double
        var dots: [Dot]
        /// So viele Fahrten liegen im dichtesten Punkt.
        var most: Int
    }

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

    /// Die feinste Auflösung zuerst.
    var layers: [Layer] = []
    /// Die Ampeln, die mit der meisten Wartezeit zuerst.
    var signals: [Signal] = []
    /// Wie viele Fahrten eine Linie beigetragen haben.
    var rides = 0

    /// Die Zellgrößen der Wolke. Die feinste liegt bei der Ungenauigkeit der
    /// Ortung: zwei Fahrten auf derselben Spur treffen dieselbe Zelle, die
    /// Gegenfahrbahn eine andere.
    static let layerMeters = [12.0, 48, 192, 768]
    /// Halte näher beieinander als das gehören zu derselben Ampel — auch der
    /// von der Gegenseite der Kreuzung.
    static let signalMeters = 45.0

    private struct Cell: Hashable {
        var x: Int32
        var y: Int32
        var mode: String
    }

    /// `modes` sagt je Fahrt, womit sie gefahren wurde; ohne Angabe liegt
    /// alles in einer Wolke.
    static func build(_ tracks: [RideTrack], modes: [UUID: String] = [:]) -> RideHeat {
        // Je Fahrt ihre Stücke, in gleichmäßigen Schritten: der Empfänger
        // liefert einen Punkt je Sekunde, und das sind auf der Autobahn
        // vierzig Meter — zwei Fahrten über dieselbe Straße träfen sonst
        // selten dieselbe Zelle.
        let rides = tracks.map { (mode: modes[$0.id] ?? "", line: Array(resampled($0.points).joined())) }
            .filter { !$0.line.isEmpty }
        guard let anchor = rides.first?.line.first?.coordinate else {
            return RideHeat(signals: waits(in: tracks))
        }
        let layers = layerMeters.map { meters -> Layer in
            // Ein Gitter in Grad, an der ersten Fahrt ausgerichtet: über eine
            // Stadt hinweg ändert sich die Breite eines Längengrads kaum.
            let dy = meters / 111_320
            let dx = meters / (111_320 * Swift.max(0.2, cos(anchor.latitude * .pi / 180)))
            // Je Zelle, wie viele **Fahrten** hindurchgingen — nicht wie viele
            // Punkte, sonst zählte eine rote Ampel wie zehn Fahrten. Und wo
            // in der Zelle: die Mitte dessen, was dort gefahren wurde, nicht
            // die Mitte des Gitters, sonst läge die Wolke im Karomuster.
            var sum: [Cell: (lat: Double, lon: Double, kmh: Double, points: Int, rides: Int)] = [:]
            for (mode, line) in rides {
                var seen = Set<Cell>()
                for sample in line {
                    let c = sample.coordinate
                    let cell = Cell(x: Int32((c.longitude / dx).rounded(.down)), y: Int32((c.latitude / dy).rounded(.down)),
                                    mode: mode)
                    var s = sum[cell] ?? (0, 0, 0, 0, 0)
                    s.lat += c.latitude
                    s.lon += c.longitude
                    s.kmh += sample.kmh
                    s.points += 1
                    if seen.insert(cell).inserted { s.rides += 1 }
                    sum[cell] = s
                }
            }
            let dots = sum.map { cell, s in
                Dot(coordinate: CLLocationCoordinate2D(latitude: s.lat / Double(s.points),
                                                       longitude: s.lon / Double(s.points)),
                    rides: s.rides, kmh: s.kmh / Double(s.points), mode: cell.mode)
            }
            return Layer(meters: meters, dots: dots, most: dots.map(\.rides).max() ?? 0)
        }
        return RideHeat(layers: layers, signals: waits(in: tracks), rides: rides.count)
    }

    /// Wie kräftig ein Punkt gezeichnet wird, von 0 bis 1: stufenlos, und
    /// gemessen am dichtesten Punkt dieser Karte — sonst wäre nach einem Jahr
    /// Pendeln alles gleich rot. Logarithmisch: der Schritt von einer Fahrt
    /// zu zweien zählt mehr als der von vierzig zu einundvierzig.
    static func strength(_ rides: Int, most: Int) -> Double {
        guard rides > 0 else { return 0 }
        guard most > 1 else { return 1 }
        return faintest + (1 - faintest) * log(Double(rides)) / log(Double(most))
    }

    /// Eine einzelne Fahrt bleibt sichtbar.
    static let faintest = 0.16

    /// So weit auseinander liegen die Punkte, mit denen gerechnet wird — unter
    /// der feinsten Zellgröße, damit keine Zelle übersprungen wird.
    static let stepMeters = 6.0
    /// Eine Lücke über dem ist kein Stück Straße, sondern ein Tunnel oder ein
    /// Aussetzer: dort wird nichts gezählt und nichts gezeichnet.
    static let gapMeters = 1_000.0

    /// Ein Punkt der abgetasteten Linie: wo, und wie schnell dort.
    struct Sample {
        var coordinate: CLLocationCoordinate2D
        var kmh: Double
    }

    /// Die Linie in gleichmäßigen Schritten, an Lücken geteilt.
    static func resampled(_ line: [CLLocationCoordinate2D]) -> [[CLLocationCoordinate2D]] {
        resampled(line.map { RidePoint(lat: $0.latitude, lon: $0.longitude, t: .distantPast, v: 0) })
            .map { $0.map(\.coordinate) }
    }

    /// Dasselbe mit dem Tempo: zwischen zwei Ortungen gilt das Mittel beider.
    static func resampled(_ line: [RidePoint]) -> [[Sample]] {
        guard let first = line.first else { return [] }
        var last = Sample(coordinate: first.coordinate, kmh: first.kmh)
        var pieces: [[Sample]] = []
        var piece = [last]
        for point in line.dropFirst() {
            let next = point.coordinate
            let d = last.coordinate.distance(to: next)
            if d > gapMeters {
                if piece.count > 1 { pieces.append(piece) }
                last = Sample(coordinate: next, kmh: point.kmh)
                piece = [last]
                continue
            }
            guard d >= stepMeters else { continue }
            let kmh = (last.kmh + point.kmh) / 2
            let from = last.coordinate
            for i in 1...Int(d / stepMeters) {
                let f = Double(i) * stepMeters / d
                piece.append(Sample(coordinate: CLLocationCoordinate2D(
                    latitude: from.latitude + (next.latitude - from.latitude) * f,
                    longitude: from.longitude + (next.longitude - from.longitude) * f), kmh: kmh))
            }
            last = Sample(coordinate: piece[piece.count - 1].coordinate, kmh: point.kmh)
        }
        if piece.count > 1 { pieces.append(piece) }
        return pieces
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
