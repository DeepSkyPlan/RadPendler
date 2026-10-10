import CoreLocation
import Foundation
import simd

/// Local flat projection in metres around a reference latitude — accurate to
/// well under a metre over the 30 km of a Berlin commute.
struct Flat {
    let kx: Double
    let ky = 111_320.0

    init(latitude: Double) { kx = 111_320 * cos(latitude * .pi / 180) }

    func point(_ c: CLLocationCoordinate2D) -> SIMD2<Double> { SIMD2(c.longitude * kx, c.latitude * ky) }

    /// Zurück in Grad — für alles, was auf der Ebene einen Punkt *findet* und
    /// ihn danach auf der Karte zeigen muss.
    func coordinate(_ p: SIMD2<Double>) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: p.y / ky, longitude: kx != 0 ? p.x / kx : 0)
    }
}

/// Traffic signals and large roads (trunk/primary/secondary) from
/// OpenStreetMap, for judging how quiet a bike route is.
struct RoadData {
    struct Road {
        var name: String
        var points: [CLLocationCoordinate2D]
    }

    var signals: [CLLocationCoordinate2D]
    var roads: [Road]
    /// Kreuzungen, an denen dieser Fahrer schon gemessen hat — gehalten oder
    /// durchgefahren. Sie kommen nicht aus Overpass und liegen deshalb neben
    /// den Ampeln der Karte, nicht zwischen ihnen: eine zwischengespeicherte
    /// Antwort bleibt, was der Server geschickt hat.
    var learned: [LearnedSignal] = []

    /// Overpass JSON: signal nodes via `out skel`, roads via `convert … out geom`.
    static func parse(_ data: Data) throws -> RoadData {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = root["elements"] as? [[String: Any]] else { throw OverpassError.malformed }
        var signals: [CLLocationCoordinate2D] = []
        var roads: [Road] = []
        // Ein gewachsener Schlauch besteht aus mehreren Antworten, und wo sie
        // sich überlappen, steht dieselbe Ampel und dieselbe Straße zweimal da.
        var seenSignals = Set<String>(), seenRoads = Set<String>()
        for e in elements {
            if e["type"] as? String == "node", let lat = e["lat"] as? Double, let lon = e["lon"] as? Double {
                let c = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                if Geo.valid(c), seenSignals.insert(String(format: "%.6f,%.6f", lat, lon)).inserted { signals.append(c) }
                continue
            }
            guard let tags = e["tags"] as? [String: String],
                  let geom = e["geometry"] as? [String: Any], let coords = geom["coordinates"] as? [[Double]] else { continue }
            // A road in a tunnel is not something the rider crosses.
            if let t = tags["tunnel"], !t.isEmpty, t != "no" { continue }
            let ref = tags["ref"].flatMap { $0.isEmpty ? nil : $0.replacingOccurrences(of: ";", with: "/") }
            let name = [ref, tags["name"].flatMap { $0.isEmpty ? nil : $0 }].compactMap { $0 }.first ?? L("Hauptstraße")
            let points = Geo.validated(coords.filter { $0.count >= 2 }
                .map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) })
            guard points.count >= 2, let first = points.first, let last = points.last else { continue }
            let key = String(format: "%@|%d|%.6f,%.6f|%.6f,%.6f", name, points.count,
                             first.latitude, first.longitude, last.latitude, last.longitude)
            guard seenRoads.insert(key).inserted else { continue }
            roads.append(Road(name: name, points: points))
        }
        return RoadData(signals: signals, roads: roads)
    }

    /// Zwei Antworten in einer, als dieselbe Art Datei: die Elemente beider
    /// hintereinander. Was dabei doppelt kommt, sortiert `parse` aus.
    static func merged(_ a: Data, _ b: Data) -> Data {
        func elements(_ d: Data) -> [Any] {
            let root = Log.attempt("Straßendaten zusammenlegen (lesen)") { try JSONSerialization.jsonObject(with: d) }
            return (root as? [String: Any])?["elements"] as? [Any] ?? []
        }
        let all = elements(a) + elements(b)
        return Log.attempt("Straßendaten zusammenlegen") { try JSONSerialization.data(withJSONObject: ["elements": all]) } ?? b
    }

    enum OverpassError: LocalizedError {
        case malformed
        case corridorTooBig
        /// Die Abfrage läuft noch; die Planung wartet nicht länger darauf.
        case stillFetching
        /// Overpass hat eben abgelehnt; für ein paar Minuten wird nicht gefragt.
        case unavailable
        var errorDescription: String? {
            switch self {
            case .malformed: L("OpenStreetMap-Daten: unerwartete Antwort")
            case .stillFetching: L("OpenStreetMap-Daten werden noch geholt")
            case .unavailable: L("OpenStreetMap antwortet gerade nicht")
            case .corridorTooBig: L("Strecke zu lang für die Ampelzählung (OpenStreetMap)")
            }
        }
    }
}

/// Der Schlauch um die gefundenen Routen, in dem gefragt wird.
///
/// Vorher fragte die App den **umschließenden Kasten** ab. Bei einer
/// diagonalen Pendelstrecke ist das halb Berlin: gemessen 3,6 MB und 18 238
/// Elemente für eine 20-km-Strecke, von denen die Auswertung ein Dreizehntel
/// anfasst. Overpass kann statt dessen entlang einer Linie fragen
/// (`around:`) — dieselbe Strecke: 287 kB und 1 409 Elemente.
struct Corridor: Codable, Equatable {
    /// Ausgedünnte Stützpunkte, Breitengrad und Längengrad.
    var points: [[Double]]
    /// Radius um jeden Punkt, in Metern.
    var radius: Double

    /// Abstand der Stützpunkte. Enger als der Radius, sonst hat der Schlauch
    /// Löcher zwischen den Punkten.
    static let spacing = 150.0
    /// So weit neben der Route werden Straßen noch gebraucht: `RouteAnalyzer`
    /// sucht Querungen in einem Kasten von 100 m um die Linie und zählt Meter
    /// bis 20 m daneben. 150 m ist mit Luft darüber.
    static let needed = 150.0
    static let radius = 300.0

    /// Jeden Punkt, der weiter als `spacing` von allen schon behaltenen weg
    /// ist. Das dünnt jede einzelne Route aus **und** legt die gemeinsamen
    /// Stücke mehrerer Varianten übereinander — neun Routen über dieselbe
    /// Hauptstraße ergeben einen Schlauch, nicht neun.
    /// Über ein Gitter aus `spacing`-Zellen statt über alles schon Behaltene:
    /// „liegt hier schon einer?" ist damit ein Nachschlagen und kein Vergleich
    /// mit jedem Vorgänger. Bei vier Radrouten sind das sechstausend Punkte
    /// gegen zweihundert — über eine Million Vergleiche, jeder davon vorher
    /// mit zwei frisch angelegten `CLLocation`-Objekten, und das dreimal je
    /// Planung.
    static func around(_ coords: [CLLocationCoordinate2D], spacing: Double = spacing,
                       radius: Double = radius) -> Corridor {
        guard let first = coords.first(where: Geo.valid) else { return Corridor(points: [], radius: radius) }
        let mPerDegLat = 111_320.0
        let mPerDegLon = mPerDegLat * cos(first.latitude * .pi / 180)
        // **Behalten wird, was kein schon behaltener Punkt erreicht** — mit
        // demselben Maß, mit dem `covers` später prüft. Bis 1.17 entschied
        // allein die Nachbarzelle: zwei behaltene Punkte lagen dann bis zu
        // 300 m auseinander, die Mitte dazwischen 150 m und mehr von beiden,
        // und `covers` verlangt höchstens 150. Ein Schlauch deckte so die
        // Strecke nicht, für die er selbst geholt worden war: der
        // Zwischenspeicher traf fast nie, jede Planung fragte Overpass neu,
        // und die Ampeln fehlten, sooft Overpass nicht wollte (gemessen
        // 09.10.2026: drei Planungen hintereinander, drei Abfragen).
        let reach = Swift.min(spacing, radius - needed) * 0.9
        let reach2 = reach * reach
        var cells: [Int64: [(x: Double, y: Double)]] = [:]
        var kept: [CLLocationCoordinate2D] = []
        for c in coords where Geo.valid(c) {
            let (mx, my) = (c.longitude * mPerDegLon, c.latitude * mPerDegLat)
            let x = Int64((mx / spacing).rounded(.down))
            let y = Int64((my / spacing).rounded(.down))
            // Die eigene Zelle und ihre acht Nachbarn — weiter als eine Zelle
            // reicht `reach` nicht.
            var near = false
            for dx in -1...1 where !near {
                for dy in -1...1 where !near {
                    for p in cells[(x + Int64(dx)) &* 1_000_003 &+ (y + Int64(dy))] ?? [] {
                        let (ex, ey) = (p.x - mx, p.y - my)
                        if ex * ex + ey * ey <= reach2 { near = true; break }
                    }
                }
            }
            if near { continue }
            cells[x &* 1_000_003 &+ y, default: []].append((mx, my))
            kept.append(c)
        }
        return Corridor(points: kept.map { [$0.latitude, $0.longitude] }, radius: radius)
    }

    var coordinates: [CLLocationCoordinate2D] {
        points.compactMap { $0.count >= 2 ? CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) : nil }
    }

    /// Reicht das, was für diesen Schlauch geholt wurde, auch für jene Route?
    ///
    /// Ein Punkt der neuen Route, der `d` von einem Stützpunkt entfernt liegt,
    /// hat seine 150-m-Umgebung nur dann vollständig im Geholten, wenn
    /// `d + needed ≤ radius`. Geprüft wird jeder fünfte Punkt; enger liegen
    /// sie ohnehin nicht als ein paar Meter auseinander.
    func covers(_ coords: [CLLocationCoordinate2D]) -> Bool {
        let mine = coordinates
        guard !mine.isEmpty else { return false }
        let limit = radius - Self.needed
        guard limit > 0 else { return false }
        for (i, c) in coords.enumerated() where i % 5 == 0 {
            if !mine.contains(where: { $0.distance(to: c) <= limit }) { return false }
        }
        return true
    }

    /// Die Punkte einer Strecke, die dieser Schlauch **nicht** erreicht — das,
    /// wonach noch gefragt werden muss. Dasselbe Maß wie `covers`, aber an
    /// jedem Punkt: ein übersprungener wäre ein Loch im Nachgeholten.
    func unreached(of coords: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        let mine = coordinates
        let limit = radius - Self.needed
        guard !mine.isEmpty, limit > 0 else { return coords }
        // In Metern auf einer Ebene: auf diese Entfernungen genau genug, und
        // sechstausend Punkte gegen sechshundert sind sonst Millionen
        // Großkreisrechnungen.
        let kLat = 111_320.0, kLon = kLat * cos(mine[0].latitude * .pi / 180)
        let flat = mine.map { ($0.latitude * kLat, $0.longitude * kLon) }
        let limit2 = limit * limit
        return coords.filter { c in
            let (y, x) = (c.latitude * kLat, c.longitude * kLon)
            return !flat.contains { let dy = $0.0 - y, dx = $0.1 - x; return dy * dy + dx * dx <= limit2 }
        }
    }

    /// Beantwortet dieser Schlauch alles, was jener beantwortet hat? Mit
    /// demselben Maß wie beim Lesen, nur an **jedem** Stützpunkt des anderen:
    /// dessen Punkte liegen ohnehin 150 m auseinander, und ein übersprungener
    /// wäre ein Loch von 750 m.
    func covers(_ other: Corridor) -> Bool {
        let mine = coordinates
        let limit = radius - Self.needed
        guard !mine.isEmpty, limit > 0, radius >= other.radius else { return false }
        return other.coordinates.allSatisfy { c in mine.contains { $0.distance(to: c) <= limit } }
    }
}

/// Fetches `RoadData` for a bounding box from the Overpass API and keeps it
/// on disk for 30 days. The box is snapped outward to a 0.05° grid so the
/// daily commute always hits the same file; the first fetch for the Berlin
/// south-west corridor is ~3.6 MB and takes ~7 s.
actor RoadDataStore {
    struct Box: Hashable {
        var south, west, north, east: Double

        /// With 1e-6 slack: grid values like 52.55 come back as 52.550000000000004.
        func contains(_ o: Box) -> Bool {
            let e = 1e-6
            return south <= o.south + e && west <= o.west + e && north >= o.north - e && east >= o.east - e
        }

        /// Ob die beiden sich berühren — dann lässt sich an das eine anbauen,
        /// was für das andere fehlt.
        func overlaps(_ o: Box) -> Bool {
            south <= o.north && o.south <= north && west <= o.east && o.west <= east
        }

        /// Der kleinste Kasten um beide.
        func union(_ o: Box) -> Box {
            Box(south: Swift.min(south, o.south), west: Swift.min(west, o.west),
                north: Swift.max(north, o.north), east: Swift.max(east, o.east))
        }

        /// Identifies the box. Not the file name — that would write the
        /// corridor between home and work onto the disk in plain sight.
        var key: String { String(format: "%.2f_%.2f_%.2f_%.2f", south, west, north, east) }

        /// What the cached file is called: the same box, but unreadable to
        /// anyone listing the directory.
        var fileName: String {
            var hash: UInt64 = 0xcbf29ce484222325
            for byte in key.utf8 {
                hash = (hash ^ UInt64(byte)) &* 0x100000001b3
            }
            return String(format: "osm-%016llx", hash)
        }

        /// Berlin to Hamburg is about 2.5° of latitude, and Overpass would
        /// answer that with hundreds of megabytes — if at all. Past this the
        /// app does without traffic lights and says so.
        var isTooLarge: Bool { north - south > 1.2 || east - west > 1.8 }

        init(south: Double, west: Double, north: Double, east: Double) {
            (self.south, self.west, self.north, self.east) = (south, west, north, east)
        }

        /// Box around the coordinates, padded ~300 m and snapped to 0.05°.
        init(around coords: [CLLocationCoordinate2D]) {
            let g = 0.05, pad = 0.003
            south = ((coords.map(\.latitude).min()! - pad) / g).rounded(.down) * g
            north = ((coords.map(\.latitude).max()! + pad) / g).rounded(.up) * g
            west = ((coords.map(\.longitude).min()! - pad) / g).rounded(.down) * g
            east = ((coords.map(\.longitude).max()! + pad) / g).rounded(.up) * g
            (south, west, north, east) = (Self.snap(south), Self.snap(west), Self.snap(north), Self.snap(east))
        }

        private static func snap(_ v: Double) -> Double { (v * 100).rounded() / 100 }
    }

    static let shared = RoadDataStore()

    /// Wer die Frage stellt. Einspeisbar, weil ein Planer, der offline sein
    /// soll, es sonst nicht ist: bis 1.4 lief die Overpass-Abfrage über ein
    /// fest verdrahtetes `URLSession.shared` weiter, während alle anderen
    /// Dienste längst ins Leere liefen.
    private let session: URLSession

    /// Für Tests: ein eigener Ordner statt des Zwischenspeichers der App.
    private let folder: URL?

    init(session: URLSession = .shared, folder: URL? = nil) {
        self.session = session
        self.folder = folder
    }

    private var memory: [Box: (data: RoadData, corridor: Corridor?)] = [:]
    /// Requests already on their way. Bike, car and bike+rail ask for
    /// overlapping corridors at the same moment; without this they all miss the
    /// cache, and Overpass answers the same 4-MB question three times — and
    /// throttles, which turned a 2-second plan into a 24-second one.
    private var inFlight: [Box: Task<RoadData, Error>] = [:]
    /// Drei fragen je Planung: Rad, Auto und die Zubringer von Rad + Bahn.
    /// Mit zweien verdrängten sie sich gegenseitig, und der dritte fragte
    /// jedes Mal die Platte. Mehr ist ein Leck, kein Zwischenspeicher.
    static let maxBoxesInMemory = 3
    private let maxAge: TimeInterval = 30 * 86_400
    private var directory: URL {
        folder ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("osm-roads")
    }

    /// So lange wartet eine Planung auf Straßendaten, die erst geholt werden
    /// müssen. Bis 1.17 wartete sie, bis Overpass antwortete oder aufgab —
    /// gemessen am 09.10.2026: die vier Radrouten standen nach 3,6 s, dann
    /// neun Sekunden Warten auf ein `504`, und beim nächsten Plan wieder
    /// sieben. Jetzt läuft die Abfrage neben der Planung weiter; was sie
    /// bringt, liegt dreißig Tage auf der Platte, und der nächste Plan hat es.
    ///
    /// Anderthalb Sekunden, seit 1.19: kommt die Antwort später, meldet der
    /// Speicher es (`arrived`), und der Plan auf dem Bildschirm rechnet Rad
    /// und Auto mit den Ampeln nach. Mit vier Sekunden dauerte der erste Plan
    /// nach einem Update acht bis zehn, und die Ampeln standen trotzdem erst
    /// nach dem Neustart da (Nutzer, 10.10.2026).
    static let planPatience: TimeInterval = 1.5

    /// Geht hinaus, sobald neue Straßendaten da sind — für den Plan, der
    /// ohne sie fertig wurde.
    static let arrived = Notification.Name("RoadDataStore.arrived")

    /// - Parameter patience: wie lange höchstens gewartet wird, wenn die Daten
    ///   erst geholt werden müssen; nil wartet bis zum Ende. Die Abfrage selbst
    ///   läuft in jedem Fall weiter.
    func data(covering coords: [CLLocationCoordinate2D],
              patience: TimeInterval? = RoadDataStore.planPatience) async throws -> RoadData {
        guard !coords.isEmpty else { throw RoadData.OverpassError.malformed }
        let box = Box(around: coords)
        guard !box.isTooLarge else { throw RoadData.OverpassError.corridorTooBig }
        let deadline = patience.map { Date.now.addingTimeInterval($0) }
        // Mehrmals: wer auf die Abfrage eines anderen wartet, bekommt deren
        // Schlauch — und der deckt die eigene Strecke vielleicht nicht ganz.
        // Dann wird nachgeholt, was fehlt.
        for _ in 0..<3 {
            // Der Kasten bleibt der Schlüssel — er ist über Tage hinweg derselbe,
            // während der Schlauch mit jeder neu gefundenen Route ein wenig
            // anders aussieht. Benutzt wird ein Treffer aber nur, wenn sein
            // Schlauch auch diese Strecke deckt.
            if let hit = memory.first(where: { $0.key.contains(box) && ($0.value.corridor?.covers(coords) ?? true) }) {
                return hit.value.data
            }
            if let (b, d, c) = loadFromDisk(covering: box, coords: coords) {
                remember(b, d, c)
                return d
            }
            // Overpass hat eben zweimal abgelehnt: nicht bei jeder Planung
            // wieder anklopfen und vier Sekunden auf dieselbe Absage warten.
            if let gaveUp, Date.now.timeIntervalSince(gaveUp) < Self.backOff {
                throw RoadData.OverpassError.unavailable
            }
            // **Eine Abfrage zur Zeit**, wem sie auch gehört. Rad, Auto und die
            // Zubringer fragen im selben Augenblick nach drei Schläuchen; der
            // öffentliche Server lässt zwei Anfragen je Adresse zu und
            // beantwortet die dritte mit `504` (gemessen 09.10.2026). Wer
            // wartet, baut danach an das an, was die erste gebracht hat. Der
            // Auftrag steht vor dem ersten `await`, sonst ließe der Akteur den
            // Nächsten an dieser Zeile vorbei.
            let task = inFlight.values.first ?? start(box, coords)
            // Im zweiten, geduldigen Versuch dauert es Minuten — darauf wartet
            // keine Planung.
            if secondAttempt, patience != nil { throw RoadData.OverpassError.stillFetching }
            let remaining = deadline.map { Swift.max(0, $0.timeIntervalSinceNow) }
            _ = try await Self.value(of: task, within: remaining)
        }
        if let hit = memory.first(where: { $0.key.contains(box) }) { return hit.value.data }
        throw RoadData.OverpassError.stillFetching
    }

    /// Ob die laufende Abfrage schon ihr zweiter Versuch ist.
    private var secondAttempt = false
    /// Wann Overpass zuletzt auch den zweiten Versuch abgelehnt hat.
    private var gaveUp: Date?
    /// So lange wird danach nicht wieder gefragt.
    static let backOff: TimeInterval = 180

    private func retrying() { secondAttempt = true }

    /// Holt, was für diese Strecke **noch fehlt**, und legt es zu dem, was
    /// schon da ist.
    ///
    /// Bis 1.17 galt: deckt der gespeicherte Schlauch die neue Linie nicht
    /// ganz, wird alles neu geholt — der ganze Schlauch um alle Linien, knapp
    /// ein Megabyte, zehn Sekunden, und oft ein `504`. Mit vier Radlinien, der
    /// gewohnten und den Zubringern sah die Linienmenge bei fast jeder Planung
    /// ein wenig anders aus; die Ampeln fehlten entsprechend oft. Jetzt wächst
    /// der Schlauch: gefragt wird nur nach den Stücken, die kein gespeicherter
    /// Punkt erreicht, und die Antwort wird angehängt. Nach ein paar Planungen
    /// ist alles da, was auf diesem Weg je gebraucht wird.
    ///
    /// Die Abfrage gehört niemandem: sie läuft zu Ende, auch wenn die Planung,
    /// die sie ausgelöst hat, längst weiter ist, und versucht es nach einem
    /// Fehlschlag einmal mit viel mehr Geduld.
    private func start(_ box: Box, _ coords: [CLLocationCoordinate2D]) -> Task<RoadData, Error> {
        let base = partial(containing: box)
        let missing = base.map { $0.corridor.unreached(of: coords) } ?? coords
        let piece = Corridor.around(missing)
        // Der Kasten wächst mit: die ruhige Linie über andere Straßen oder ein
        // Bahnhof weiter draußen sprengen ihn sonst, und es finge von vorn an.
        let target = base.map { $0.box.union(box) } ?? box
        let task = Task { [directory] () throws -> RoadData in
            do {
                let raw: Data
                do {
                    raw = try await self.fetch(piece)
                } catch {
                    // Overpass antwortet auf eine kleine Frage in zwei Sekunden
                    // und auf eine große gern mit `504`: die Abfrage ist teuer,
                    // nicht der Server kaputt. Noch einmal, in Ruhe.
                    Log.note("Straßendaten holen", error)
                    self.retrying()
                    raw = try await self.fetch(piece, serverSeconds: 180, requestSeconds: 210)
                }
                let merged = base.map { RoadData.merged($0.raw, raw) } ?? raw
                let corridor = Corridor(points: (base?.corridor.points ?? []) + piece.points, radius: piece.radius)
                let parsed = try RoadData.parse(merged)
                Self.store(merged, in: directory, as: target)
                let file = directory.appendingPathComponent("\(target.fileName).json")
                Self.writeSidecar(target, corridor: corridor, next: file)
                self.finish(target, parsed, corridor)
                return parsed
            } catch {
                Log.note("Straßendaten nachholen", error)
                self.finish(target, nil, nil)
                throw error
            }
        }
        inFlight[target] = task
        return task
    }

    private func finish(_ box: Box, _ data: RoadData?, _ corridor: Corridor?) {
        inFlight[box] = nil
        secondAttempt = false
        gaveUp = data == nil ? .now : nil
        guard let data, let corridor else { return }
        remember(box, data, corridor)
        sweep(keeping: box, corridor)
        // Nur der Speicher der App meldet sich; der eines Tests hat niemanden,
        // den es etwas anginge.
        if folder == nil {
            Task { @MainActor in NotificationCenter.default.post(name: Self.arrived, object: nil) }
        }
    }

    /// Wartet auf eine laufende Abfrage, aber nicht länger als `seconds`.
    /// Wer zu früh geht, bricht sie nicht ab.
    private static func value(of task: Task<RoadData, Error>, within seconds: TimeInterval?) async throws -> RoadData {
        guard let seconds else { return try await task.value }
        let once = Once()
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                let result = await task.result
                if once.first() { continuation.resume(with: result) }
            }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                if once.first() { continuation.resume(throwing: RoadData.OverpassError.stillFetching) }
            }
        }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func first() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if done { return false }
            done = true
            return true
        }
    }

    /// Wie alt eine Datei ist; unendlich, wenn es sich nicht sagen lässt —
    /// dann gilt sie als abgelaufen.
    static func age(of file: URL) -> TimeInterval {
        // swiftlint:disable:next naked_try_optional
        (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            .map { Date.now.timeIntervalSince($0) } ?? .infinity
    }

    /// Was zu diesem Kasten schon auf der Platte liegt, auch wenn es die
    /// Strecke nicht ganz deckt — das, woran angebaut wird. Von mehreren das
    /// mit dem längsten Schlauch.
    private func partial(containing box: Box) -> (box: Box, raw: Data, corridor: Corridor)? {
        let fm = FileManager.default
        guard let files = Log.attempt("Straßendaten-Ordner lesen", missingIsFine: true, {
            try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        }) else { return nil }
        var best: (box: Box, file: URL, corridor: Corridor)?
        for f in files where f.pathExtension == "json" {
            guard let side = self.sidecar(of: f), side.box.overlaps(box), let corridor = side.corridor,
                  !side.box.union(box).isTooLarge else { continue }
            let age = Self.age(of: f)
            let longest = best?.corridor.points.count ?? 0
            guard maxAge > age, corridor.points.count > longest else { continue }
            best = (side.box, f, corridor)
        }
        guard let best, let raw = Log.attempt("Straßendaten lesen", { try Data(contentsOf: best.file) }) else { return nil }
        return (best.box, raw, best.corridor)
    }

    /// Keeps the memory cache to the three corridors a plan asks for.
    private func remember(_ box: Box, _ data: RoadData, _ corridor: Corridor?) {
        memory[box] = (data, corridor)
        guard memory.count > Self.maxBoxesInMemory else { return }
        // Drop what the new one really answers first, then anything.
        for (key, value) in memory where key != box
            && Self.superseded(key, value.corridor, by: box, corridor) { memory[key] = nil }
        while memory.count > Self.maxBoxesInMemory, let victim = memory.keys.first(where: { $0 != box }) {
            memory[victim] = nil
        }
    }

    /// Ob eine ältere Antwort weg kann, weil die neue alles beantwortet, was
    /// sie beantwortet hat. Bis 1.9.1 reichte dafür, dass der neue **Kasten**
    /// den alten enthielt — aber geholt wird nur der Schlauch darin: die
    /// Zubringer-Antwort für den Bahnhof im Norden ging, sobald die Radroute
    /// im Süden einen größeren Kasten brauchte, und wurde beim nächsten Plan
    /// neu geholt.
    ///
    /// Eine alte Antwort ohne Schlauch ist ein ganz geholter Kasten; den
    /// ersetzt kein Schlauch.
    static func superseded(_ oldBox: Box, _ old: Corridor?, by box: Box, _ corridor: Corridor?) -> Bool {
        guard box.contains(oldBox) else { return false }
        guard let corridor else { return true }
        guard let old else { return false }
        return corridor.covers(old)
    }

    /// Was neben einer zwischengespeicherten Antwort steht: welcher Kasten,
    /// und welcher Schlauch tatsächlich abgefragt wurde.
    private struct Sidecar: Codable {
        var south, west, north, east: Double
        /// Fehlt bei Dateien aus der Zeit, als der ganze Kasten geholt wurde.
        /// Die decken alles ab, was in ihm liegt — deshalb `nil` und nicht
        /// „deckt nichts".
        var corridor: Corridor?
        var box: Box { Box(south: south, west: west, north: north, east: east) }
    }

    /// Reads the box back from the little sidecar next to each cached answer.
    /// The data file is named by a hash, so a directory listing no longer
    /// spells out the corridor between home and work. Eine Datei, deren
    /// Beiwagen sich nicht lesen lässt, räumt `sweep` weg.
    private func sidecar(of file: URL) -> Sidecar? {
        let url = file.deletingPathExtension().appendingPathExtension("box")
        guard let data = Log.attempt("Beiwagen lesen", missingIsFine: true, { try Data(contentsOf: url) })
        else { return nil }
        return Log.attempt("Beiwagen auspacken") { try JSONDecoder().decode(Sidecar.self, from: data) }
    }

    /// Die Schutzklasse des Zwischenspeichers: lesbar, sobald das Gerät seit
    /// dem Einschalten einmal entsperrt wurde.
    ///
    /// Bis 1.16 stand hier `complete` — und damit war der Zwischenspeicher
    /// genau dann zu, wenn er gebraucht wird: das Telefon steckt gesperrt in
    /// der Tasche, die Fahrt läuft, es wird neu geplant oder iOS weckt die App
    /// für die Warnungen. Lesen wie Schreiben scheiterten stumm, und die Frage
    /// ging jedes Mal neu an Overpass. Der Korridor verrät nichts, was nicht
    /// auch in den Einstellungen steht (Zuhause und Arbeit, dieselbe Klasse).
    static let protection: Data.WritingOptions = .completeFileProtectionUntilFirstUserAuthentication

    /// Legt eine Antwort ab. `atomic`, weil eine Datei aus einer älteren
    /// Fassung noch die alte Schutzklasse trägt und sich bei gesperrtem Gerät
    /// nicht überschreiben, wohl aber ersetzen lässt.
    private static func store(_ raw: Data, in directory: URL, as box: Box) {
        Log.attempt("Straßendaten-Ordner anlegen") {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let file = directory.appendingPathComponent("\(box.fileName).json")
        Log.attempt("Straßendaten schreiben") { try raw.write(to: file, options: [.atomic, protection]) }
    }

    private static func writeSidecar(_ box: Box, corridor: Corridor, next file: URL) {
        let url = file.deletingPathExtension().appendingPathExtension("box")
        let side = Sidecar(south: box.south, west: box.west, north: box.north, east: box.east,
                           corridor: corridor)
        guard let data = Log.attempt("Beiwagen kodieren", { try JSONEncoder().encode(side) }) else { return }
        // Derselbe Schutz wie für die Antwort daneben: hier steht der Korridor
        // in Klartextkoordinaten, also genau die Linie zwischen Zuhause und
        // Arbeit, die der gehashte Dateiname verbergen soll.
        Log.attempt("Beiwagen schreiben") { try data.write(to: url, options: [.atomic, protection]) }
    }

    /// Deletes what is stale or answered by the corridor just written — the
    /// files were only ever skipped on read, never removed, and three
    /// overlapping corridors had grown to 13 MB.
    private func sweep(keeping box: Box, _ corridor: Corridor) {
        let fm = FileManager.default
        guard let files = Log.attempt("Straßendaten-Ordner lesen", missingIsFine: true, {
            try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        }) else { return }
        for f in files where f.pathExtension == "json" {
            guard f.deletingPathExtension().lastPathComponent != box.fileName else { continue }
            let age = Self.age(of: f)
            // No sidecar means the file predates this scheme: it is unreadable
            // to us now, so it is rubbish either way.
            let redundant = self.sidecar(of: f).map { Self.superseded($0.box, $0.corridor, by: box, corridor) } ?? true
            guard age > maxAge || redundant else { continue }
            Log.attempt("Straßendaten aufräumen", missingIsFine: true) { try fm.removeItem(at: f) }
            Log.attempt("Beiwagen aufräumen", missingIsFine: true) {
                try fm.removeItem(at: f.deletingPathExtension().appendingPathExtension("box"))
            }
        }
    }

    /// Ein Treffer muss beides: im Kasten liegen **und** mit seinem Schlauch
    /// diese Strecke decken. Eine alte Datei ohne Schlauch deckt alles im
    /// Kasten — damals wurde er ganz geholt.
    private func loadFromDisk(covering box: Box,
                              coords: [CLLocationCoordinate2D]) -> (Box, RoadData, Corridor?)? {
        let fm = FileManager.default
        guard let files = Log.attempt("Straßendaten-Ordner lesen", missingIsFine: true, {
            try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        }) else { return nil }
        for f in files where f.pathExtension == "json" {
            guard let side = self.sidecar(of: f), side.box.contains(box) else { continue }
            guard side.corridor?.covers(coords) ?? true else { continue }
            let age = Self.age(of: f)
            guard age < maxAge, let data = Log.attempt("Straßendaten lesen", { try Data(contentsOf: f) }),
                  let parsed = Log.attempt("Straßendaten auspacken", { try RoadData.parse(data) }) else { continue }
            return (side.box, parsed, side.corridor)
        }
        return nil
    }

    /// Die Frage an Overpass: Ampeln und große Straßen **entlang der Route**,
    /// nicht im ganzen Kasten. Gemessen an einer 20-km-Strecke quer durch
    /// Berlin: 287 kB und 1 409 Elemente statt 3,6 MB und 18 238.
    ///
    /// Die beiden Ampel-Schreibweisen — `highway=traffic_signals` am Knoten
    /// und `crossing=traffic_signals` an der Querung — kommen über einen
    /// Schlüssel-Ausdruck in **eine** Abfrage; sonst stünde die lange
    /// Punktliste dreimal im Text statt zweimal.
    static func query(_ corridor: Corridor, serverSeconds: Int = 25) -> String {
        let around = corridor.points.map { String(format: "%.5f,%.5f", $0[0], $0[1]) }.joined(separator: ",")
        let r = Int(corridor.radius)
        return """
        [out:json][timeout:\(serverSeconds)];
        node(around:\(r),\(around))[~"^(highway|crossing)$"~"^traffic_signals$"];out skel qt;
        way(around:\(r),\(around))[highway~"^(trunk|primary|secondary)(_link)?$"];
        convert way ::geom=geom(),ref=t["ref"],name=t["name"],tunnel=t["tunnel"];out geom qt;
        """
    }

    private func fetch(_ corridor: Corridor, serverSeconds: Int = 25,
                       requestSeconds: TimeInterval = 30) async throws -> Data {
        let query = Self.query(corridor, serverSeconds: serverSeconds)
        var request = URLRequest(url: URL(string: "https://overpass-api.de/api/interpreter")!,
                                 timeoutInterval: requestSeconds)
        request.httpMethod = "POST"
        request.setValue(AppIdentity.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [.init(name: "data", value: query)]
        request.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

/// How pleasant a bike route is: traffic lights, large roads crossed, metres
/// ridden beside large roads.
struct BikeRouteStats: Equatable {
    /// Signalised junctions on the route (signal nodes within 15 m, merged within 60 m).
    var signals: Int
    /// Large roads crossed, in riding order. Riding along a road does not count.
    var crossings: [String]
    /// Metres within 20 m of a large road — on it or on a bike path beside it.
    var mainRoadMeters: Double
    /// Where the lit junctions are, for drawing them on the map.
    var signalPoints: [CLLocationCoordinate2D] = []
    /// Von diesen Kreuzungen die, an denen dieser Fahrer schon gemessen hat.
    /// Sie sind in `signals` mitgezählt und stehen hier noch einmal, weil sie
    /// ihre eigene Wartezeit mitbringen — siehe `PlanSettings.signalWait`.
    var learnedSignals: [LearnedSignal] = []

    /// Metre-equivalent of noise and stress: a crossing is as bad as 300 m
    /// beside a main road, a traffic light as 100 m.
    var disturbance: Double { mainRoadMeters + 300 * Double(crossings.count) + 100 * Double(signals) }

    /// The places where traffic makes one stop: every lit junction and every
    /// main road that has to be crossed.
    ///
    /// Deliberately **not** `disturbance`. That one is dominated by the metres
    /// ridden beside main roads — thousands against a handful of junctions —
    /// so "ruhigst" answers "where do I ride next to the fewest cars", and
    /// this one answers "where do I have to stop for them least often". Those
    /// are different routes, and the point of offering both is that they are.
    var stops: Int { signals + crossings.count }

    static func == (a: BikeRouteStats, b: BikeRouteStats) -> Bool {
        a.signals == b.signals && a.crossings == b.crossings && a.mainRoadMeters == b.mainRoadMeters
    }
}

enum RouteAnalyzer {
    static func analyze(_ route: [CLLocationCoordinate2D], roads data: RoadData) -> BikeRouteStats {
        guard route.count > 1 else { return BikeRouteStats(signals: 0, crossings: [], mainRoadMeters: 0) }
        let flat = Flat(latitude: route[0].latitude)
        let r = route.map(flat.point)
        var cum: [Double] = [0]
        for (a, b) in zip(r, r.dropFirst()) { cum.append(cum.last! + simd_length(b - a)) }

        let lo = SIMD2(r.map(\.x).min()! - 100, r.map(\.y).min()! - 100)
        let hi = SIMD2(r.map(\.x).max()! + 100, r.map(\.y).max()! + 100)
        let inBox = { (p: SIMD2<Double>) in p.x >= lo.x && p.x <= hi.x && p.y >= lo.y && p.y <= hi.y }

        // Road segments near the route, bucketed in a 100 m grid.
        struct Seg { var a, b: SIMD2<Double>; var road: Int }
        var roadNames: [String] = []
        var segs: [Seg] = []
        for road in data.roads {
            let pts = road.points.map(flat.point)
            // Bounding boxes must overlap; a long straight road can pass the
            // route with both ends far outside its box.
            guard let rlo = pts.dropFirst().reduce(pts.first, { simd_min($0!, $1) }),
                  let rhi = pts.dropFirst().reduce(pts.first, { simd_max($0!, $1) }),
                  rlo.x <= hi.x, rhi.x >= lo.x, rlo.y <= hi.y, rhi.y >= lo.y else { continue }
            let id = roadNames.count
            roadNames.append(road.name)
            for (a, b) in zip(pts, pts.dropFirst()) { segs.append(Seg(a: a, b: b, road: id)) }
        }
        let grid = SegmentGrid(segs.map { ($0.a, $0.b) }, cell: 100)

        func distance(_ p: SIMD2<Double>, toRoad id: Int?, within radius: Double) -> Double {
            var best = Double.infinity
            for i in grid.candidates(near: p, radius: radius) where id == nil || segs[i].road == id
                || roadNames[segs[i].road] == roadNames[id!] {
                best = min(best, pointSegment(p, segs[i].a, segs[i].b))
            }
            return best
        }
        func point(at s: Double) -> SIMD2<Double> {
            let s = min(max(s, 0), cum.last!)
            var i = (cum.firstIndex { $0 > s } ?? cum.count) - 1
            i = min(max(i, 0), r.count - 2)
            let len = cum[i + 1] - cum[i]
            return len > 0 ? r[i] + (r[i + 1] - r[i]) * ((s - cum[i]) / len) : r[i]
        }

        // Crossings: the route intersects a large road and is well away from
        // it (and from its other carriageway) 80 m before and after.
        var hits: [(s: Double, name: String)] = []
        for i in 0..<(r.count - 1) {
            let a = r[i], b = r[i + 1]
            for j in grid.candidates(alongSegment: a, b) {
                guard let t = intersect(a, b, segs[j].a, segs[j].b) else { continue }
                let s = cum[i] + t * (cum[i + 1] - cum[i])
                let road = segs[j].road
                if distance(point(at: s - 80), toRoad: road, within: 40) > 35,
                   distance(point(at: s + 80), toRoad: road, within: 40) > 35 {
                    hits.append((s, roadNames[road]))
                }
            }
        }
        var crossings: [(s: Double, name: String)] = []
        for h in hits.sorted(by: { $0.s < $1.s }) {
            if let last = crossings.last, h.s - last.s < 80 || (h.name == last.name && h.s - last.s < 600) {
                crossings[crossings.count - 1].s = h.s
                continue
            }
            crossings.append(h)
        }

        // Metres beside a large road.
        var main = 0.0
        for i in 0..<(r.count - 1) where distance((r[i] + r[i + 1]) / 2, toRoad: nil, within: 20) < 20 {
            main += cum[i + 1] - cum[i]
        }

        // Signalised junctions. What the map knows and what the rider has
        // measured goes through the same sieve: it counts where it sits on
        // this route, not where it came from.
        let routeGrid = SegmentGrid(zip(r, r.dropFirst()).map { ($0, $1) }, cell: 100)
        var signalHits: [(s: Double, c: CLLocationCoordinate2D, learned: LearnedSignal?)] = []
        func collect(_ c: CLLocationCoordinate2D, _ learned: LearnedSignal?) {
            let p = flat.point(c)
            guard inBox(p) else { return }
            var best = (d: Double.infinity, s: 0.0)
            for i in routeGrid.candidates(near: p, radius: 15) {
                let d = pointSegment(p, r[i], r[i + 1])
                if d < best.d { best = (d, cum[i]) }
            }
            if best.d < 15 { signalHits.append((best.s, c, learned)) }
        }
        for c in data.signals { collect(c, nil) }
        for l in data.learned { collect(l.coordinate, l) }
        // One junction can carry several signal nodes: keep the first of each
        // cluster. Measured beats mapped — the same junction seen from both
        // sides is one junction, and the one with seconds on it is the one
        // that knows what it costs.
        var junctions: [(c: CLLocationCoordinate2D, learned: LearnedSignal?)] = []
        var last = -Double.infinity
        for hit in signalHits.sorted(by: { $0.s < $1.s }) {
            if hit.s - last > 60 {
                junctions.append((hit.c, hit.learned))
            } else if junctions.last?.learned == nil, let l = hit.learned {
                junctions[junctions.count - 1].learned = l
            }
            last = hit.s
        }
        return BikeRouteStats(signals: junctions.count, crossings: crossings.map(\.name),
                              mainRoadMeters: main, signalPoints: junctions.map(\.c),
                              learnedSignals: junctions.compactMap(\.learned))
    }

    static func pointSegment(_ p: SIMD2<Double>, _ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
        let d = b - a, l = simd_length_squared(d)
        let t = l > 0 ? min(max(simd_dot(p - a, d) / l, 0), 1) : 0
        return simd_length(p - (a + d * t))
    }

    /// Parameter along a→b where it crosses c→d, or nil.
    static func intersect(_ a: SIMD2<Double>, _ b: SIMD2<Double>, _ c: SIMD2<Double>, _ d: SIMD2<Double>) -> Double? {
        let r = b - a, s = d - c
        let den = r.x * s.y - r.y * s.x
        guard abs(den) > 1e-9 else { return nil }
        let q = c - a
        let t = (q.x * s.y - q.y * s.x) / den
        let u = (q.x * r.y - q.y * r.x) / den
        return (0...1).contains(t) && (0...1).contains(u) ? t : nil
    }
}

/// Uniform grid over line segments for "what is near here" queries.
struct SegmentGrid {
    private var cells: [SIMD2<Int>: [Int]] = [:]
    private let size: Double

    init(_ segments: [(SIMD2<Double>, SIMD2<Double>)], cell: Double) {
        size = cell
        for (i, (a, b)) in segments.enumerated() {
            for key in keys(from: simd_min(a, b), to: simd_max(a, b)) { cells[key, default: []].append(i) }
        }
    }

    /// More cells than this from a single segment means the segment is not a
    /// road — a NaN, an infinity or two points on opposite sides of the world.
    /// Converting those to `Int` traps; spanning them fills memory.
    private static let maxCellsPerSegment = 10_000

    private func keys(from lo: SIMD2<Double>, to hi: SIMD2<Double>) -> [SIMD2<Int>] {
        guard lo.x.isFinite, lo.y.isFinite, hi.x.isFinite, hi.y.isFinite else { return [] }
        let fx0 = (lo.x / size).rounded(.down), fx1 = (hi.x / size).rounded(.down)
        let fy0 = (lo.y / size).rounded(.down), fy1 = (hi.y / size).rounded(.down)
        let limit = Double(Int.max / 2)
        guard abs(fx0) < limit, abs(fx1) < limit, abs(fy0) < limit, abs(fy1) < limit else { return [] }
        let x0 = Int(fx0), x1 = max(Int(fx1), Int(fx0))
        let y0 = Int(fy0), y1 = max(Int(fy1), Int(fy0))
        guard (x1 - x0 + 1) * (y1 - y0 + 1) <= Self.maxCellsPerSegment else { return [] }
        var out: [SIMD2<Int>] = []
        for x in x0...x1 { for y in y0...y1 { out.append(SIMD2(x, y)) } }
        return out
    }

    func candidates(near p: SIMD2<Double>, radius: Double) -> Set<Int> {
        var out = Set<Int>()
        for k in keys(from: p - radius, to: p + radius) { out.formUnion(cells[k] ?? []) }
        return out
    }

    func candidates(alongSegment a: SIMD2<Double>, _ b: SIMD2<Double>) -> Set<Int> {
        var out = Set<Int>()
        for k in keys(from: simd_min(a, b), to: simd_max(a, b)) { out.formUnion(cells[k] ?? []) }
        return out
    }
}
