import CoreLocation
import Foundation

/// Alle Fahrten übereinander: eine Punktwolke, die dort dicht wird, wo oft
/// gefahren wurde, und die Stellen, an denen gestanden wurde.
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

    /// Was mit eigener Kraft oder eigenem Lenkrad gefahren wird. Eine reine
    /// Bahnfahrt hat keine Straße und keinen Halt.
    static let modes: [TravelMode] = [.bike, .bikeTransit, .car]

    /// `modes` sagt je Fahrt, womit sie gefahren wurde; ohne Angabe liegt
    /// alles in einer Wolke.
    static func build(_ tracks: [RideTrack], modes: [UUID: String] = [:]) -> RideHeat {
        var sum = Sum()
        for track in tracks { sum.add(track, mode: modes[track.id] ?? "") }
        return sum.heat()
    }

    /// Alle Fahrten als **Summe**: je Zelle, was dort zusammenkam, und welche
    /// Fahrten schon darin stecken.
    ///
    /// Bis 1.20 las die Heatmap bei jedem Öffnen jede Linie von der Platte und
    /// rechnete alles neu — mit jeder Fahrt etwas länger, nach einem Jahr
    /// Pendeln spürbar (Nutzer, 12.10.2026). Die Summe wird weggeschrieben
    /// (`RideStore.heatSum`), und eine neue Fahrt kommt nur noch dazu. Sie ist
    /// kein gespeicherter Stand, sondern ein Zwischenspeicher: was nicht mehr
    /// passt — eine gelöschte Fahrt, eine andere Fassung —, wird verworfen und
    /// neu gerechnet.
    struct Sum: Codable, Sendable {
        /// Hochzählen, wenn sich ändert, wie gerechnet wird.
        /// 2: Halte an Start und Ziel zählen nicht mehr (1.22).
        static let version = 2

        struct Cell: Hashable, Sendable {
            var x: Int32
            var y: Int32
            var mode: String
        }

        /// Was in einer Zelle zusammenkam: die Summe der Lagen und Tempi aller
        /// Punkte — und von wie vielen Fahrten.
        struct Spot: Codable, Sendable {
            var x: Int32
            var y: Int32
            var mode: String
            var lat = 0.0
            var lon = 0.0
            var kmh = 0.0
            var points = 0
            var rides = 0
        }

        /// Ein Halt, wie er in der Linie stand. Zusammengelegt wird erst beim
        /// Zeigen: welche Halte dieselbe Kreuzung sind, hängt davon ab, welche
        /// Verkehrsmittel gerade gezeigt werden.
        struct Wait: Codable, Sendable {
            var lat: Double
            var lon: Double
            var seconds: TimeInterval
            var mode: String
        }

        /// Eine Fahrt, die schon in der Summe steckt.
        struct Entry: Codable, Sendable, Equatable {
            var mode: String
            /// Ob sie eine Linie beigetragen hat.
            var line: Bool
        }

        private(set) var version = Sum.version
        /// Woran das Gitter ausgerichtet ist: die Breite der ersten Fahrt.
        private(set) var anchor: Double?
        /// Je Auflösung (`layerMeters`) die Zellen.
        private(set) var cells: [[Cell: Spot]] = RideHeat.layerMeters.map { _ in [:] }
        private(set) var waits: [Wait] = []
        private(set) var rides: [UUID: Entry] = [:]

        init() {}

        /// Ob die Summe genau aus Fahrten besteht, die es noch gibt — mit dem
        /// Verkehrsmittel, das sie heute tragen. Herausrechnen lässt sich eine
        /// Fahrt nicht (die Zelle weiß nicht mehr, was von wem kam); dann wird
        /// neu gerechnet.
        func fits(_ wanted: [UUID: String]) -> Bool {
            version == Self.version && cells.count == RideHeat.layerMeters.count
                && rides.allSatisfy { wanted[$0.key] == $0.value.mode }
        }

        /// Eine Fahrt dazu. Zweimal dieselbe ändert nichts.
        mutating func add(_ track: RideTrack, mode: String) {
            guard rides[track.id] == nil else { return }
            // In gleichmäßigen Schritten: der Empfänger liefert einen Punkt je
            // Sekunde, und das sind auf der Autobahn vierzig Meter — zwei
            // Fahrten über dieselbe Straße träfen sonst selten dieselbe Zelle.
            let line = Array(RideHeat.resampled(track.points).joined())
            rides[track.id] = Entry(mode: mode, line: !line.isEmpty)
            // Auch für Fahrten von vor 1.22: Start und Ziel sind keine Halte.
            let stops = RideStop.awayFromDoors(track.stops, start: track.points.first?.coordinate,
                                               end: track.points.last?.coordinate,
                                               rideMeters: zip(track.points, track.points.dropFirst())
                                                   .reduce(0) { $0 + $1.0.coordinate.distance(to: $1.1.coordinate) })
            waits += stops.filter(\.atSignal).map {
                Wait(lat: $0.lat, lon: $0.lon, seconds: $0.seconds, mode: mode)
            }
            guard let first = line.first else { return }
            let latitude = anchor ?? first.coordinate.latitude
            anchor = latitude
            for (i, meters) in RideHeat.layerMeters.enumerated() {
                // Ein Gitter in Grad: über eine Stadt hinweg ändert sich die
                // Breite eines Längengrads kaum.
                let dy = meters / 111_320
                let dx = meters / (111_320 * Swift.max(0.2, cos(latitude * .pi / 180)))
                // Je Zelle, wie viele **Fahrten** hindurchgingen — nicht wie
                // viele Punkte, sonst zählte eine rote Ampel wie zehn Fahrten.
                var seen = Set<Cell>()
                for sample in line {
                    let c = sample.coordinate
                    let cell = Cell(x: Int32((c.longitude / dx).rounded(.down)),
                                    y: Int32((c.latitude / dy).rounded(.down)), mode: mode)
                    var s = cells[i][cell] ?? Spot(x: cell.x, y: cell.y, mode: mode)
                    s.lat += c.latitude
                    s.lon += c.longitude
                    s.kmh += sample.kmh
                    s.points += 1
                    if seen.insert(cell).inserted { s.rides += 1 }
                    cells[i][cell] = s
                }
            }
        }

        /// Die Karte daraus — für alle Verkehrsmittel oder für eines.
        func heat(only mode: String? = nil) -> RideHeat {
            let layers = zip(RideHeat.layerMeters, cells).map { meters, cells -> Layer in
                // Wo in der Zelle: die Mitte dessen, was dort gefahren wurde,
                // nicht die Mitte des Gitters, sonst läge die Wolke im Karomuster.
                let dots = cells.values.filter { mode == nil || $0.mode == mode }.map { s in
                    Dot(coordinate: CLLocationCoordinate2D(latitude: s.lat / Double(s.points),
                                                           longitude: s.lon / Double(s.points)),
                        rides: s.rides, kmh: s.kmh / Double(s.points), mode: s.mode)
                }
                return Layer(meters: meters, dots: dots, most: dots.map(\.rides).max() ?? 0)
            }
            let shown = waits.filter { mode == nil || $0.mode == mode }
            let lines = rides.values.filter { $0.line && (mode == nil || $0.mode == mode) }.count
            return RideHeat(layers: lines > 0 ? layers : [],
                            signals: RideHeat.clustered(shown.map {
                                (CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon), $0.seconds)
                            }),
                            rides: lines)
        }

        // Die Zellen als Liste: ein Wörterbuch mit zusammengesetztem
        // Schlüssel schriebe `Codable` ohnehin so, nur doppelt.
        private enum CodingKeys: String, CodingKey { case version, anchor, cells, waits, rides }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decode(Int.self, forKey: .version)
            anchor = try c.decodeIfPresent(Double.self, forKey: .anchor)
            cells = try c.decode([[Spot]].self, forKey: .cells).map { spots in
                Dictionary(spots.map { (Cell(x: $0.x, y: $0.y, mode: $0.mode), $0) }, uniquingKeysWith: { a, _ in a })
            }
            waits = try c.decode([Wait].self, forKey: .waits)
            rides = try c.decode([UUID: Entry].self, forKey: .rides)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(version, forKey: .version)
            try c.encodeIfPresent(anchor, forKey: .anchor)
            try c.encode(cells.map { Array($0.values) }, forKey: .cells)
            try c.encode(waits, forKey: .waits)
            try c.encode(rides, forKey: .rides)
        }
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

    /// Die Halte der Fahrten, nach Ort zusammengelegt.
    static func waits(in tracks: [RideTrack]) -> [Signal] {
        clustered(tracks.flatMap(\.stops).filter(\.atSignal).map { ($0.coordinate, $0.seconds) })
    }

    static func clustered(_ stops: [(coordinate: CLLocationCoordinate2D, seconds: TimeInterval)]) -> [Signal] {
        var found: [Signal] = []
        for stop in stops {
            if let i = found.firstIndex(where: { $0.coordinate.distance(to: stop.coordinate) <= signalMeters }) {
                // Der Ort wandert mit: der Schwerpunkt aller Halte.
                let n = Double(found[i].stops)
                found[i].coordinate = CLLocationCoordinate2D(
                    latitude: (found[i].coordinate.latitude * n + stop.coordinate.latitude) / (n + 1),
                    longitude: (found[i].coordinate.longitude * n + stop.coordinate.longitude) / (n + 1))
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
