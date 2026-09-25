import Foundation

/// Welche Sprache die App spricht.
///
/// „Wie das Telefon" ist die Voreinstellung und für fast jeden richtig. Die
/// beiden anderen sind für die Fälle, in denen das Telefon etwas anderes sagt,
/// als man lesen will.
///
/// **Die Umstellung wirkt sofort, ohne Neustart.** Das geht nicht über die
/// Sprachwahl des Systems — die steht fest, wenn der Prozess startet, und vier
/// Wege, sie von innen umzustellen, sind nachweislich gescheitert (siehe `L`).
/// Es geht, weil die App die Systemsprache gar nicht erst fragt: `L(…)` liest
/// unmittelbar aus dem Verzeichnis der gewählten Sprache, und die Wurzelansicht
/// trägt die Sprache als Kennung — wechselt sie, baut SwiftUI den Baum neu auf
/// und jeder Text wird neu nachgeschlagen.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, de, en

    var id: String { rawValue }

    /// Die Kennung des Sprachverzeichnisses; nil heißt „wie das Telefon".
    var code: String? { self == .system ? nil : rawValue }

    var flag: String {
        switch self {
        case .system: "A"
        case .de: "🇩🇪"
        case .en: "🇬🇧"
        }
    }

    /// In der eigenen Sprache, nicht in der gerade eingestellten: wer die
    /// App auf Englisch stehen hat und Deutsch sucht, sucht „Deutsch".
    var title: String {
        switch self {
        case .system: L("Wie das Telefon")
        case .de: "Deutsch"
        case .en: "English"
        }
    }

    /// Das Sprachverzeichnis, aus dem `L(…)` liest. nil heißt: das Paket
    /// selbst fragen, also die Sprache, die das Telefon gewählt hat.
    var bundle: Bundle? {
        guard let code, let path = Bundle.main.path(forResource: code, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    /// Und die Schreibweise der Zahlen dazu: „1,5 km" gegen „1.5 km". Die
    /// Sprachwahl des Systems bleibt davon unberührt — das hier gilt nur für
    /// das, was die App selbst formatiert.
    var locale: Locale { code.map { Locale(identifier: $0) } ?? .autoupdatingCurrent }

    /// Die gerade gewählte Sprache. `L(…)` liest sie, die Wurzelansicht trägt
    /// sie als Kennung — ändert sie sich, wird der Baum neu gebaut und jeder
    /// Text neu nachgeschlagen.
    static var current: AppLanguage = .system {
        didSet {
            bundle = current.bundle
            locale = current.locale
        }
    }

    private(set) static var bundle: Bundle?
    /// Für alles, was die App selbst formatiert — `Fmt` liest von hier.
    private(set) static var locale: Locale = .autoupdatingCurrent
}

/// Ein Text in der gewählten Sprache.
///
/// **Warum nicht einfach `Text("Abfahrt")`?** Weil SwiftUI dann die Sprache
/// nimmt, die das System beim Start gewählt hat, und die lässt sich von innen
/// nicht umstellen. Vier Wege sind daran gescheitert, alle nachgemessen:
/// die Klasse von `Bundle.main` austauschen (greift für eigene Abfragen, nicht
/// für `Text`), `\.locale` in der Umgebung setzen (steuert nur Formatierung),
/// `AppleLanguages` schreiben und neu starten (blieb deutsch), und
/// `CFBundleLocalizations` nachtragen (auch nicht).
///
/// Dieser Weg fragt die Sprachwahl des Systems gar nicht erst: er liest
/// unmittelbar aus dem Verzeichnis der gewählten Sprache. `Text(String)`
/// schlägt nichts mehr nach, also bleibt stehen, was hier herauskommt.
///
/// Fehlt eine Übersetzung, kommt der deutsche Schlüssel — besser als ein
/// Platzhalter auf dem Bildschirm.
func L(_ key: String) -> String {
    guard let bundle = AppLanguage.bundle else {
        return Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }
    return bundle.localizedString(forKey: key, value: key, table: nil)
}

/// Dasselbe für Sätze mit Zahlen darin: `L("%d von %d Ampeln", passed, all)`.
///
/// Ein eingesetzter Wert mitten im Satz geht nicht als Schlüssel — „3 Ampeln"
/// und „4 Ampeln" wären zwei Einträge, und im Englischen steht die Zahl
/// womöglich woanders. Deshalb ist der Schlüssel die Form mit Platzhaltern,
/// und die Sprache darf sie umstellen.
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = L(key)
    guard !args.isEmpty else { return format }
    return String(format: format, locale: AppLanguage.locale, arguments: args)
}
