import Foundation

/// Der eine Weg, auf dem Listen in die UserDefaults und nach iCloud gehen und
/// von dort zurückkommen.
///
/// Was dort liegt, hat irgendeine Fassung der App geschrieben — eine ältere,
/// eine neuere auf dem anderen Gerät, oder eine mit einem Fehler (03.10.2026:
/// Zählungen bis zum Überlauf). Drei Regeln, damit das keine Fassung umwirft:
///
/// 1. **Lesen verzeiht.** Ein Eintrag, den diese Fassung nicht lesen kann,
///    fällt allein heraus — nicht die ganze Liste mit ihm. Und ein Feld, das
///    nach der ersten Fassung eines Typs dazukam, ist beim Lesen nie Pflicht:
///    ein Vorgabewert am Feld reicht dafür **nicht**, das synthetisierte
///    `Decodable` verlangt den Schlüssel trotzdem. Solche Typen bekommen ein
///    eigenes `init(from:)` (siehe `Ride`).
/// 2. **Schreiben ist stabil.** Dieselbe Liste ergibt dieselben Bytes — ohne
///    `.sortedKeys` würfelt `JSONEncoder` die Reihenfolge je Prozess neu.
/// 3. **Was hereinkommt, wird begrenzt**, bevor damit gerechnet wird
///    (`sanitized` an jedem reisenden Typ). Swift bricht bei einem Überlauf
///    ab, und ein Wert in iCloud kommt nach jeder Neuinstallation zurück.
///
/// `StoredFormatTests` hält zu jeder ausgelieferten Fassung eine Probe fest.
enum Stored {
    static func encode<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return Log.attempt("kodieren: \(T.self)") { try encoder.encode(value) }
    }

    /// nil nur, wenn dort gar keine Liste steht.
    static func list<T: Decodable>(_ type: T.Type = T.self, from data: Data) -> [T]? {
        Log.attempt("Liste lesen: \(T.self)") { try JSONDecoder().decode(List<T>.self, from: data) }?.items
    }

    /// Dasselbe für eine Liste mitten in einem anderen Typ.
    struct List<T: Decodable>: Decodable {
        let items: [T]
        init(from decoder: Decoder) throws { items = try [Lossy<T>](from: decoder).compactMap(\.value) }
    }

    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    // MARK: Grenzen

    /// Ein Zähler: nie negativ, nie über dem, was er in Jahren erreichen kann.
    static func count(_ n: Int, max limit: Int) -> Int { Swift.min(Swift.max(0, n), limit) }

    /// Eine Menge (Sekunden, Meter): endlich, nie negativ, gedeckelt.
    static func amount(_ x: Double, max limit: Double) -> Double {
        x.isFinite ? Swift.min(Swift.max(0, x), limit) : 0
    }

    static func plausible(lat: Double, lon: Double) -> Bool {
        lat.isFinite && lon.isFinite && abs(lat) <= 90 && abs(lon) <= 180
    }

    /// Zeiten, zu denen diese App etwas aufgezeichnet haben kann.
    static func plausible(_ date: Date) -> Bool {
        (0...6_000_000_000).contains(date.timeIntervalSince1970)
    }
}
