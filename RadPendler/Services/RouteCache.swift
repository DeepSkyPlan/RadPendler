import Foundation

/// Der eine Zwischenspeicher für Rad- und Fußwege, für alle, die planen: den
/// Bildschirm, die im Hintergrund geweckte App und die Neuplanung unterwegs.
///
/// Eine Linie von A nach B ist bei BRouter eine Funktion der beiden Punkte
/// und des Profils — keine Verkehrslage, keine Uhrzeit. Was sie ändern kann,
/// sind die OpenStreetMap-Daten, und die ändern sich nicht in einer Stunde.
/// Für Apples Rad- und Fußwege gilt dasselbe; das Auto fährt nie hindurch,
/// seine Zeiten folgen dem Verkehr.
///
/// Bis 1.9.1 hatte daneben jeder `MapKitRouter` seinen eigenen, ohne Ablauf
/// und ohne Grenze — und jeder Planer, jeder Tracker und die Hintergrund-
/// Planung hatten ihre eigenen Router. Dieselbe Frage ging so mehrmals hinaus.
actor RouteCache {
    static let shared = RouteCache()

    /// So lange gilt eine Antwort. Danach ist sie nicht falsch, aber es ist
    /// billig genug, sie neu zu holen.
    static let lifetime: TimeInterval = 3600
    /// Und so viele werden behalten: eine Pendelstrecke mit allen Profilen,
    /// der gewohnten und Apples Linie sind sieben, die Zubringer von Rad +
    /// Bahn an beiden Enden bis zu zwölf — mal zwei Richtungen.
    static let limit = 64

    private var entries: [String: (route: StreetRoute, at: Date)] = [:]

    func route(for key: String, now: Date = .now) -> StreetRoute? {
        guard let hit = entries[key], now.timeIntervalSince(hit.at) < Self.lifetime else { return nil }
        return hit.route
    }

    func keep(_ route: StreetRoute, for key: String, now: Date = .now) {
        // Abgelaufenes zuerst, dann das Älteste.
        entries = entries.filter { now.timeIntervalSince($0.value.at) < Self.lifetime }
        if entries[key] == nil, entries.count >= Self.limit,
           let oldest = entries.min(by: { $0.value.at < $1.value.at })?.key {
            entries.removeValue(forKey: oldest)
        }
        entries[key] = (route, now)
    }

    var count: Int { entries.count }

    func forget() { entries.removeAll() }
}

/// Die Antworten von BRouter auf der Platte, einen Tag lang.
///
/// `RouteCache` hält sie nur, solange die App läuft. Wer morgens die App
/// öffnet, fragte deshalb jede Linie neu — für eine Pendelstrecke, deren
/// Antwort seit gestern dieselbe ist. Hier liegt die Antwort so, wie der
/// Server sie geschickt hat; gelesen wird sie mit demselben `parse`.
///
/// Dieselbe Schutzklasse wie die Straßendaten, und aus demselben Grund ein
/// Dateiname, dem man nichts ansieht: die Linie führt von Zuhause zur Arbeit.
enum RouteDisk {
    static let lifetime: TimeInterval = 24 * 3600
    static let limit = 48

    private static var folder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("brouter-routes")
    }

    private static func file(_ key: String) -> URL {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return folder.appendingPathComponent(String(format: "r-%016llx.json", hash))
    }

    static func read(_ key: String) -> Data? {
        let url = file(key)
        guard RoadDataStore.age(of: url) < lifetime else { return nil }
        return Log.attempt("Radroute von der Platte lesen", missingIsFine: true) { try Data(contentsOf: url) }
    }

    static func write(_ data: Data, for key: String) {
        let fm = FileManager.default
        Log.attempt("Ordner für Radrouten anlegen") { try fm.createDirectory(at: folder, withIntermediateDirectories: true) }
        Log.attempt("Radroute ablegen") {
            try data.write(to: file(key), options: [.atomic, RoadDataStore.protection])
        }
        // Aufräumen beim Schreiben: Abgelaufenes weg, und nie mehr als `limit`.
        guard let files = Log.attempt("Ordner für Radrouten lesen", missingIsFine: true, {
            try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
        }) else { return }
        let dated = files.map { ($0, RoadDataStore.age(of: $0)) }.sorted { $0.1 < $1.1 }
        for (i, entry) in dated.enumerated() where i >= limit || entry.1 >= lifetime {
            Log.attempt("Radroute aufräumen", missingIsFine: true) { try fm.removeItem(at: entry.0) }
        }
    }
}

