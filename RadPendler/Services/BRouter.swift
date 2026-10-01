import CoreLocation
import Foundation

/// Bike routes from the public BRouter server (brouter.de), which routes on
/// OpenStreetMap with selectable profiles. Apple Maps has exactly one bike
/// route and no notion of quiet streets; BRouter gives several distinct
/// candidates per request (`alternativeidx` 0…3).
struct BRouterClient {
    enum Profile: String, Sendable {
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
    /// Kopfsteinpflaster meiden: jedes Profil geht dann in einer abgewandelten
    /// Fassung als eigenes Profil zum Server (`withoutCobbles`).
    var avoidCobbles = false

    func route(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
               via: [CLLocationCoordinate2D] = [],
               profile: Profile, alternative: Int = 0) async throws -> StreetRoute {
        // Start und Ziel einer Pendelstrecke ändern sich nicht, und BRouter
        // kennt keine Verkehrslage: dieselbe Frage hat eine Stunde später
        // dieselbe Antwort. Bisher wurden bei **jeder** Neuplanung drei
        // Linien neu über das Netz geholt — von einem öffentlichen Server,
        // der ohnehin drosselt.
        let key = String(format: "%.5f,%.5f|%.5f,%.5f|%@|%d%@",
                         from.latitude, from.longitude, to.latitude, to.longitude,
                         profile.rawValue, alternative, avoidCobbles ? "|ohne-pflaster" : "")
            + via.map { String(format: "|über %.5f,%.5f", $0.latitude, $0.longitude) }.joined()
        if cached, let hit = await RouteCache.shared.route(for: key) { return hit }
        let route: StreetRoute
        if profile.isCustom || avoidCobbles {
            // Hochgeladene Profile räumt der Server irgendwann weg. Scheitert
            // die Anfrage mit einer gemerkten Kennung, einmal neu hochladen;
            // scheitert auch das, gilt die Fassung ohne Abwandlung — ohne
            // Pflasterregel, und für „wenig Autos" am Ende „safety". Lieber
            // eine Linie mit Pflaster als gar keine.
            let custom = CustomProfile.Kind(profile: profile, withoutCobbles: avoidCobbles)
            do {
                route = try await fetch(from: from, to: to, via: via,
                                        profile: try await CustomProfile.shared.id(custom, session: session),
                                        alternative: alternative)
            } catch {
                do {
                    let fresh = try await CustomProfile.shared.id(custom, session: session, renew: true)
                    route = try await fetch(from: from, to: to, via: via, profile: fresh, alternative: alternative)
                } catch {
                    var plain = self
                    if avoidCobbles { plain.avoidCobbles = false } else { return try await plain.route(from: from, to: to, via: via, profile: .safety, alternative: alternative) }
                    return try await plain.route(from: from, to: to, via: via, profile: profile, alternative: alternative)
                }
            }
        } else {
            route = try await fetch(from: from, to: to, via: via, profile: profile.rawValue, alternative: alternative)
        }
        if cached { await RouteCache.shared.keep(route, for: key) }
        return route
    }

    private func fetch(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
                       via: [CLLocationCoordinate2D] = [],
                       profile: String, alternative: Int) async throws -> StreetRoute {
        var c = URLComponents(string: "https://brouter.de/brouter")!
        c.queryItems = [
            // Zwischenpunkte stehen einfach dazwischen: BRouter fährt sie der
            // Reihe nach an — so führt ein Fixpunkt die Linie, statt sie nur
            // hinterher auszusortieren.
            .init(name: "lonlats", value: ([from] + via + [to])
                .map { String(format: "%.6f,%.6f", $0.longitude, $0.latitude) }.joined(separator: "|")),
            .init(name: "profile", value: profile),
            .init(name: "alternativeidx", value: String(alternative)),
            .init(name: "format", value: "geojson"),
        ]
        var request = URLRequest(url: c.url!, timeoutInterval: 20)
        request.setValue("RadPendler iOS (private commute planner)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await BRouterGate.shared.limited { try await session.data(for: request) }
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

/// Höchstens drei Anfragen gleichzeitig an brouter.de — für die ganze App,
/// nicht je Aufrufer.
///
/// Auf acht auf einmal antwortet der öffentliche Server mit `403 Please,
/// retry later!`, und zwar für Stunden. Eine Planung fragt aber an mehreren
/// Stellen zugleich: die Radrouten, und daneben die Zubringer von Rad + Bahn
/// an beiden Enden — jede Stelle für sich gedrosselt waren das bis zu
/// dreizehn gleichzeitig. Die Schranke sitzt deshalb dort, wo die Anfrage
/// wirklich hinausgeht, und zählt alle.
actor BRouterGate {
    static let shared = BRouterGate(limit: 3)

    let limit: Int
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    /// Wie viele höchstens gleichzeitig drin waren — nur für den Test.
    private(set) var peak = 0

    init(limit: Int) { self.limit = limit }

    private func enter() async {
        if running < limit {
            running += 1
            peak = Swift.max(peak, running)
            return
        }
        // Der Platz wird beim Verlassen direkt weitergereicht; `running`
        // bleibt dabei stehen.
        await withCheckedContinuation { waiting.append($0) }
    }

    private func leave() {
        if waiting.isEmpty { running -= 1 } else { waiting.removeFirst().resume() }
    }

    nonisolated func limited<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        await enter()
        do {
            let result = try await work()
            await leave()
            return result
        } catch {
            await leave()
            throw error
        }
    }
}

/// Bike legs through BRouter's "safety" profile (bike paths and quiet streets
/// first), falling back to Apple Maps; the car always through Apple Maps.
///
/// Kein eigener Zwischenspeicher: BRouters und Apples Antworten hält
/// `RouteCache` (eine Stunde, gedeckelt). Bis 1.9.1 stand hier ein dritter,
/// ohne Ablauf — und weil er auch die Ersatzlinie von Apple behielt, blieb
/// ein einziger Aussetzer von BRouter bis zum Neustart stehen.
actor CompositeRouter: StreetRouting {
    private let apple = MapKitRouter()
    private let brouter = BRouterClient()

    func route(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
               mode: StreetMode, departure: Date?) async throws -> StreetRoute {
        guard mode == .bike else { return try await apple.route(from: from, to: to, mode: mode, departure: departure) }
        return try await bikeRoute(from: from, to: to)
    }

    func feeder(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
                avoidCobbles: Bool) async throws -> StreetRoute {
        try await bikeRoute(from: from, to: to, avoidCobbles: avoidCobbles)
    }

    /// Mit dem Profil der Linie, die gefahren wird, und der Pflasterregel —
    /// eine Neuplanung, die „safety" fragt, schickt jemanden, der die
    /// schnellste Linie fährt, in die Nebenstraßen, und er ist gleich wieder
    /// daneben (Fahrt 30.09.2026).
    func bikeRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
                   via: [CLLocationCoordinate2D] = [],
                   profile: BRouterClient.Profile = .safety,
                   avoidCobbles: Bool = false) async throws -> StreetRoute {
        var brouter = brouter
        brouter.avoidCobbles = avoidCobbles
        do {
            return try await brouter.route(from: from, to: to, via: via, profile: profile)
        } catch {
            return try await apple.route(from: from, to: to, mode: .bike, departure: nil)
        }
    }
}

/// Eigene BRouter-Profile auf dem öffentlichen Server: einmal hochladen
/// (`POST /brouter/profile`), die Kennung („custom_…") merken und bei jeder
/// Anfrage als Profilnamen schicken. Parameter in der Adresse
/// (`profile:consider_noise=true`) beantwortet brouter.de mit 500 — der
/// Umweg über das Hochladen ist der einzige.
///
/// Zwei Gründe für ein eigenes Profil: „wenig Autos" (`radpendler-quiet.brf`)
/// und „Kopfsteinpflaster meiden" — dafür liegt jedes Serverprofil als
/// `brouter-<name>.brf` im Paket und wird mit `withoutCobbles` abgewandelt.
///
/// Wie lange der Server eine Kennung hält, sagt er nicht. Dafür gibt es `renew`.
actor CustomProfile {
    static let shared = CustomProfile()
    /// Sechs Stunden: jedes Hochladen ist eine Anfrage mehr an einen Server,
    /// der bei zu vielen auf einmal mit 403 antwortet — und seit „ohne
    /// Pflaster" sind es bis zu fünf Profile. Hat er eins vorher weggeräumt,
    /// scheitert die Anfrage, und `renew` lädt neu.
    static let lifetime: TimeInterval = 6 * 3600

    struct Kind: Hashable {
        var profile: BRouterClient.Profile
        var withoutCobbles: Bool

        var resource: String {
            profile.isCustom ? profile.rawValue : "brouter-\(profile.rawValue)"
        }
    }

    private var current: [Kind: (id: String, at: Date)] = [:]

    func id(_ kind: Kind, session: URLSession, renew: Bool = false) async throws -> String {
        if !renew, let c = current[kind], Date.now.timeIntervalSince(c.at) < Self.lifetime { return c.id }
        guard let url = Bundle.main.url(forResource: kind.resource, withExtension: "brf"),
              var text = try? String(contentsOf: url, encoding: .utf8) else { throw BRouterClient.BRouterError.malformed }
        if kind.withoutCobbles { text = Self.withoutCobbles(text) }
        var request = URLRequest(url: URL(string: "https://brouter.de/brouter/profile")!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.setValue("RadPendler iOS (private commute planner)", forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(text.utf8)
        let (data, response) = try await BRouterGate.shared.limited { try await session.data(for: request) }
        // Ein Profil mit Fehler bekommt trotzdem eine Kennung — und jede
        // Anfrage damit endet in 500. Das Feld `error` sagt es vorher.
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["error"] == nil,
              let id = json["profileid"] as? String, id.hasPrefix("custom_") else {
            throw BRouterClient.BRouterError.server(String(data: data.prefix(200), encoding: .utf8) ?? "upload")
        }
        current[kind] = (id, .now)
        return id
    }

    /// Kopfsteinpflaster kostet das Sechsfache: die Zeile `assign costfactor`
    /// des Profils wird zu `costfactor_base`, und vor dem Knotenteil kommt
    /// eine neue, die fünf auf Pflaster aufschlägt. Kein Ausschluss — liegt
    /// die Haustür an einer Pflasterstraße, muss man trotzdem hinkommen.
    /// Probe 27.09.2026, Teststrecke: 0,8–1,25 km Pflaster je
    /// Profil wurden höchstens 62 m, für höchstens 0,6 km Umweg.
    /// `unhewn_cobblestone` kennt BRouters Wertetabelle nicht (Profilfehler).
    nonisolated static func withoutCobbles(_ text: String) -> String {
        var out: [String] = []
        for line in text.components(separatedBy: "\n") {
            if line.range(of: #"^assign\s+costfactor\s*$"#, options: .regularExpression) != nil {
                out.append("assign costfactor_base")
                continue
            }
            if line.hasPrefix("---context:node") {
                out += ["# RadPendler: Kopfsteinpflaster meiden",
                        "assign costfactor",
                        "  add costfactor_base",
                        "      switch surface=sett|cobblestone 5 0", ""]
            }
            out.append(line)
        }
        return out.joined(separator: "\n")
    }
}
