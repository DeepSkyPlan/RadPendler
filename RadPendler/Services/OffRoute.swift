import CoreLocation
import Foundation
import simd

/// Wo die geplante Linie liegt, wenn man nicht auf ihr ist.
///
/// Auf dem Rad verpasst man eine Abbiegung, oder eine Straße ist auf, oder man
/// fährt bewusst anders. Der Abbiegehinweis zeigt dann auf eine Straße, auf der
/// man nicht mehr ist — und je weiter weg, desto sinnloser. Statt dessen: ein
/// Pfeil dorthin, wo die Route liegt, und eine Karte, die weit genug
/// herausgeht, dass man beides sieht. Und wenn das Zurückfinden sich nicht mehr
/// lohnt, ein neuer Weg von hier aus.
enum OffRoute {
    struct Fix: Equatable {
        /// Abstand zur Linie, in Metern.
        var meters: Double
        /// Grad von Norden, vom Fahrer zum nächsten Punkt der Linie.
        var bearing: CLLocationDirection
        /// Ebendieser Punkt — die Karte muss ihn und den Fahrer zusammen zeigen.
        var nearest: CLLocationCoordinate2D

        /// `CLLocationCoordinate2D` ist von sich aus nicht vergleichbar.
        static func == (a: Fix, b: Fix) -> Bool {
            a.meters == b.meters && a.bearing == b.bearing
                && a.nearest.latitude == b.nearest.latitude && a.nearest.longitude == b.nearest.longitude
        }
    }

    /// Ab hier gilt man als abgewichen …
    static let offMeters = 60.0
    /// … und erst darunter wieder als drauf. Der Abstand dazwischen ist
    /// Absicht: ohne ihn flackert der Pfeil auf einem Radweg neben der
    /// gerouteten Fahrbahn, wo ein Fix mit fünfzehn Metern Ungenauigkeit über
    /// die Schwelle und wieder zurück springt.
    static let backOnMeters = 35.0
    /// Voreinstellung dafür, ab wann der Weg zum Ziel neu berechnet wird;
    /// einstellbar unter „Neu berechnen ab". Auf der ersten Testfahrt war ein
    /// Kilometer zu spät: bis dahin ist man längst auf einer anderen Straße,
    /// und der Pfeil zurück zeigt auf einen Weg, den man nicht mehr fährt.
    static let replanMeters = 200.0
    /// Und erst, wenn man so lange ohne Unterbrechung daneben ist. Ein kurzer
    /// Bogen um eine Baustelle ist kein neuer Weg.
    static let offFor: TimeInterval = 15

    /// Ob jetzt neu geplant werden soll: **was zuerst eintritt**.
    ///
    /// - Die Strecke, aber nicht sofort — `offFor` Sekunden am Stück daneben,
    ///   sonst löst jeder Bogen um eine Baustelle eine Neuplanung aus.
    /// - Oder die Zeit, ganz ohne Rücksicht auf die Entfernung: wer im Kreis
    ///   um einen gesperrten Weg fährt, kommt nie weit genug weg und braucht
    ///   trotzdem irgendwann einen neuen Vorschlag.
    ///
    /// Beide Werte 0 heißt: gar nicht neu planen, nur der Pfeil zurück.
    /// Rein, damit die Regel ohne Fahrt zu prüfen ist.
    static func shouldReplan(meters: Double, offFor seconds: TimeInterval,
                             afterMeters: Double, afterMinutes: Double) -> Bool {
        if afterMeters > 0, meters > afterMeters, seconds >= offFor { return true }
        if afterMinutes > 0, seconds >= afterMinutes * 60 { return true }
        return false
    }
    /// Und selbst dann nicht öfter als so oft: eine Neuplanung je Ortung wäre
    /// eine Anfrage je Sekunde.
    static let replanEvery: TimeInterval = 60

    /// Nächster Punkt auf der Linie — auf den Strecken, nicht nur auf ihren
    /// Ecken. BRouter setzt zwischen zwei Punkten gern hundert Meter gerade
    /// Straße; der nächste Punkt liegt dann fast nie auf einer der Ecken, und
    /// wer nur die Ecken misst, meldet eine Abweichung, die es nicht gibt.
    static func nearest(to here: CLLocationCoordinate2D,
                        on route: [CLLocationCoordinate2D]) -> Fix? {
        guard let first = route.first else { return nil }
        guard route.count >= 2 else {
            return Fix(meters: here.distance(to: first),
                       bearing: TurnGuide.bearing(from: here, to: first), nearest: first)
        }
        let flat = Flat(latitude: here.latitude)
        let p = flat.point(here)
        var best: (d2: Double, at: SIMD2<Double>)?
        for (a, b) in zip(route, route.dropFirst()) {
            let pa = flat.point(a), pb = flat.point(b)
            let ab = pb - pa
            let len2 = simd_length_squared(ab)
            // Der Lotfußpunkt, auf die Strecke begrenzt: außerhalb ist es einer
            // der beiden Endpunkte.
            let t = len2 > 0 ? Swift.max(0, Swift.min(1, simd_dot(p - pa, ab) / len2)) : 0
            let q = pa + ab * t
            let d2 = simd_length_squared(p - q)
            if best == nil || d2 < best!.d2 { best = (d2, q) }
        }
        guard let best else { return nil }
        let point = flat.coordinate(best.at)
        return Fix(meters: here.distance(to: point),
                   bearing: TurnGuide.bearing(from: here, to: point), nearest: point)
    }

    /// Ob man (noch) als abgewichen gilt. Mit Hysterese — hinein ab
    /// `offMeters`, heraus erst unter `backOnMeters`.
    static func isOff(_ meters: Double, was: Bool) -> Bool {
        was ? meters > backOnMeters : meters > offMeters
    }
}
