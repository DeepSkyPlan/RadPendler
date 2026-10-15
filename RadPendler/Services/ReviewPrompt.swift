import Foundation

/// Wann die App nach einer Bewertung im App Store fragt: einmal je neuer
/// Fassung, nach einer Fahrt (Nutzer, 15.10.2026).
///
/// Gefragt wird mit Apples eigenem Fenster (`requestReview`): Sterne direkt,
/// und von dort mit einem Tipp zur Rezension. Ob es wirklich erscheint,
/// entscheidet iOS — höchstens dreimal in 365 Tagen, gar nicht in
/// TestFlight-Fassungen und nicht, wenn jemand es in den Einstellungen
/// abgeschaltet hat. Mehr als „jetzt wäre ein guter Moment“ kann die App
/// nicht sagen.
///
/// Der gute Moment ist das Schließen der Zusammenfassung nach einer Fahrt:
/// man hat die App gerade benutzt und ist fertig damit — nicht beim Öffnen,
/// nicht mitten im Planen. Und erst ab der zweiten Fahrt: wer die App einmal
/// ausprobiert hat, kann noch nicht sagen, ob sie taugt.
enum ReviewPrompt {
    /// Welche Fassung zuletzt gefragt hat — nur auf diesem Gerät.
    static let key = "reviewAskedVersion"
    static let minRides = 2

    /// „1.22“ — die Fassung, nicht der Build: ein neuer Build derselben
    /// Fassung fragt nicht noch einmal.
    static var currentVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    static func due(version: String?, asked: String?, rides: Int) -> Bool {
        guard let version, rides >= minRides else { return false }
        return version != asked
    }
}
