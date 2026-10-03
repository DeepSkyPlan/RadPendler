import Foundation

/// Die Bremse für eine Absturzschleife.
///
/// Am 03.10.2026 stürzte die App beim Start ab, auf jedem Gerät und nach
/// jeder Neuinstallation: der Stand, an dem sie starb, lag in iCloud und kam
/// jedes Mal zurück. Was hereinkommt, wird inzwischen begrenzt (`Stored`) —
/// das hier ist für den Fehler, den noch niemand kennt.
///
/// Jeder Start wird gezählt, bevor irgendetwas geladen ist, und wieder
/// gestrichen, sobald die App zehn Sekunden gelaufen oder ordentlich in den
/// Hintergrund gegangen ist. Bleiben zwei Starts hintereinander stehen, läuft
/// der dritte **ohne iCloud-Abgleich** — und so bleibt es, bis eine andere
/// Fassung der App installiert ist oder der Nutzer ihn in den Einstellungen
/// wieder einschaltet. Die App ist dann benutzbar und ein Update kommt an.
///
/// Was das nicht kann: einen Stand heilen, der schon in den UserDefaults
/// dieses Geräts liegt. Dagegen hilft nur das Begrenzen beim Laden.
enum StartGuard {
    static let attemptsKey = "startAttempts"
    static let pausedKey = "cloudPausedIn"
    /// So viele unüberlebte Starts hintereinander sind einer zu viel.
    static let limit = 2
    /// Nach so vielen Sekunden gilt ein Start als überlebt.
    static let alive: TimeInterval = 10

    static var build: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    private static var began: Date?

    /// Einmal je Prozess, vor dem ersten Laden.
    static func begin(_ defaults: UserDefaults = .standard, build: String = StartGuard.build) {
        let failed = defaults.integer(forKey: attemptsKey)
        if failed >= limit {
            defaults.set(build, forKey: pausedKey)
            defaults.set(0, forKey: attemptsKey)
        } else {
            defaults.set(failed + 1, forKey: attemptsKey)
        }
        began = .now
    }

    /// Dieser Start hat gehalten.
    static func survived(_ defaults: UserDefaults = .standard) {
        guard defaults.integer(forKey: attemptsKey) != 0 else { return }
        defaults.set(0, forKey: attemptsKey)
    }

    /// Der Weg in den Hintergrund zählt erst nach ein paar Sekunden: beim
    /// Start selbst wechselt die Szene auch einmal die Phase, und das ist kein
    /// Beweis für irgendetwas.
    static func leftForeground(_ defaults: UserDefaults = .standard, now: Date = .now) {
        guard let began, now.timeIntervalSince(began) >= 3 else { return }
        survived(defaults)
    }

    /// Ob iCloud für diese Fassung der App angehalten ist.
    static func cloudPaused(_ defaults: UserDefaults = .standard, build: String = StartGuard.build) -> Bool {
        defaults.string(forKey: pausedKey) == build
    }

    static func resume(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: pausedKey)
        defaults.set(0, forKey: attemptsKey)
    }
}
