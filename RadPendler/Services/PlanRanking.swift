import CoreLocation
import Foundation

// Reihenfolge und Empfehlung: welche Möglichkeit oben steht und welche die
// App vorschlägt. Reine Rechnung auf fertigen Möglichkeiten.

extension TripPlanner {
    /// Earliest arrival first, each change of train counted as `penalty`;
    /// within 3 minutes the more active mode first.
    /// `order` is the user's list of modes: it decides which one wins when two
    /// trips arrive within three minutes of each other.
    static func ranking(_ a: TripOption, _ b: TripOption, penalty: TimeInterval = 600,
                        arrival: Bool = false,
                        order: [TravelMode] = TravelMode.defaultOrder) -> Bool {
        if a.passesWaypoints != b.passesWaypoints { return a.passesWaypoints }
        // Leaving as late as possible is the point of an arrival search.
        let wa = score(a, penalty: penalty, arrival: arrival)
        let wb = score(b, penalty: penalty, arrival: arrival)
        if abs(wa - wb) < 180, a.mode != b.mode {
            return rank(a.mode, order) < rank(b.mode, order)
        }
        return wa < wb
    }

    static func rank(_ mode: TravelMode, _ order: [TravelMode]) -> Int {
        order.firstIndex(of: mode) ?? order.count
    }

    private static func score(_ o: TripOption, penalty: TimeInterval, arrival: Bool) -> Double {
        let d = arrival ? o.weightedLeave(penalty) : o.weightedArrival(penalty)
        return arrival ? -d.timeIntervalSince1970 : d.timeIntervalSince1970
    }

    /// The user's own rule, as far as the settings let it be one: dry → ride
    /// (the whole way, or with the train if that arrives earlier); wet → bike
    /// in the train, which keeps the time in the rain short; everything else in
    /// the order the user put the modes in. "Dry" and the order both come from
    /// the settings — `rainSwitch` is the level at which the bike goes into the
    /// train, `order` decides the ties.
    static func recommend(_ options: [TripOption], penalty: TimeInterval = 600,
                          order: [TravelMode] = TravelMode.defaultOrder,
                          rainSwitch: RainLevel = .light) -> Recommendation? {
        let arrival = { (o: TripOption) in o.weightedArrival(penalty) }
        let level = { (o: TripOption) in o.rain?.level ?? .dry }
        let preferredBike = { (o: TripOption) in o.mode == .bike && o.isPreferredVariant }
        // U-Bahn/tram connections only count when no S-Bahn/regional one exists.
        let onRoute = options.filter(\.passesWaypoints)
        let bikeTrains = (onRoute.isEmpty ? options : onRoute).filter { $0.mode == .bikeTransit && !$0.isAlternative }
        // The fallback stays inside the fixed points too — it used to reach
        // past them while the line below promised it would not.
        let anyBikeTransit = (onRoute.isEmpty ? options : onRoute).filter { $0.mode == .bikeTransit }
        let bikeTransit = bikeTrains.isEmpty ? anyBikeTransit : bikeTrains
        // Trips that miss the fixed points are never recommended while others exist.
        let options = options.contains(where: \.passesWaypoints) ? options.filter(\.passesWaypoints) : options
        let bikeish = options.filter(preferredBike) + bikeTransit
        let dry = bikeish.filter { level($0) < rainSwitch }

        if let pick = dry.min(by: { ranking($0, $1, penalty: penalty, order: order) }) {
            let reason = pick.mode == .bike
                ? "Radstrecke \(pick.rain?.summary ?? "ohne Regendaten")"
                : L("trocken und mit der Bahn schneller als die ganze Strecke per Rad")
            return Recommendation(optionID: pick.id, reason: reason)
        }
        if let pick = bikeTransit
            .min(by: { (level($0), arrival($0)) < (level($1), arrival($1)) }) {
            let wet = options.first(where: preferredBike)?.rain?.summary
            return Recommendation(optionID: pick.id,
                                  reason: L("Regen auf der Radstrecke%@ — Rad in die Bahn",
                                            wet.map { " (\($0))" } ?? ""))
        }
        // No connection that takes the bike: fall back in the user's own order,
        // minus bike + rail, which just had its turn.
        for mode in order where mode != .bikeTransit {
            if let pick = options.filter({ $0.mode == mode }).min(by: { arrival($0) < arrival($1) }) {
                return Recommendation(optionID: pick.id, reason: L("keine Verbindung mit Radmitnahme gefunden"))
            }
        }
        return nil
    }
}
