import CoreLocation
import Foundation

/// Client for the VBB HAFAS "mgate" endpoint that the VBB web app uses.
///
/// This is not a published API: the client/auth block below is the one the
/// open-source `hafas-client` VBB profile sends. The public wrapper
/// v6.vbb.transport.rest answered 503 during the Phase-0 probe (2026-09-19),
/// the endpoint itself answered in ~0.2 s. If VBB ever rotates the AID, the
/// official route is an access key from VBB for their HAFAS ReST API.
struct HafasClient {
    var endpoint = URL(string: "https://fahrinfo.vbb.de/bin/mgate.exe")!
    var session: URLSession = .shared

    enum Location {
        case station(lid: String)
        case address(name: String, coordinate: CLLocationCoordinate2D)

        var json: [String: Any] {
            switch self {
            case .station(let lid):
                return ["lid": lid]
            case .address(let name, let c):
                return ["type": "A", "name": name, "crd": HafasCoord.encode(c)]
            }
        }
    }

    struct Station: Equatable {
        var name: String
        var lid: String
        var coordinate: CLLocationCoordinate2D
        var distance: Double
        var productMask: Int

        static func == (a: Station, b: Station) -> Bool { a.lid == b.lid }
    }

    enum HafasError: LocalizedError {
        case server(code: String, text: String)
        case malformed

        var errorDescription: String? {
            switch self {
            case .server(let code, let text): "VBB-Auskunft: \(text) (\(code))"
            case .malformed: "VBB-Auskunft: unerwartete Antwort"
            }
        }
    }

    // MARK: Requests

    /// Rail stations within `radius` metres, nearest first, one entry per station
    /// (HAFAS lists "S+U Berlin Hauptbahnhof" and its "[Gleis 1-8]" part separately).
    func nearbyStations(around c: CLLocationCoordinate2D, radius: Double,
                        productMask: Int = TransitProduct.bikeStationMask) async throws -> [Station] {
        let req: [String: Any] = [
            "ring": ["cCrd": HafasCoord.encode(c), "maxDist": Int(radius)],
            "getPOIs": false, "getStops": true, "maxLoc": 20,
            "locFltrL": [["type": "PROD", "mode": "INC", "value": String(productMask)]],
        ]
        let res = try await call("LocGeoPos", req)
        return HafasParser.stations(res, productMask: productMask)
    }

    /// Connections departing at or after `date`. With `bikeCarriage`, HAFAS only
    /// returns trains that take bikes; the parser still checks every leg.
    func journeys(from: Location, to: Location, departing date: Date,
                  bikeCarriage: Bool, productMask: Int = TransitProduct.allMask,
                  results: Int = 4) async throws -> [[Leg]] {
        var filters: [[String: Any]] = [["type": "PROD", "mode": "INC", "value": String(productMask)]]
        if bikeCarriage { filters.append(["type": "BC", "mode": "INC", "value": "1"]) }
        let (day, time) = HafasTime.format(date)
        let req: [String: Any] = [
            "depLocL": [from.json], "arrLocL": [to.json],
            "outDate": day, "outTime": time, "outFrwd": true,
            "numF": results, "getPolyline": true, "getPasslist": false,
            "jnyFltrL": filters,
        ]
        do {
            let res = try await call("TripSearch", req)
            return try HafasParser.journeys(res)
        } catch HafasError.server(let code, _) where code == "H890" || code == "H9380" {
            return []   // "no connection found" / "departure = arrival"
        }
    }

    // MARK: Transport

    private func call(_ method: String, _ req: [String: Any]) async throws -> [String: Any] {
        let body: [String: Any] = [
            "lang": "de",
            "client": ["type": "WEB", "id": "VBB", "name": "VBB WebApp", "l": "vs_webapp_vbb"],
            "ext": "VBB.1", "ver": "1.45",
            "auth": ["type": "AID", "aid": "hafas-vbb-webapp"],
            "svcReqL": [["meth": method, "req": req]],
        ]
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: request)
        return try HafasParser.serviceResult(data)
    }
}

/// HAFAS integer micro-degrees.
enum HafasCoord {
    static func encode(_ c: CLLocationCoordinate2D) -> [String: Int] {
        ["x": Int((c.longitude * 1_000_000).rounded()), "y": Int((c.latitude * 1_000_000).rounded())]
    }

    static func decode(_ crd: Any?) -> CLLocationCoordinate2D? {
        guard let d = crd as? [String: Any], let x = d["x"] as? Int, let y = d["y"] as? Int else { return nil }
        return CLLocationCoordinate2D(latitude: Double(y) / 1_000_000, longitude: Double(x) / 1_000_000)
    }
}

/// HAFAS clock strings. Times are local (Europe/Berlin); a leg past midnight
/// carries a day offset in front: "01002500" = 00:25 on the following day.
enum HafasTime {
    static let zone = TimeZone(identifier: "Europe/Berlin")!

    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        return c
    }

    static func format(_ date: Date) -> (day: String, time: String) {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return (String(format: "%04d%02d%02d", c.year!, c.month!, c.day!),
                String(format: "%02d%02d%02d", c.hour!, c.minute!, c.second!))
    }

    static func date(day: String, time: String) -> Date? {
        guard day.count == 8, time.count >= 6, let y = Int(day.prefix(4)),
              let m = Int(day.dropFirst(4).prefix(2)), let d = Int(day.suffix(2)) else { return nil }
        let t = Array(time)
        let offsetDays = t.count > 6 ? Int(String(t[0..<(t.count - 6)])) ?? 0 : 0
        let hms = t.suffix(6)
        guard let hh = Int(String(hms.prefix(2))), let mm = Int(String(hms.dropFirst(2).prefix(2))),
              let ss = Int(String(hms.suffix(2))) else { return nil }
        let base = calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hh, minute: mm, second: ss))
        return base.flatMap { calendar.date(byAdding: .day, value: offsetDays, to: $0) }
    }
}

/// Google encoded-polyline decoding; HAFAS sends `crdEncYX` in this format.
enum Polyline {
    static func decode(_ s: String, precision: Double = 1e5) -> [CLLocationCoordinate2D] {
        var coords: [CLLocationCoordinate2D] = []
        let bytes = Array(s.utf8)
        var i = 0, lat = 0, lon = 0
        func next() -> Int? {
            var result = 0, shift = 0
            while i < bytes.count {
                let b = Int(bytes[i]) - 63
                i += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20 { return (result & 1) != 0 ? ~(result >> 1) : (result >> 1) }
            }
            return nil
        }
        while i < bytes.count {
            guard let dLat = next(), let dLon = next() else { break }
            lat += dLat
            lon += dLon
            coords.append(CLLocationCoordinate2D(latitude: Double(lat) / precision,
                                                 longitude: Double(lon) / precision))
        }
        return coords
    }
}

/// Turns mgate JSON into the app's model. Pure functions, tested against
/// responses captured in PendelTests/Fixtures.
enum HafasParser {
    static func serviceResult(_ data: Data) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HafasClient.HafasError.malformed
        }
        if let err = root["err"] as? String, err != "OK" {
            throw HafasClient.HafasError.server(code: err, text: root["errTxt"] as? String ?? err)
        }
        guard let svc = (root["svcResL"] as? [[String: Any]])?.first else {
            throw HafasClient.HafasError.malformed
        }
        if let err = svc["err"] as? String, err != "OK" {
            let text = svc["errTxtOut"] as? String ?? svc["errTxt"] as? String ?? err
            throw HafasClient.HafasError.server(code: err, text: text)
        }
        guard let res = svc["res"] as? [String: Any] else { throw HafasClient.HafasError.malformed }
        return res
    }

    static func stations(_ res: [String: Any], productMask: Int) -> [Station] {
        var seen = Set<String>()
        var out: [Station] = []
        for l in res["locL"] as? [[String: Any]] ?? [] {
            guard let name = l["name"] as? String, let lid = l["lid"] as? String,
                  let c = HafasCoord.decode(l["crd"]) else { continue }
            let mask = l["pCls"] as? Int ?? 0
            guard mask & productMask != 0 else { continue }
            let base = baseName(name)
            guard seen.insert(base).inserted else { continue }
            out.append(Station(name: name, lid: lid, coordinate: c,
                               distance: Double(l["dist"] as? Int ?? 0), productMask: mask))
        }
        return out.sorted { $0.distance < $1.distance }
    }

    typealias Station = HafasClient.Station

    /// "S+U Berlin Hauptbahnhof [Gleis 1-8]" → "S+U Berlin Hauptbahnhof"
    static func baseName(_ name: String) -> String {
        name.components(separatedBy: " [").first ?? name
    }

    static func journeys(_ res: [String: Any]) throws -> [[Leg]] {
        guard let cons = res["outConL"] as? [[String: Any]] else { return [] }
        let common = res["common"] as? [String: Any] ?? [:]
        let ctx = Context(common)
        return cons.compactMap { journey($0, ctx) }
    }

    private struct Context {
        let locs: [[String: Any]]
        let prods: [[String: Any]]
        let rems: [[String: Any]]
        let polys: [[String: Any]]

        init(_ common: [String: Any]) {
            locs = common["locL"] as? [[String: Any]] ?? []
            prods = common["prodL"] as? [[String: Any]] ?? []
            rems = common["remL"] as? [[String: Any]] ?? []
            polys = common["polyL"] as? [[String: Any]] ?? []
        }

        func loc(_ x: Any?) -> [String: Any] {
            guard let i = x as? Int, locs.indices.contains(i) else { return [:] }
            return locs[i]
        }

        func name(_ x: Any?) -> String { loc(x)["name"] as? String ?? "?" }
        func coord(_ x: Any?) -> CLLocationCoordinate2D? { HafasCoord.decode(loc(x)["crd"]) }

        func remarks(_ msgL: Any?) -> [[String: Any]] {
            (msgL as? [[String: Any]] ?? []).compactMap { m in
                guard let i = m["remX"] as? Int, rems.indices.contains(i) else { return nil }
                return rems[i]
            }
        }

        func polyline(_ jny: [String: Any]) -> [CLLocationCoordinate2D] {
            guard let g = jny["polyG"] as? [String: Any], let xs = g["polyXL"] as? [Int] else { return [] }
            return xs.flatMap { i -> [CLLocationCoordinate2D] in
                guard polys.indices.contains(i), let enc = polys[i]["crdEncYX"] as? String else { return [] }
                return Polyline.decode(enc)
            }
        }
    }

    private static func journey(_ con: [String: Any], _ ctx: Context) -> [Leg]? {
        guard let day = con["date"] as? String, let secs = con["secL"] as? [[String: Any]] else { return nil }
        var legs: [Leg] = []
        for sec in secs {
            guard let dep = sec["dep"] as? [String: Any], let arr = sec["arr"] as? [String: Any] else { continue }
            let planned = (HafasTime.date(day: day, time: dep["dTimeS"] as? String ?? ""),
                           HafasTime.date(day: day, time: arr["aTimeS"] as? String ?? ""))
            let real = ((dep["dTimeR"] as? String).flatMap { HafasTime.date(day: day, time: $0) },
                        (arr["aTimeR"] as? String).flatMap { HafasTime.date(day: day, time: $0) })
            guard let pDep = planned.0, let pArr = planned.1 else { continue }
            let from = ctx.name(dep["locX"]), to = ctx.name(arr["locX"])
            let ends = [ctx.coord(dep["locX"]), ctx.coord(arr["locX"])].compactMap { $0 }

            switch sec["type"] as? String {
            case "JNY":
                guard let jny = sec["jny"] as? [String: Any] else { continue }
                let prodIndex = jny["prodX"] as? Int ?? -1
                let prod = ctx.prods.indices.contains(prodIndex) ? ctx.prods[prodIndex] : [:]
                let line = (prod["name"] as? String ?? "?").trimmingCharacters(in: .whitespaces)
                let remarks = ctx.remarks(jny["msgL"]) + ctx.remarks(dep["msgL"]) + ctx.remarks(arr["msgL"])
                let poly = ctx.polyline(jny)
                legs.append(Leg(
                    kind: .transit(line: line, product: TransitProduct(cls: prod["cls"] as? Int ?? 64)),
                    fromName: from, toName: to,
                    departure: real.0 ?? pDep, arrival: real.1 ?? pArr,
                    plannedDeparture: pDep, plannedArrival: pArr,
                    coordinates: poly.isEmpty ? ends : poly,
                    departurePlatform: platform(dep, "d"), arrivalPlatform: platform(arr, "a"),
                    direction: jny["dirTxt"] as? String,
                    bikeCarriage: bikeCarriage(remarks),
                    cancelled: (jny["isCncl"] as? Bool ?? false) || (dep["dCncl"] as? Bool ?? false)
                        || (arr["aCncl"] as? Bool ?? false)))
            default:   // WALK, TRSF (transfer inside a station), DEVI
                if from == to && pDep == pArr { continue }
                let gis = sec["gis"] as? [String: Any]
                legs.append(Leg(kind: .walk, fromName: from, toName: to,
                                departure: real.0 ?? pDep, arrival: real.1 ?? pArr,
                                distance: (gis?["dist"] as? Int).map(Double.init),
                                coordinates: ends))
            }
        }
        return legs.contains(where: \.isTransit) ? legs : nil
    }

    private static func platform(_ stop: [String: Any], _ p: String) -> String? {
        (stop["\(p)PltfR"] as? [String: Any])?["txt"] as? String
            ?? (stop["\(p)PltfS"] as? [String: Any])?["txt"] as? String
            ?? stop["\(p)PlatfR"] as? String ?? stop["\(p)PlatfS"] as? String
    }

    /// A leg carries bikes if HAFAS attaches the "FK" remark ("Fahrradmitnahme
    /// möglich") and nothing on the leg says the opposite.
    static func bikeCarriage(_ remarks: [[String: Any]]) -> Bool {
        let texts = remarks.map { (($0["txtN"] as? String) ?? "").lowercased() }
        if texts.contains(where: { $0.contains("keine fahrradmitnahme") || $0.contains("fahrradmitnahme nicht") }) {
            return false
        }
        return remarks.contains { ($0["code"] as? String) == "FK" }
            || texts.contains { $0.contains("fahrradmitnahme möglich") || $0.contains("fahrradmitnahme begrenzt") }
    }
}
