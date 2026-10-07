import Foundation
import os

/// Was schiefging, ohne dass es jemand gesehen hätte.
///
/// Bis 1.16 stand an gut hundert Stellen ein `try?`, und die App hatte genau
/// eine Protokollzeile. Eine Linie, die sich nicht schreiben ließ, ein
/// Zwischenspeicher, der bei gesperrtem Gerät nicht lesbar war, eine Warnung,
/// die iOS nicht annahm — nichts davon hinterließ eine Spur. Gemeldet wurde
/// nur, was auf dem Bildschirm auffiel.
///
/// Jetzt geht jeder solche Fehler zweimal hinaus: ins Systemprotokoll
/// (Konsole.app, Filter `subsystem:de.keese.radpendler`) und in eine kurze
/// Liste im Speicher, die „Fahrt teilen" in die Auswertungsdatei schreibt.
///
/// **Ohne Orte.** In die Liste kommen nur die Stelle im Code und Art und
/// Nummer des Fehlers — nie sein Text: der kann Pfade und Adressen enthalten.
/// Im Systemprotokoll steht der Text als `private` und ist nur auf dem
/// entsperrten eigenen Gerät lesbar.
enum Log {
    struct Entry: Codable, Equatable {
        var t: Date
        var what: String
        /// „NSCocoaErrorDomain 513" — Art und Nummer, sonst nichts.
        var error: String
    }

    /// So viele bleiben. Ein Fehler in einer Schleife soll weder den Speicher
    /// noch die geteilte Datei füllen.
    static let limit = 50

    private static let logger = Logger(subsystem: "de.keese.radpendler", category: "fehler")
    private static let lock = NSLock()
    private static var entries: [Entry] = []

    /// Die jüngsten Fehler dieses Laufs, älteste zuerst.
    static var recent: [Entry] {
        lock.lock(); defer { lock.unlock() }
        return entries
    }

    static func clear() {
        lock.lock(); defer { lock.unlock() }
        entries = []
    }

    /// Ein Abbruch ist kein Fehler: wer auf das Adressfeld tippt, bricht die
    /// laufende Planung ab, und das soll hier nicht stehen.
    static func note(_ what: String, _ error: Error) {
        guard !isCancellation(error) else { return }
        let ns = error as NSError
        let code = "\(ns.domain) \(ns.code)"
        logger.error("\(what, privacy: .public): \(code, privacy: .public) — \(error.localizedDescription, privacy: .private)")
        lock.lock(); defer { lock.unlock() }
        entries.append(Entry(t: .now, what: what, error: code))
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
    }

    /// `try?` mit Gedächtnis. `missingIsFine` für Dateien, die es nicht geben
    /// muss — die Linie einer Fahrt vom anderen Gerät, der Zwischenstand einer
    /// Aufzeichnung, die ordentlich beendet wurde.
    @discardableResult
    static func attempt<T>(_ what: String, missingIsFine: Bool = false, _ work: () throws -> T) -> T? {
        do { return try work() } catch {
            if !(missingIsFine && isMissingFile(error)) { note(what, error) }
            return nil
        }
    }

    /// Dasselbe für alles, was wartet. Eigener Name, damit `attempt` in einer
    /// `async`-Funktion ohne `await` auskommt. Läuft auf dem Akteur des
    /// Aufrufers weiter.
    @discardableResult
    static func attemptAsync<T>(_ what: String, isolation: isolated (any Actor)? = #isolation,
                                _ work: () async throws -> T) async -> T? {
        do { return try await work() } catch {
            note(what, error)
            return nil
        }
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }

    static func isMissingFile(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain {
            return ns.code == NSFileReadNoSuchFileError || ns.code == NSFileNoSuchFileError
        }
        return ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOENT)
    }
}
