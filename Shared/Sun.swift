import CoreLocation
import Foundation

/// Wo die Sonne steht — genug, um Tag und Dunkelheit zu trennen (auf rund
/// ein Zehntelgrad, die Näherung des Astronomischen Almanachs).
enum Sun {
    /// Höhe über dem Horizont in Grad, ohne Lichtbrechung.
    static func elevation(at date: Date, _ c: CLLocationCoordinate2D) -> Double {
        let rad = Double.pi / 180
        let n = date.timeIntervalSince1970 / 86_400 + 2_440_587.5 - 2_451_545.0
        let mean = (280.460 + 0.985_647_4 * n).truncatingRemainder(dividingBy: 360)
        let anomaly = (357.528 + 0.985_600_3 * n).truncatingRemainder(dividingBy: 360) * rad
        let lambda = (mean + 1.915 * sin(anomaly) + 0.020 * sin(2 * anomaly)) * rad
        let epsilon = (23.439 - 0.000_000_4 * n) * rad
        let ra = atan2(cos(epsilon) * sin(lambda), cos(lambda))
        let decl = asin(sin(epsilon) * sin(lambda))
        let gmst = (280.460_618_37 + 360.985_647_366_29 * n).truncatingRemainder(dividingBy: 360)
        let hour = (gmst + c.longitude) * rad - ra
        let phi = c.latitude * rad
        return asin(sin(phi) * sin(decl) + cos(phi) * cos(decl) * cos(hour)) / rad
    }

    /// Ab Sonnenuntergang bis Sonnenaufgang — der Rand der Scheibe am
    /// Horizont, mit Lichtbrechung (−0,833°). Ab da beginnt die Dämmerung,
    /// und ab da zählt, ob ein Weg Licht hat.
    static func isDark(at date: Date, _ c: CLLocationCoordinate2D) -> Bool {
        elevation(at: date, c) < -0.833
    }
}
