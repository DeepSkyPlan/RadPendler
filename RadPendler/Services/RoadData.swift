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
        for e in elements {
            if e["type"] as? String == "node", let lat = e["lat"] as? Double, let lon = e["lon"] as? Double {
                let c = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                if Geo.valid(c) { signals.append(c) }
                continue
            }
            guard let tags = e["tags"] as? [String: String],
                  let geom = e["geometry"] as? [String: Any], let coords = geom["coordinates"] as? [[Double]] else { continue }
            // A road in a tunnel is not something the rider crosses.
            if let t = tags["tunnel"], !t.isEmpty, t != "no" { continue }
            let ref = tags["ref"].flatMap { $0.isEmpty ? nil : $0.replacingOccurrences(of: ";", with: "/") }
            let name = [ref, tags["name"].flatMap { $0.isEmpty ? nil : $0 }].compactMap { $0 }.first ?? "Hauptstraße"
            let points = Geo.validated(coords.filter { $0.count >= 2 }
                .map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) })
            guard points.count >= 2 else { continue }
            roads.append(Road(name: name, points: points))
        }
        return RoadData(signals: signals, roads: roads)
    }

    enum OverpassError: LocalizedError {
        case malformed
        case corridorTooBig
        var errorDescription: String? {
            switch self {
            case .malformed: "OpenStreetMap-Daten: unerwartete Antwort"
            case .corridorTooBig: "Strecke zu lang für die Ampelzählung (OpenStreetMap)"
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
    static func around(_ coords: [CLLocationCoordinate2D], spacing: Double = spacing,
                       radius: Double = radius) -> Corridor {
        var kept: [CLLocationCoordinate2D] = []
        for c in coords where Geo.valid(c) {
            if kept.contains(where: { $0.distance(to: c) < spacing }) { continue }
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
    private var memory: [Box: (data: RoadData, corridor: Corridor?)] = [:]
    /// Requests already on their way. Bike, car and bike+rail ask for
    /// overlapping corridors at the same moment; without this they all miss the
    /// cache, and Overpass answers the same 4-MB question three times — and
    /// throttles, which turned a 2-second plan into a 24-second one.
    private var inFlight: [Box: Task<RoadData, Error>] = [:]
    /// Korridore, für die gerade ein zweiter, geduldigerer Versuch läuft.
    private var warming: Set<Box> = []
    /// Two corridors are all a trip has; more is a leak, not a cache.
    private let maxBoxesInMemory = 2
    private let maxAge: TimeInterval = 30 * 86_400
    private var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("osm-roads")
    }

    func data(covering coords: [CLLocationCoordinate2D]) async throws -> RoadData {
        guard !coords.isEmpty else { throw RoadData.OverpassError.malformed }
        let box = Box(around: coords)
        guard !box.isTooLarge else { throw RoadData.OverpassError.corridorTooBig }
        // Der Kasten bleibt der Schlüssel — er ist über Tage hinweg derselbe,
        // während der Schlauch mit jeder neu gefundenen Route ein wenig
        // anders aussieht. Benutzt wird ein Treffer aber nur, wenn sein
        // Schlauch auch diese Strecke deckt.
        if let hit = memory.first(where: { $0.key.contains(box) && ($0.value.corridor?.covers(coords) ?? true) }) {
            return hit.value.data
        }
        let corridor = Corridor.around(coords)
        // Someone is already fetching a corridor that covers this one: wait for
        // their answer instead of asking the same question again. The task is
        // registered before the first `await`, or the actor would let the next
        // caller past this line while we suspend.
        if let running = inFlight.first(where: { $0.key.contains(box) })?.value {
            return try await running.value
        }
        if let (b, d, c) = loadFromDisk(covering: box, coords: coords) {
            remember(b, d, c)
            return d
        }
        let task = Task { [directory] () throws -> RoadData in
            let raw = try await Self.fetch(corridor)
            let parsed = try RoadData.parse(raw)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("\(box.fileName).json")
            try? raw.write(to: file, options: .completeFileProtection)
            Self.writeSidecar(box, corridor: corridor, next: file)
            return parsed
        }
        inFlight[box] = task
        defer { inFlight[box] = nil }
        do {
            let parsed = try await task.value
            remember(box, parsed, corridor)
            sweep(keeping: box)
            return parsed
        } catch {
            // Overpass antwortet auf eine kleine Frage in zwei Sekunden und
            // auf diese hier mit `504`: die Abfrage ist teuer, nicht der
            // Server kaputt. Der Plan wartet darauf nicht — er sagt, dass die
            // Ampeln fehlen, und holt sie in Ruhe nach. Einmal geholt, liegen
            // sie dreißig Tage auf der Platte, und der nächste Plan hat sie.
            warm(box, corridor)
            throw error
        }
    }

    /// Der zweite Versuch: derselbe Korridor, aber mit viel mehr Geduld — auf
    /// beiden Seiten. Er blockiert nichts und meldet nichts; er füllt nur den
    /// Zwischenspeicher.
    private func warm(_ box: Box, _ corridor: Corridor) {
        guard warming.insert(box).inserted else { return }
        Task { [directory] in
            defer { warming.remove(box) }
            guard let raw = try? await Self.fetch(corridor, serverSeconds: 180, requestSeconds: 210),
                  let parsed = try? RoadData.parse(raw) else { return }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("\(box.fileName).json")
            try? raw.write(to: file, options: .completeFileProtection)
            Self.writeSidecar(box, corridor: corridor, next: file)
            remember(box, parsed, corridor)
            sweep(keeping: box)
        }
    }

    /// Keeps the memory cache to the two corridors a trip can have.
    private func remember(_ box: Box, _ data: RoadData, _ corridor: Corridor?) {
        memory[box] = (data, corridor)
        guard memory.count > maxBoxesInMemory else { return }
        // Drop boxes that the new one already covers first, then anything.
        for key in memory.keys where key != box && box.contains(key) { memory[key] = nil }
        while memory.count > maxBoxesInMemory, let victim = memory.keys.first(where: { $0 != box }) {
            memory[victim] = nil
        }
    }

    /// Reads the box back from the little sidecar next to each cached answer.
    /// The data file is named by a hash, so a directory listing no longer
    /// spells out the corridor between home and work.
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

    private func sidecar(of file: URL) -> Sidecar? {
        let url = file.deletingPathExtension().appendingPathExtension("box")
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let decoded = try? JSONDecoder().decode(Sidecar.self, from: data) { return decoded }
        // Die alte Form: vier Zahlen, durch Leerzeichen getrennt.
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let parts = text.split(separator: " ").compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        return Sidecar(south: parts[0], west: parts[1], north: parts[2], east: parts[3], corridor: nil)
    }

    private static func writeSidecar(_ box: Box, corridor: Corridor, next file: URL) {
        let url = file.deletingPathExtension().appendingPathExtension("box")
        let side = Sidecar(south: box.south, west: box.west, north: box.north, east: box.east,
                           corridor: corridor)
        guard let data = try? JSONEncoder().encode(side) else { return }
        // Derselbe Schutz wie für die Antwort daneben: hier steht der Korridor
        // in Klartextkoordinaten, also genau die Linie zwischen Zuhause und
        // Arbeit, die der gehashte Dateiname verbergen soll.
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    /// Deletes what is stale or already contained in the box just written — the
    /// files were only ever skipped on read, never removed, and three
    /// overlapping corridors had grown to 13 MB.
    private func sweep(keeping box: Box) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory,
                                                      includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }
        for f in files where f.pathExtension == "json" {
            guard f.deletingPathExtension().lastPathComponent != box.fileName else { continue }
            let age = (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                .map { Date.now.timeIntervalSince($0) } ?? .infinity
            // No sidecar means the file predates this scheme: it is unreadable
            // to us now, so it is rubbish either way.
            let contained = self.sidecar(of: f).map { box.contains($0.box) } ?? true
            guard age > maxAge || contained else { continue }
            try? fm.removeItem(at: f)
            try? fm.removeItem(at: f.deletingPathExtension().appendingPathExtension("box"))
        }
    }

    /// Ein Treffer muss beides: im Kasten liegen **und** mit seinem Schlauch
    /// diese Strecke decken. Eine alte Datei ohne Schlauch deckt alles im
    /// Kasten — damals wurde er ganz geholt.
    private func loadFromDisk(covering box: Box,
                              coords: [CLLocationCoordinate2D]) -> (Box, RoadData, Corridor?)? {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory,
                                                      includingPropertiesForKeys: [.contentModificationDateKey])
        else { return nil }
        for f in files where f.pathExtension == "json" {
            guard let side = self.sidecar(of: f), side.box.contains(box) else { continue }
            guard side.corridor?.covers(coords) ?? true else { continue }
            let age = (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                .map { Date.now.timeIntervalSince($0) } ?? .infinity
            guard age < maxAge, let data = try? Data(contentsOf: f),
                  let parsed = try? RoadData.parse(data) else { continue }
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

    private static func fetch(_ corridor: Corridor, serverSeconds: Int = 25,
                              requestSeconds: TimeInterval = 30) async throws -> Data {
        let query = Self.query(corridor, serverSeconds: serverSeconds)
        var request = URLRequest(url: URL(string: "https://overpass-api.de/api/interpreter")!,
                                 timeoutInterval: requestSeconds)
        request.httpMethod = "POST"
        request.setValue("RadPendler iOS (private commute planner)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [.init(name: "data", value: query)]
        request.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
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
