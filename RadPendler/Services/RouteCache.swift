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
