import CoreLocation
import Foundation
import simd

/// Die Wege, die dieser Fahrer wirklich fährt — und was die Planung daraus lernt.
///
/// Kein Router kennt die Straße, die man nach dem dritten Mal einfach nimmt:
/// die Fahrradstraße, die in keinem Profil besser dasteht als die Nebenstraße
/// daneben, den Korso, der auf dem Papier eine Hauptstraße ist (Fahrt
/// 30.09.2026: Südwestkorso und Prinzregentenstraße, von keinem Profil
/// gewählt). Die eigenen Fahrten kennen sie. Zwei Dinge macht die Planung
/// daraus:
///
/// - **„gewohnt"**: gibt es für diese Strecke schon zwei Radfahrten, wird die
///   typischste davon — die, die den anderen am meisten gleicht — als Linie
///   nachgefahren: BRouter bekommt vier Punkte darauf als Zwischenpunkte und
///   legt daraus eine saubere Route, mit Ampeln, Belägen und Zeit wie jede
///   andere.
/// - **Vertrautheit**: jede Linie bekommt ihren Anteil an Metern auf schon
///   gefahrenen Wegen. Der zählt beim Abwägen für „optimal" wie weniger
///   Störung — man kennt den Weg und weiß, dass er taugt.
///
/// Die Linien liegen nur auf dem Gerät, ausgedünnt auf alle 50 m. Hundert
/// Pendelfahrten sind so ein paar hundert Kilobyte; in den iCloud-Speicher
/// (ein Megabyte für alles) gehören sie nicht.
actor RiddenPaths {
    static let shared = RiddenPaths()

    struct Line: Codable, Equatable {
        var id: UUID
        var date: Date
        var points: [TrackPoint]

        var coordinates: [CLLocationCoordinate2D] { points.map(\.coordinate) }
    }

    /// So viele Fahrten bleiben — die jüngsten. Wege ändern sich; was vor
    /// einem Jahr gefahren wurde, ist vielleicht längst eine Baustelle.
    static let keep = 200
    /// Ab so vielen Fahrten auf derselben Strecke ist etwas „gewohnt".
    static let minRides = 2
    /// So nah müssen Anfang und Ende einer Fahrt an Start und Ziel liegen.
    static let endRadius = 500.0
    /// So nah muss eine Linie an einem gefahrenen Weg liegen, um als vertraut
    /// zu gelten — eine Straßenbreite plus die Ungenauigkeit des Empfängers.
    static let familiarRadius = 40.0
    /// Nur Radfahrten ab dieser Länge; alles darunter ist Rangieren.
    static let minMeters = 2_000.0

    private let file: URL
    private var lines: [Line]? = nil

    init(file: URL? = nil) {
        self.file = file ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory).appending(path: "Rides").appending(path: "ridden.json")
    }

    private func loaded() -> [Line] {
        if let lines { return lines }
        let read = (try? Data(contentsOf: file)).flatMap { Stored.list(Line.self, from: $0) } ?? []
        lines = read
        return read
    }

    private func save(_ list: [Line]) {
        lines = list
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = Stored.encode(list) { try? data.write(to: file, options: .atomic) }
    }

    /// Eine gefahrene Radfahrt kommt dazu. Andere Verkehrsmittel und kurze
    /// Stücke nicht: nur das Rad sucht sich seine Straßen selbst.
    func add(_ ride: Ride, track: RideTrack) {
        guard ride.travelMode == .bike, ride.meters >= Self.minMeters else { return }
        let thin = Self.thinned(track.coordinates)
        guard thin.count >= 4 else { return }
        var list = loaded().filter { $0.id != ride.id }
        list.append(Line(id: ride.id, date: ride.started, points: thin.map(TrackPoint.init)))
        list.sort { $0.date > $1.date }
        save(Array(list.prefix(Self.keep)))
    }

    func remove(_ id: UUID) {
        let list = loaded()
        guard list.contains(where: { $0.id == id }) else { return }
        save(list.filter { $0.id != id })
    }

    var count: Int { loaded().count }

    /// Die gefahrenen Linien von hier nach dort — auch die Rückfahrten,
    /// umgedreht: wer abends über den Korso heimfährt, fährt morgens meist
    /// denselben hin.
    func matching(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> [[CLLocationCoordinate2D]] {
        Array(Self.matching(loaded().map(\.coordinates), from: from, to: to).prefix(Self.recent))
    }

    /// Die jüngsten so vielen Fahrten einer Strecke zählen. Das hält die
    /// Rechnung klein — „typisch" vergleicht jede mit jeder — und folgt einem
    /// Wegwechsel nach ein paar Wochen.
    static let recent = 10

    // MARK: Rechnung — rein, damit sie ohne Gerät zu prüfen ist

    nonisolated static func matching(_ lines: [[CLLocationCoordinate2D]], from: CLLocationCoordinate2D,
                                     to: CLLocationCoordinate2D) -> [[CLLocationCoordinate2D]] {
        lines.compactMap { line in
            guard let a = line.first, let b = line.last else { return nil }
            if a.distance(to: from) <= endRadius, b.distance(to: to) <= endRadius { return line }
            if b.distance(to: from) <= endRadius, a.distance(to: to) <= endRadius { return Array(line.reversed()) }
            return nil
        }
    }

    /// Ein Punkt alle `every` Meter. Was dazwischen liegt, ist für die Frage
    /// „welche Straße" ohne Belang.
    nonisolated static func thinned(_ line: [CLLocationCoordinate2D], every: Double = 50) -> [CLLocationCoordinate2D] {
        guard var last = line.first else { return [] }
        var out = [last]
        for c in line.dropFirst() where c.distance(to: last) >= every {
            out.append(c)
            last = c
        }
        if let end = line.last, out.count > 1, end.distance(to: out.last!) > 1 { out.append(end) }
        return out
    }

    /// Umgekehrt: Punkte **einfügen**, bis keiner weiter als `every` vom
    /// nächsten liegt. Die gespeicherten Linien haben alle 50 m einen.
    nonisolated static func densified(_ line: [CLLocationCoordinate2D], every: Double) -> [CLLocationCoordinate2D] {
        guard let first = line.first else { return [] }
        var out = [first]
        for (a, b) in zip(line, line.dropFirst()) {
            let n = Swift.max(1, Int((a.distance(to: b) / every).rounded(.up)))
            for i in 1...n {
                let f = Double(i) / Double(n)
                out.append(CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * f,
                                                  longitude: a.longitude + (b.longitude - a.longitude) * f))
            }
        }
        return out
    }

    /// Welcher Anteil einer Linie (nach Metern) auf einem der gefahrenen Wege
    /// liegt.
    nonisolated static func familiarShare(_ route: [CLLocationCoordinate2D],
                                          ridden: [[CLLocationCoordinate2D]],
                                          radius: Double = familiarRadius) -> Double {
        guard route.count > 1, !ridden.isEmpty else { return 0 }
        let grid = Grid(ridden.flatMap { densified($0, every: 15) }, cell: radius)
        var total = 0.0, familiar = 0.0
        for (a, b) in zip(route, route.dropFirst()) {
            let step = a.distance(to: b)
            guard step > 0 else { continue }
            // Lange Geraden stückweise: BRouter setzt gern hundert Meter ohne
            // Stützpunkt, und nur die Enden zu prüfen hieße raten.
            let parts = Swift.max(1, Int(step / 20))
            for i in 0..<parts {
                let f = (Double(i) + 0.5) / Double(parts)
                let p = CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * f,
                                               longitude: a.longitude + (b.longitude - a.longitude) * f)
                total += step / Double(parts)
                if grid.near(p, within: radius) { familiar += step / Double(parts) }
            }
        }
        return total > 0 ? familiar / total : 0
    }

    /// Die typischste Fahrt: die, deren Meter am meisten auf den anderen
    /// liegen. Eine Fahrt mit einem Umweg zum Bäcker oder mit springender
    /// Ortung verliert dabei gegen die, die man immer fährt.
    nonisolated static func typical(_ lines: [[CLLocationCoordinate2D]]) -> [CLLocationCoordinate2D]? {
        guard lines.count >= minRides else { return nil }
        let scored = lines.indices.map { i -> (Int, Double) in
            let others = lines.indices.filter { $0 != i }.map { lines[$0] }
            return (i, familiarShare(lines[i], ridden: others))
        }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 >= 0.5 else { return nil }
        return lines[best.0]
    }

    /// Punkte auf der Linie, bei diesen Anteilen ihrer Länge — die
    /// Zwischenpunkte, an denen BRouter sie nachfährt.
    nonisolated static func via(_ line: [CLLocationCoordinate2D],
                                at fractions: [Double] = [0.2, 0.4, 0.6, 0.8]) -> [CLLocationCoordinate2D] {
        let cum = TurnGuide.cumulative(line)
        guard let length = cum.last, length > 0 else { return [] }
        return fractions.compactMap { f in
            let target = length * f
            guard let i = cum.indices.min(by: { abs(cum[$0] - target) < abs(cum[$1] - target) }) else { return nil }
            return line[i]
        }
    }

    /// Ein grobes Raster für die Frage „liegt hier ein gefahrener Punkt in
    /// der Nähe?" — sonst wären es Tausende mal Tausende Abstände.
    struct Grid {
        private let flat: Flat
        private let cell: Double
        private var cells: [SIMD2<Int>: [SIMD2<Double>]] = [:]

        init(_ points: [CLLocationCoordinate2D], cell: Double) {
            flat = Flat(latitude: points.first?.latitude ?? 52.5)
            self.cell = cell
            for c in points {
                let p = flat.point(c)
                cells[key(p), default: []].append(p)
            }
        }

        private func key(_ p: SIMD2<Double>) -> SIMD2<Int> {
            SIMD2(Int((p.x / cell).rounded(.down)), Int((p.y / cell).rounded(.down)))
        }

        func near(_ c: CLLocationCoordinate2D, within r: Double) -> Bool {
            let p = flat.point(c), k = key(p)
            for dx in -1...1 { for dy in -1...1 {
                for q in cells[k &+ SIMD2(dx, dy)] ?? [] where simd_distance(p, q) <= r { return true }
            } }
            return false
        }
    }
}
