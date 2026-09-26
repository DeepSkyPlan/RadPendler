import Foundation

/// Was gelöscht wurde, und wann.
///
/// Drei Listen reisen zwischen den Geräten und werden dabei **vereinigt**
/// statt ersetzt: die Fahrten, die benutzten Adressen und die gelernten
/// Ampeln. Das muss so sein — ein Gerät, das seit einer Woche nicht
/// nachgesehen hat, darf keine Liste kürzen, die es nie gesehen hat.
///
/// Der Preis dafür war, dass Löschen nicht ging: Gerät A löscht eine Fahrt,
/// Gerät B kennt sie noch, vereinigt sie mit seiner Fassung, schreibt sie
/// zurück — und A holt sie sich beim nächsten Abgleich wieder herein. Das ist
/// kein theoretischer Fall, sondern der Normalfall mit iPhone und iPad.
///
/// Deshalb reist jetzt mit, was **nicht** mehr da sein soll. Eine Kennung mit
/// Zeitstempel, und die Vereinigung wirft hinterher hinaus, was einen
/// Grabstein hat. Weil auch die Grabsteine vereinigt werden, kommt die
/// Löschung auf jedem Gerät an, egal wer zuerst nachsieht.
struct Tombstones: Codable, Equatable {
    /// Kennung → wann gelöscht. Die Kennung ist kurz und trägt ihre Art vorn:
    /// `ride:<uuid>`, `place:<schlüssel>`, `signal:<gitterzelle>`.
    private(set) var stones: [String: Date] = [:]

    /// So lange wird ein Grabstein mitgeführt. Danach ist jedes Gerät, das
    /// den gelöschten Eintrag noch hatte, entweder längst nachgezogen oder so
    /// lange aus, dass es ohnehin neu anfängt. Ohne diese Grenze wüchse die
    /// Liste ewig, und sie teilt sich den einen iCloud-Speicher mit allem
    /// anderen.
    static let lifetime: TimeInterval = 90 * 24 * 3600

    static func key(ride id: UUID) -> String { "ride:\(id.uuidString)" }
    static func key(place id: String) -> String { "place:\(id)" }
    static func key(signal id: String) -> String { "signal:\(id)" }

    func has(_ key: String) -> Bool { stones[key] != nil }

    mutating func add(_ key: String, at now: Date = .now) {
        stones[key] = now
    }

    mutating func add(_ keys: [String], at now: Date = .now) {
        for key in keys { stones[key] = now }
    }

    /// Beide Listen in eine: die spätere Löschung gewinnt, Altes fällt weg.
    func merging(_ other: Tombstones, now: Date = .now) -> Tombstones {
        var out = stones
        for (key, when) in other.stones {
            out[key] = Swift.max(out[key] ?? .distantPast, when)
        }
        out = out.filter { now.timeIntervalSince($0.value) < Self.lifetime }
        return Tombstones(stones: out)
    }

    // MARK: In den UserDefaults

    /// Der eine Schlüssel, unter dem die Liste liegt — `RideStore` und
    /// `AppSettings` löschen beide, also greifen beide hierher.
    static let key = "tombstones"

    static func load(_ defaults: UserDefaults) -> Tombstones {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Tombstones.self, from: $0) } ?? Tombstones()
    }

    /// Immer frisch lesen, ergänzen, zurückschreiben: zwei Stellen löschen,
    /// und eine im Speicher gehaltene Kopie wäre nach dem ersten Mal veraltet.
    @discardableResult
    static func bury(_ keys: [String], in defaults: UserDefaults, at now: Date = .now) -> Tombstones {
        var stones = load(defaults)
        stones.add(keys, at: now)
        defaults.set(try? JSONEncoder().encode(stones), forKey: key)
        return stones
    }

    /// Ein Grabstein zählt nur, wenn er **nach** dem Eintrag gesetzt wurde:
    /// wer eine Adresse löscht und sie am nächsten Tag wieder benutzt, hat sie
    /// wieder, und kein Abgleich darf sie ihm ein zweites Mal wegnehmen.
    func buried(_ key: String, newerThan when: Date) -> Bool {
        guard let stone = stones[key] else { return false }
        return stone >= when
    }
}
