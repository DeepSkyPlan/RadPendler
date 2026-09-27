import CoreLocation
import Foundation

/// Bike routes from the public BRouter server (brouter.de), which routes on
/// OpenStreetMap with selectable profiles. Apple Maps has exactly one bike
/// route and no notion of quiet streets; BRouter gives several distinct
/// candidates per request (`alternativeidx` 0…3).
struct BRouterClient {
    enum Profile: String {
        case trekking, safety, fastbike, shortest
        /// BRouter's own low-traffic profile: it pays a detour to stay off
        /// roads that carry cars, where "safety" only prefers what is safe.
        case lowTraffic = "fastbike-lowtraffic"
        /// „wenig Autos": unser eigenes Profil, „safety" mit geschätztem Lärm
        /// und Verkehr (`Resources/radpendler-quiet.brf`). Liegt nicht auf
        /// dem Server, sondern wird hochgeladen — siehe `CustomProfile`.
        case quiet = "radpendler-quiet"

        var isCustom: Bool { self == .quiet }
    }

    var session: URLSession = .shared
    /// Ob dieselbe Frage aus dem Zwischenspeicher beantwortet werden darf.
    /// Tests schalten es ab, damit sie messen, was sie messen wollen.
    var cached = true

    func route(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
               profile: Profile, alternative: Int = 0) async throws -> StreetRoute {
        // Start und Ziel einer Pendelstrecke ändern sich nicht, und BRouter
        // kennt keine Verkehrslage: dieselbe Frage hat eine Stunde später
        // dieselbe Antwort. Bisher wurden bei **jeder** Neuplanung drei
        // Linien neu über das Netz geholt — von einem öffentlichen Server,
        // der ohnehin drosselt.
        let key = String(format: "%.5f,%.5f|%.5f,%.5f|%@|%d",
                         from.latitude, from.longitude, to.latitude, to.longitude,
                         profile.rawValue, alternative)
        if cached, let hit = await RouteCache.shared.route(for: key) { return hit }
        let route: StreetRoute
        if profile.isCustom {
            // Hochgeladene Profile räumt der Server irgendwann weg. Scheitert
            // die Anfrage mit einer gemerkten Kennung, einmal neu hochladen;
            // scheitert auch das, steht „safety" dafür — lieber die alte
            // Antwort als gar keine „wenig Autos"-Linie.
            do {
                route = try await fetch(from: from, to: to, profile: try await CustomProfile.shared.id(session: session),
                                        alternative: alternative)
            } catch {
                do {
                    let fresh = try await CustomProfile.shared.id(session: session, renew: true)
                    route = try await fetch(from: from, to: to, profile: fresh, alternative: alternative)
                } catch {
                    return try await self.route(from: from, to: to, profile: .safety, alternative: alternative)
                }
            }
        } else {
            route = try await fetch(from: from, to: to, profile: profile.rawValue, alternative: alternative)
        }
        if cached { await RouteCache.shared.keep(route, for: key) }
        return route
    }

    private func fetch(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
                       profile: String, alternative: Int) async throws -> StreetRoute {
        var c = URLComponents(string: "https://brouter.de/brouter")!
        c.queryItems = [
            .init(name: "lonlats", value: String(format: "%.6f,%.6f|%.6f,%.6f",
                                                 from.longitude, from.latitude, to.longitude, to.latitude)),
            .init(name: "profile", value: profile),
            .init(name: "alternativeidx", value: String(alternative)),
            .init(name: "format", value: "geojson"),
        ]
        var request = URLRequest(url: c.url!, timeoutInterval: 20)
        request.setValue("RadPendler iOS (private commute planner)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw BRouterError.server(String(data: data.prefix(200), encoding: .utf8) ?? "HTTP \(http.statusCode)")
        }
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> StreetRoute {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let feature = (root["features"] as? [[String: Any]])?.first,
              let geometry = feature["geometry"] as? [String: Any],
              let coords = geometry["coordinates"] as? [[Double]],
              let props = feature["properties"] as? [String: Any] else { throw BRouterError.malformed }
        let points = Geo.validated(coords.filter { $0.count >= 2 }
            .map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) })
        let length = Double(props["track-length"] as? String ?? "") ?? 0
        let time = Double(props["total-time"] as? String ?? "") ?? 0
        guard points.count > 1 else { throw BRouterError.malformed }
        let roads = Self.roads(props["messages"] as? [[String]], along: coords)
        return StreetRoute(distance: length, expectedTravelTime: time, coordinates: points,
                           mix: roads.mix, roadPoints: roads.points,
                           ascent: Self.ascent(props: props, coordinates: coords))
    }

    /// Der summierte Anstieg. BRouter rechnet ihn selbst aus und nennt ihn
    /// `filtered ascend` — „filtered", weil das Rauschen des Höhenmodells
    /// herausgerechnet ist: ohne das summiert jede Unebenheit der Messung ein
    /// paar Zentimeter, und aus einer flachen Strecke werden hundert
    /// Höhenmeter. Fehlt der Wert, wird er aus den Höhen der Punkte gerechnet
    /// — dieselbe Zahl, nur ungefiltert.
    static func ascent(props: [String: Any], coordinates: [[Double]]) -> Double? {
        if let v = props["filtered ascend"] as? Double { return v }
        if let v = props["filtered ascend"] as? Int { return Double(v) }
        if let s = props["filtered ascend"] as? String, let v = Double(s) { return v }
        return climbed(coordinates)
    }

    /// Alles Bergauf zusammengezählt, aus der dritten Stelle jeder Koordinate.
    /// nil, wenn die Höhen fehlen — eine Strecke ohne Höhen ist nicht flach,
    /// sie ist unbekannt.
    static func climbed(_ coordinates: [[Double]]) -> Double? {
        let heights = coordinates.compactMap { $0.count >= 3 ? $0[2] : nil }
        guard heights.count == coordinates.count, heights.count >= 2 else { return nil }
        return zip(heights, heights.dropFirst()).reduce(0) { $0 + Swift.max(0, $1.1 - $1.0) }
    }

    /// BRouter's per-segment table: one row per stretch, with its length and
    /// the OpenStreetMap tags of the way it runs on. The first row names the
    /// columns, and the names are what is looked up — the order has changed
    /// between BRouter versions before.
    ///
    /// **Eine Zeile ist kein Punkt, sondern eine Strecke.** BRouter fasst eine
    /// Straße zusammen, solange sich ihre Merkmale nicht ändern: der Median
    /// einer Pendelstrecke liegt bei 14 m, das längste Stück der gemessenen
    /// 33-km-Route bei 2 082 m. Legte man nur den einen Punkt jeder Zeile ab,
    /// läge über ein Drittel der gefahrenen Meter weiter als
    /// `RoadPoint.matchRadius` von jedem Stützpunkt entfernt — und die
    /// Aufzeichnung schriebe sie als „sonstiges" gut, obwohl die Straße bekannt
    /// ist. (Auf der Testroute: 38,5 % der Meter.) Deshalb wird jede Zeile
    /// entlang der Linie ausgelegt und alle `RoadPoint.spacing` Meter ein
    /// Stützpunkt gesetzt.
    static func roads(_ messages: [[String]]?,
                      along coordinates: [[Double]] = []) -> (mix: RoadMix, points: [RoadPoint]) {
        guard let messages, let header = messages.first,
              let distanceColumn = header.firstIndex(of: "Distance"),
              let tagColumn = header.firstIndex(of: "WayTags") else { return (RoadMix(), []) }
        let lonColumn = header.firstIndex(of: "Longitude")
        let latColumn = header.firstIndex(of: "Latitude")
        let line = Geo.validated(coordinates.filter { $0.count >= 2 }
            .map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) })
        let cum = TurnGuide.cumulative(line)
        var mix = RoadMix()
        var points: [RoadPoint] = []
        var travelled = 0.0
        for row in messages.dropFirst() {
            guard row.count > max(distanceColumn, tagColumn),
                  let metres = Double(row[distanceColumn]) else { continue }
            let cls = RoadClass.from(wayTags: row[tagColumn])
            mix.add(metres, to: cls)
            let from = travelled
            travelled += metres
            // Die Linie kennen wir: dann wird die Strecke auf ihr ausgelegt.
            if line.count > 1, cum.last ?? 0 > 0 {
                var s = from
                while s < travelled {
                    if let c = Self.point(at: s, on: line, cum: cum) {
                        points.append(RoadPoint(lat: c.latitude, lon: c.longitude, cls: cls))
                    }
                    s += RoadPoint.spacing
                }
                continue
            }
            // Ohne Linie bleibt der eine Punkt der Zeile. Die Koordinaten
            // kommen als ganzzahlige Mikrograd.
            guard let lonColumn, let latColumn, row.count > max(lonColumn, latColumn),
                  let lon = Double(row[lonColumn]), let lat = Double(row[latColumn]) else { continue }
            let c = CLLocationCoordinate2D(latitude: lat / 1_000_000, longitude: lon / 1_000_000)
            guard Geo.valid(c) else { continue }
            points.append(RoadPoint(lat: c.latitude, lon: c.longitude, cls: cls))
        }
        return (mix, points)
    }

    /// Der Punkt `s` Meter vom Anfang der Linie. Linear zwischen den Ecken —
    /// bei Stützpunkten alle paar Meter ist das die Straße selbst.
    static func point(at s: Double, on line: [CLLocationCoordinate2D],
                      cum: [Double]) -> CLLocationCoordinate2D? {
        guard line.count > 1, cum.count == line.count, let total = cum.last, total > 0 else { return line.first }
        let s = Swift.min(Swift.max(s, 0), total)
        var i = (cum.firstIndex { $0 > s } ?? cum.count) - 1
        i = Swift.min(Swift.max(i, 0), line.count - 2)
        let span = cum[i + 1] - cum[i]
        guard span > 0 else { return line[i] }
        let f = (s - cum[i]) / span
        return CLLocationCoordinate2D(latitude: line[i].latitude + (line[i + 1].latitude - line[i].latitude) * f,
                                      longitude: line[i].longitude + (line[i + 1].longitude - line[i].longitude) * f)
    }

    enum BRouterError: LocalizedError {
        case server(String), malformed
        var errorDescription: String? {
            switch self {
            case .server(let s): "BRouter: \(foreignText(s))"
            case .malformed: L("BRouter: unerwartete Antwort")
            }
        }
    }
}

/// Gefahrene Wege, die sich nicht ändern, solange man sie fährt.
///
/// Eine Linie von A nach B ist bei BRouter eine Funktion der beiden Punkte
/// und des Profils — keine Verkehrslage, keine Uhrzeit. Was sie ändern kann,
/// sind die OpenStreetMap-Daten, und die ändern sich nicht in einer Stunde.
actor RouteCache {
    static let shared = RouteCache()

    /// So lange gilt eine Antwort. Danach ist sie nicht falsch, aber es ist
    /// billig genug, sie neu zu holen.
    static let lifetime: TimeInterval = 3600
    /// Und so viele werden behalten: eine Pendelstrecke mit allen Profilen
    /// und beiden Richtungen sind ein Dutzend.
    static let limit = 32

    private var entries: [String: (route: StreetRoute, at: Date)] = [:]

    func route(for key: String) -> StreetRoute? {
        guard let hit = entries[key], Date.now.timeIntervalSince(hit.at) < Self.lifetime else { return nil }
        return hit.route
    }

    func keep(_ route: StreetRoute, for key: String) {
        if entries.count >= Self.limit, let oldest = entries.min(by: { $0.value.at < $1.value.at })?.key {
            entries.removeValue(forKey: oldest)
        }
        entries[key] = (route, .now)
    }

    func forget() { entries.removeAll() }
}

/// Bike legs through BRouter's "safety" profile (bike paths and quiet streets
/// first), falling back to Apple Maps; the car always through Apple Maps.
actor CompositeRouter: StreetRouting {
    private let apple = MapKitRouter()
    private let brouter = BRouterClient()
    private var cache: [String: StreetRoute] = [:]

    func route(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
               mode: StreetMode, departure: Date?) async throws -> StreetRoute {
        guard mode == .bike else { return try await apple.route(from: from, to: to, mode: mode, departure: departure) }
        let key = String(format: "%.5f,%.5f|%.5f,%.5f", from.latitude, from.longitude, to.latitude, to.longitude)
        if let hit = cache[key] { return hit }
        let r: StreetRoute
        do {
            r = try await brouter.route(from: from, to: to, profile: .safety)
        } catch {
            r = try await apple.route(from: from, to: to, mode: .bike, departure: nil)
        }
        cache[key] = r
        return r
    }
}

/// Ein eigenes BRouter-Profil auf dem öffentlichen Server: einmal hochladen
/// (`POST /brouter/profile`), die Kennung („custom_…") merken und bei jeder
/// Anfrage als Profilnamen schicken. Parameter in der Adresse
/// (`profile:consider_noise=true`) beantwortet brouter.de mit 500 — der
/// Umweg über das Hochladen ist der einzige.
///
/// Die Kennung gilt eine halbe Stunde; wie lange der Server sie wirklich
/// hält, sagt er nicht. Dafür gibt es `renew`.
actor CustomProfile {
    static let shared = CustomProfile()
    static let lifetime: TimeInterval = 1800

    private var current: (id: String, at: Date)?

    func id(session: URLSession, renew: Bool = false) async throws -> String {
        if !renew, let c = current, Date.now.timeIntervalSince(c.at) < Self.lifetime { return c.id }
        guard let url = Bundle.main.url(forResource: "radpendler-quiet", withExtension: "brf"),
              let text = try? Data(contentsOf: url) else { throw BRouterClient.BRouterError.malformed }
        var request = URLRequest(url: URL(string: "https://brouter.de/brouter/profile")!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.setValue("RadPendler iOS (private commute planner)", forHTTPHeaderField: "User-Agent")
        request.httpBody = text
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["profileid"] as? String, id.hasPrefix("custom_") else {
            throw BRouterClient.BRouterError.server(String(data: data.prefix(200), encoding: .utf8) ?? "upload")
        }
        current = (id, .now)
        return id
    }
}
