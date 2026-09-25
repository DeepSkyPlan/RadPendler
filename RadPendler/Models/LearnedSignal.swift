import CoreLocation
import Foundation

/// A place where the rider actually had to wait. OpenStreetMap knows most
/// traffic lights, but not all of them, and it knows none of the ones that are
/// only a light in practice — the crossing where the tram always comes, the
/// gate, the junction where nobody lets you out.
///
/// So the app remembers where *this* rider stops, counts how often and how
/// long, and uses that from the next ride on: for deciding whether a standstill
/// was a red light, and for the bike times, where a junction costs what it has
/// been measured to cost.
///
/// Nothing here leaves the device except into the user's own iCloud, exactly
/// like the addresses.
struct LearnedSignal: Codable, Equatable, Identifiable {
    var lat: Double
    var lon: Double
    /// How often the rider stopped here.
    var stops: Int
    /// Seconds waited here, in total.
    var totalWait: TimeInterval
    var lastSeen: Date
    /// How often a recorded ride came past here at all — stops included.
    ///
    /// This is what makes the average honest. `totalWait / stops` answers "how
    /// long is the wait when I have to wait", and that is not what a route
    /// costs: a light that is green every other morning costs half of that.
    /// `nil` are the entries from before this was counted; for them every pass
    /// was a stop, which is exactly what the app assumed back then.
    var passes: Int?

    var id: String { "\(Int(lat * 100_000))/\(Int(lon * 100_000))" }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    var averageWait: TimeInterval { stops > 0 ? totalWait / Double(stops) : 0 }

    /// Never fewer than the stops: an entry that was counted before the passes
    /// were, or one merged from a device that did not count them, must not
    /// come out as "waited twelve times in one pass".
    var passCount: Int { max(passes ?? 0, stops) }

    /// So viele Vorbeifahrten mit dem eingestellten Mittelwert bekommt jede
    /// Kreuzung geschenkt, bevor das Gemessene sie bestimmt.
    ///
    /// Ohne das entscheidet die erste Beobachtung alles: wer einmal an einer
    /// Schranke neunzig Sekunden stand, hätte dort für immer neunzig Sekunden
    /// stehen — und wer einmal bei Grün durchfuhr, nie wieder. Drei ist wenig
    /// genug, dass nach einer Woche Pendeln das Gemessene führt, und genug,
    /// dass ein einzelner Ausreißer die Fahrzeit nicht umwirft.
    static let prior = 3.0

    /// Was diese Kreuzung eine Fahrt im Mittel kostet — gemessen, gemischt mit
    /// dem eingestellten Mittelwert nach `prior`.
    func expectedWait(default flat: TimeInterval) -> TimeInterval {
        (totalWait + Self.prior * flat) / (Double(passCount) + Self.prior)
    }

    /// Two stops this close are the same junction. Wider than the 45 m the
    /// tracker uses to *recognise* one: two waits at the same light can be on
    /// opposite sides of a big crossing.
    static let mergeRadius = 60.0
    /// So nah muss die aufgezeichnete Linie an einer Kreuzung vorbeikommen,
    /// damit die Fahrt dort vorbeigekommen ist. Dasselbe Maß, mit dem der
    /// Zähler einen Halt einer Ampel zuschreibt.
    static let passRadius = 45.0
    /// A list this long covers years of one commute; beyond it the rarest go.
    static let limit = 500

    /// Records one wait. The remembered position moves towards the new one in
    /// proportion to how often it has been seen — the twentieth stop nudges it,
    /// the second one moves it half way. A stop is a pass, too.
    static func recording(_ list: [LearnedSignal], at c: CLLocationCoordinate2D,
                          waited: TimeInterval, now: Date = .now) -> [LearnedSignal] {
        var out = list
        if let i = nearest(in: out, to: c) {
            let n = Double(out[i].stops)
            out[i].lat = (out[i].lat * n + c.latitude) / (n + 1)
            out[i].lon = (out[i].lon * n + c.longitude) / (n + 1)
            out[i].stops += 1
            out[i].passes = out[i].passCount + 1
            out[i].totalWait += waited
            out[i].lastSeen = now
        } else {
            out.append(LearnedSignal(lat: c.latitude, lon: c.longitude, stops: 1,
                                     totalWait: waited, lastSeen: now, passes: 1))
        }
        return capped(out)
    }

    /// Eine Vorbeifahrt ohne Halt: grün, freie Kreuzung, niemand im Weg. Die
    /// Stelle behält ihre Lage — die kommt von der Karte oder von den Halten,
    /// und eine Durchfahrt weiß nicht besser, wo die Ampel steht.
    static func passing(_ list: [LearnedSignal], at c: CLLocationCoordinate2D,
                        now: Date = .now) -> [LearnedSignal] {
        var out = list
        if let i = nearest(in: out, to: c) {
            out[i].passes = out[i].passCount + 1
            out[i].lastSeen = now
        } else {
            out.append(LearnedSignal(lat: c.latitude, lon: c.longitude, stops: 0,
                                     totalWait: 0, lastSeen: now, passes: 1))
        }
        return capped(out)
    }

    /// Index of the entry within `mergeRadius`, nearest first.
    static func nearest(in list: [LearnedSignal], to c: CLLocationCoordinate2D) -> Int? {
        let mPerDegLat = 111_320.0
        let mPerDegLon = mPerDegLat * cos(c.latitude * .pi / 180)
        var best: (Int, Double)?
        for (i, s) in list.enumerated() {
            let dx = (s.lon - c.longitude) * mPerDegLon
            let dy = (s.lat - c.latitude) * mPerDegLat
            let d2 = dx * dx + dy * dy
            guard d2 <= mergeRadius * mergeRadius else { continue }
            if best == nil || d2 < best!.1 { best = (i, d2) }
        }
        return best?.0
    }

    /// Both devices' lists into one, the way `placeHistory` merges: nothing
    /// either side knew may fall out, and the same junction counts once.
    static func merging(_ mine: [LearnedSignal], _ theirs: [LearnedSignal]) -> [LearnedSignal] {
        var out = mine
        for s in theirs {
            if let i = nearest(in: out, to: s.coordinate) {
                // The same junction, seen on both devices. Whoever saw it more
                // often has the better position; the counts add up.
                if s.stops > out[i].stops { out[i].lat = s.lat; out[i].lon = s.lon }
                out[i].passes = out[i].passCount + s.passCount
                out[i].stops += s.stops
                out[i].totalWait += s.totalWait
                out[i].lastSeen = max(out[i].lastSeen, s.lastSeen)
            } else {
                out.append(s)
            }
        }
        return capped(out)
    }

    /// Over the limit the least used go first, the longest unseen among them.
    /// Measured by passes, not by stops: the junction one rolls through every
    /// morning is part of this commute and worth its entry — it is the reason
    /// the route is faster than the map thinks.
    private static func capped(_ list: [LearnedSignal]) -> [LearnedSignal] {
        guard list.count > limit else { return list }
        return Array(list.sorted { ($0.passCount, $0.lastSeen) > ($1.passCount, $1.lastSeen) }.prefix(limit))
    }
}
