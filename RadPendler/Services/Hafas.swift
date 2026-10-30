import CoreLocation
import Foundation

/// Der Zugang zur VBB-API: eine Access-ID, die der VBB auf Antrag vergibt.
///
/// Sie steht in `Secrets.xcconfig` (lokal, nicht im Repository) und kommt über
/// `Config.xcconfig` und die Info.plist ins Paket. Wer das Projekt ohne sie
/// baut, bekommt eine App ohne VBB: dann beantwortet Transitous auch Berlin
/// und Brandenburg (`TimetableSource.resolved`).
enum VbbAccess {
    static var id: String? {
        let raw = (Bundle.main.infoDictionary?["VBBAccessID"] as? String ?? "")
            .trimmingCharacters(in: .whitespaces)
        return raw.isEmpty || raw.hasPrefix("$(") ? nil : raw
    }
}

/// Client for the VBB's official HAFAS ReST API.
///
/// Used with the VBB's consent (08.10.2026) and an access id of our own. Until
/// 1.19 the app spoke to the "mgate" endpoint of the VBB web app instead, with
/// the client block of the open-source `hafas-client` profile — that was never
/// a published interface, and it is gone from here.
struct HafasClient {
    var endpoint = HafasClient.endpoint(on: .now)
    var accessID: String? = VbbAccess.id
    var session: URLSession = .shared

    var isConfigured: Bool { accessID != nil }

    /// Am 30.11.2026 stellt der VBB auf die mastscharfe Auskunft um und zieht
    /// auf neue Server (`vbb.hafas.cloud`). Der neue steht schon, aber mit
    /// unvollständiger Echtzeit; der alte geht danach aus. Eine Fassung, die
    /// heute hinausgeht, muss an diesem Tag von selbst wechseln.
    static let legacyEndpoint = URL(string: "https://fahrinfo.vbb.de/restproxy/latest")!
    static let cloudEndpoint = URL(string: "https://vbb.hafas.cloud/api/fahrinfo/latest")!
    static let switchover = Date(timeIntervalSince1970: 1_795_993_200)   // 30.11.2026 00:00 Berlin (MEZ)

    static func endpoint(on date: Date) -> URL {
        date < switchover ? legacyEndpoint : cloudEndpoint
    }

    enum Location {
        case station(lid: String)
        case address(name: String, coordinate: CLLocationCoordinate2D)

        /// `origin…` or `dest…`, as the trip search names its two ends.
        ///
        /// Ohne `…CoordName`: das neue System findet mit Namen keine einzige
        /// Verbindung (`SVC_NO_RESULT`, geprüft 30.10.2026), das alte braucht
        /// ihn nicht. Den Namen setzt `named` hinterher wieder ein.
        func query(_ end: String) -> [URLQueryItem] {
            switch self {
            case .station(let lid):
                return [URLQueryItem(name: "\(end)Id", value: lid)]
            case .address(_, let c):
                return [URLQueryItem(name: "\(end)CoordLat", value: String(format: "%.6f", c.latitude)),
                        URLQueryItem(name: "\(end)CoordLong", value: String(format: "%.6f", c.longitude))]
            }
        }

        var addressName: String? {
            if case .address(let name, _) = self { name } else { nil }
        }
    }

    struct Station: Equatable {
        var name: String
        var lid: String
        var coordinate: CLLocationCoordinate2D
        var distance: Double
        var productMask: Int

        static func == (a: Station, b: Station) -> Bool { a.lid == b.lid }

        var hasBikeCompartment: Bool { productMask & TransitProduct.bikeCompartmentMask != 0 }
    }

    enum HafasError: LocalizedError {
        case server(code: String, text: String)
        /// No access id in this build, or the VBB refuses the one it has
        /// (`API_AUTH`, `API_QUOTA`). The planner answers with Transitous then.
        case denied
        case malformed

        var errorDescription: String? {
            switch self {
            case .server(let code, let text): "VBB-Auskunft: \(foreignText(text)) (\(code))"
            case .denied: L("VBB-Auskunft: Zugang abgelehnt")
            case .malformed: L("VBB-Auskunft: unerwartete Antwort")
            }
        }
    }

    // MARK: Requests

    /// Rail stations within `radius` metres, nearest first, one entry per station
    /// (HAFAS lists "S+U Berlin Hauptbahnhof" and its "[Gleis 1-8]" part separately).
    ///
    /// Aus `StationCache`, solange dieselbe Frage keinen Tag alt ist: die
    /// Bahnhöfe um die eigene Haustür ändern sich nicht zwischen zwei
    /// Planungen, und Rad + Bahn fragt bei jeder vier Mal danach.
    func nearbyStations(around c: CLLocationCoordinate2D, radius: Double,
                        productMask: Int = TransitProduct.bikeStationMask) async throws -> [Station] {
        let key = StationCache.key(c, radius: radius, productMask: productMask)
        if let hit = await StationCache.shared.stations(for: key) { return hit }
        let found = try await askNearbyStations(around: c, radius: radius, productMask: productMask)
        // Eine leere Antwort kann ein Aussetzer sein; einen Tag lang „kein
        // Bahnhof" wäre zu teuer für eine Anfrage, die man sich sparen wollte.
        if !found.isEmpty { await StationCache.shared.keep(found, for: key) }
        return found
    }

    private func askNearbyStations(around c: CLLocationCoordinate2D, radius: Double,
                                   productMask: Int) async throws -> [Station] {
        let res = try await call("location.nearbystops", [
            URLQueryItem(name: "originCoordLat", value: String(format: "%.6f", c.latitude)),
            URLQueryItem(name: "originCoordLong", value: String(format: "%.6f", c.longitude)),
            URLQueryItem(name: "r", value: String(Int(radius))),
            URLQueryItem(name: "maxNo", value: "20"),
            URLQueryItem(name: "type", value: "S"),
            URLQueryItem(name: "products", value: String(productMask)),
        ])
        return HafasParser.stations(res, productMask: productMask)
    }

    /// Connections departing at or after `date`. With `bikeCarriage`, HAFAS only
    /// returns trains that take bikes; the parser still checks every leg.
    func journeys(from: Location, to: Location, departing date: Date, arriveBy: Bool = false,
                  bikeCarriage: Bool, productMask: Int = TransitProduct.allMask,
                  results: Int = 4) async throws -> [[Leg]] {
        let (day, time) = HafasTime.format(date)
        var query = from.query("origin") + to.query("dest") + [
            URLQueryItem(name: "date", value: day),
            URLQueryItem(name: "time", value: time),
            URLQueryItem(name: "numF", value: String(results)),
            URLQueryItem(name: "products", value: String(productMask)),
            // Die Linie als Google-Polyline; ohne `polyEnc` käme sie als
            // Zahlenliste in einem anderen Feld.
            URLQueryItem(name: "poly", value: "1"),
            URLQueryItem(name: "polyEnc", value: "GPA"),
            URLQueryItem(name: "passlist", value: "0"),
        ]
        if arriveBy { query.append(URLQueryItem(name: "searchForArrival", value: "1")) }
        if bikeCarriage { query.append(URLQueryItem(name: "bikeCarriage", value: "1")) }
        do {
            return HafasParser.journeys(try await call("trip", query))
                .map { HafasParser.named($0, from: from.addressName, to: to.addressName) }
        } catch HafasError.server(let code, _) where HafasParser.emptyCodes.contains(code) {
            return []   // "no connection found" / "departure = arrival"
        }
    }

    // MARK: Transport

    /// The access id travels in the `Authorization` header, not as `accessId`
    /// in the query: a URL ends up in error objects and logs, a header does not.
    private func call(_ service: String, _ query: [URLQueryItem]) async throws -> [String: Any] {
        guard let accessID else { throw HafasError.denied }
        let url = endpoint.appending(path: service).appending(queryItems: query + [
            URLQueryItem(name: "lang", value: "de"), URLQueryItem(name: "format", value: "json"),
        ])
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Bearer \(accessID)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppIdentity.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await session.data(for: request)
        return try HafasParser.answer(data)
    }
}

/// Die Bahnhöfe um einen Punkt, einen Tag lang.
///
/// Der Schlüssel rundet auf vier Stellen (gut 10 m): „hier" aus der Ortung
/// liegt jedes Mal ein paar Meter anders, und die Entfernungen in der Antwort
/// sind auf diese Meter ohnehin egal — sie ordnen nur.
actor StationCache {
    static let shared = StationCache()
    static let lifetime: TimeInterval = 24 * 3600
    /// Start und Ziel je mit S/RE und Tram, in beiden Richtungen und für ein
    /// paar Strecken — mehr hält niemand im Kopf.
    static let limit = 24

    private var entries: [String: (stations: [HafasClient.Station], at: Date)] = [:]

    static func key(_ c: CLLocationCoordinate2D, radius: Double, productMask: Int) -> String {
        String(format: "%.4f,%.4f|%d|%d", c.latitude, c.longitude, Int(radius), productMask)
    }

    func stations(for key: String) -> [HafasClient.Station]? {
        guard let hit = entries[key], Date.now.timeIntervalSince(hit.at) < Self.lifetime else { return nil }
        return hit.stations
    }

    func keep(_ stations: [HafasClient.Station], for key: String) {
        if entries[key] == nil, entries.count >= Self.limit,
           let oldest = entries.min(by: { $0.value.at < $1.value.at })?.key {
            entries.removeValue(forKey: oldest)
        }
        entries[key] = (stations, .now)
    }

    func clear() { entries.removeAll() }
}

/// HAFAS clock strings: "2026-09-21" and "17:15:00". Times are local
/// (Europe/Berlin); a stop past midnight carries its own date.
enum HafasTime {
    static let zone = TimeZone(identifier: "Europe/Berlin")!

    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        return c
    }

    static func format(_ date: Date) -> (day: String, time: String) {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return (String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0),
                String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0))
    }

    static func date(day: String, time: String) -> Date? {
        let d = day.split(separator: "-").compactMap { Int($0) }
        let t = time.split(separator: ":").compactMap { Int($0) }
        guard d.count == 3, t.count >= 2 else { return nil }
        return calendar.date(from: DateComponents(year: d[0], month: d[1], day: d[2],
                                                  hour: t[0], minute: t[1], second: t.count > 2 ? t[2] : 0))
    }
}

/// Google encoded-polyline decoding; HAFAS sends `crdEncYX` in this format.
enum Polyline {
    static func decode(_ s: String, precision: Double = 1e5) -> [CLLocationCoordinate2D] {
        var coords: [CLLocationCoordinate2D] = []
        let bytes = Array(s.utf8)
        var i = 0, lat = 0, lon = 0
        // The shift is bounded: a crafted run of continuation bytes would
        // otherwise drive the accumulator past `Int` and trap on the next
        // addition. An overlong group is not a number, it is an answer to drop.
        func next() -> Int? {
            var result = 0, shift = 0
            while i < bytes.count, shift < Geo.maxPolylineShift {
                let b = Int(bytes[i]) - 63
                i += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20 { return (result & 1) != 0 ? ~(result >> 1) : (result >> 1) }
            }
            return nil
        }
        while i < bytes.count, coords.count < Geo.maxPoints {
            guard let dLat = next(), let dLon = next() else { break }
            lat += dLat
            lon += dLon
            coords.append(CLLocationCoordinate2D(latitude: Double(lat) / precision,
                                                 longitude: Double(lon) / precision))
        }
        return Geo.validated(coords)
    }
}

/// Turns the ReST answers into the app's model. Pure functions, tested against
/// responses captured in RadPendlerTests/Fixtures.
enum HafasParser {
    /// "No connection found" and "start equals destination": an empty list,
    /// not an error anyone needs to read.
    static let emptyCodes: Set<String> = ["SVC_NO_RESULT", "SVC_LOC_EQUAL"]
    private static let deniedCodes: Set<String> = ["API_AUTH", "API_QUOTA"]

    /// The JSON object of an answer. An error arrives as an object with
    /// `errorCode` — sometimes with HTTP 400, sometimes with 200.
    static func answer(_ data: Data) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HafasClient.HafasError.malformed
        }
        if let code = root["errorCode"] as? String {
            if deniedCodes.contains(code) { throw HafasClient.HafasError.denied }
            let text = root["internalErrorTextOut"] as? String ?? root["errorText"] as? String ?? code
            throw HafasClient.HafasError.server(code: code, text: text)
        }
        return root
    }

    /// Seit der mastscharfen Auskunft kommt jeder Bahnsteig und jeder Mast als
    /// eigener Halt (`3…`); der Haltestellenbereich (`9…`), nach dem der Planer
    /// fragt und vergleicht, steht dann in `mainMastExtId`, sein Mittelpunkt in
    /// `mainMastLat`/`-Lon`.
    static func stations(_ res: [String: Any], productMask: Int) -> [Station] {
        var names = Set<String>(), areas = Set<String>()
        var out: [Station] = []
        for entry in res["stopLocationOrCoordLocation"] as? [[String: Any]] ?? [] {
            guard let l = entry["StopLocation"] as? [String: Any],
                  let name = l["name"] as? String,
                  let lid = l["mainMastExtId"] as? String ?? l["extId"] as? String ?? l["id"] as? String,
                  let c = mainMastCoordinate(l) ?? coordinate(l) else { continue }
            let mask = l["products"] as? Int ?? 0
            guard mask & productMask != 0 else { continue }
            let base = baseName(name)
            guard names.insert(base).inserted, areas.insert(lid).inserted else { continue }
            out.append(Station(name: name, lid: lid, coordinate: c,
                               distance: l["dist"] as? Double ?? 0, productMask: mask))
        }
        return out.sorted { $0.distance < $1.distance }
    }

    typealias Station = HafasClient.Station

    /// "S+U Berlin Hauptbahnhof [Gleis 1-8]" → "S+U Berlin Hauptbahnhof"
    static func baseName(_ name: String) -> String {
        name.components(separatedBy: " [").first ?? name
    }

    static func journeys(_ res: [String: Any]) -> [[Leg]] {
        (res["Trip"] as? [[String: Any]] ?? []).compactMap(journey)
    }

    /// Ohne `…CoordName` heißt eine Adresse in der Antwort „52.521000,
    /// 13.413000"; vorn und hinten steht wieder ihr Name.
    static func named(_ legs: [Leg], from: String?, to: String?) -> [Leg] {
        var legs = legs
        if let from, !legs.isEmpty { legs[0].fromName = from }
        if let to, !legs.isEmpty { legs[legs.count - 1].toName = to }
        return legs
    }

    private static func coordinate(_ stop: [String: Any]) -> CLLocationCoordinate2D? {
        guard let lat = stop["lat"] as? Double, let lon = stop["lon"] as? Double else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private static func mainMastCoordinate(_ stop: [String: Any]) -> CLLocationCoordinate2D? {
        guard let lat = stop["mainMastLat"] as? Double, let lon = stop["mainMastLon"] as? Double else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Fahrplanzeit und, wenn es eine gibt, die Prognose eines Halts.
    private static func times(_ stop: [String: Any]) -> (planned: Date?, real: Date?) {
        let day = stop["date"] as? String ?? ""
        let planned = HafasTime.date(day: day, time: stop["time"] as? String ?? "")
        let real = (stop["rtTime"] as? String).flatMap {
            HafasTime.date(day: stop["rtDate"] as? String ?? day, time: $0)
        }
        return (planned, real)
    }

    private static func notes(_ holder: [String: Any]) -> [[String: Any]] {
        (holder["Notes"] as? [String: Any])?["Note"] as? [[String: Any]] ?? []
    }

    private static func polyline(_ sec: [String: Any]) -> [CLLocationCoordinate2D] {
        let parts = (sec["PolylineGroup"] as? [String: Any])?["polylineDesc"] as? [[String: Any]] ?? []
        return parts.flatMap { ($0["crdEncYX"] as? String).map { Polyline.decode($0) } ?? [] }
    }

    private static func journey(_ trip: [String: Any]) -> [Leg]? {
        guard let secs = (trip["LegList"] as? [String: Any])?["Leg"] as? [[String: Any]] else { return nil }
        var legs: [Leg] = []
        for sec in secs {
            guard let dep = sec["Origin"] as? [String: Any], let arr = sec["Destination"] as? [String: Any] else { continue }
            let depTimes = times(dep), arrTimes = times(arr)
            guard let pDep = depTimes.planned, let pArr = arrTimes.planned else { continue }
            let from = dep["name"] as? String ?? "?", to = arr["name"] as? String ?? "?"
            let ends = [coordinate(dep), coordinate(arr)].compactMap { $0 }

            switch sec["type"] as? String {
            case "JNY":
                // Ein Eintrag je Abschnitt der Fahrt; ältere Fassungen der
                // Schnittstelle schicken das Objekt ohne Liste.
                let prod = (sec["Product"] as? [[String: Any]])?.first ?? sec["Product"] as? [String: Any] ?? [:]
                let line = (prod["name"] as? String ?? sec["name"] as? String ?? "?")
                    .trimmingCharacters(in: .whitespaces)
                let cls = (prod["cls"] as? String).flatMap { Int($0) } ?? prod["cls"] as? Int
                    ?? TransitProduct.unknown.rawValue
                let poly = polyline(sec)
                legs.append(Leg(
                    kind: .transit(line: line, product: TransitProduct(cls: cls)),
                    fromName: from, toName: to,
                    departure: depTimes.real ?? pDep, arrival: arrTimes.real ?? pArr,
                    plannedDeparture: pDep, plannedArrival: pArr,
                    coordinates: poly.isEmpty ? ends : poly,
                    departurePlatform: platform(dep), arrivalPlatform: platform(arr),
                    direction: sec["direction"] as? String,
                    bikeCarriage: bikeCarriage(notes(sec)) ? .yes : .unknown,
                    cancelled: [sec, dep, arr].contains { $0["cancelled"] as? Bool ?? false }))
            default:   // WALK, TRSF (transfer inside a station), DEVI
                if from == to && pDep == pArr { continue }
                legs.append(Leg(kind: .walk, fromName: from, toName: to,
                                departure: depTimes.real ?? pDep, arrival: arrTimes.real ?? pArr,
                                distance: sec["dist"] as? Double,
                                coordinates: ends))
            }
        }
        return legs.contains(where: \.isTransit) ? legs : nil
    }

    private static func platform(_ stop: [String: Any]) -> String? {
        (stop["rtPlatform"] as? [String: Any])?["text"] as? String
            ?? (stop["platform"] as? [String: Any])?["text"] as? String
            ?? stop["rtTrack"] as? String ?? stop["track"] as? String
    }

    /// A leg carries bikes if HAFAS attaches the "FK" note ("Fahrradmitnahme
    /// möglich") and nothing on the leg says the opposite.
    static func bikeCarriage(_ notes: [[String: Any]]) -> Bool {
        let texts = notes.map { (($0["txtN"] as? String) ?? ($0["value"] as? String) ?? "").lowercased() }
        if texts.contains(where: { $0.contains("keine fahrradmitnahme") || $0.contains("fahrradmitnahme nicht") }) {
            return false
        }
        return notes.contains { ($0["key"] as? String) == "FK" }
            || texts.contains { $0.contains("fahrradmitnahme möglich") || $0.contains("fahrradmitnahme begrenzt") }
    }
}
