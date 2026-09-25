import Foundation

/// The plan as the watch sees it: no routes, no coordinates, no rain radar —
/// only what fits on a wrist. Small enough for `updateApplicationContext`,
/// which keeps just the newest state and reaches the watch whether or not its
/// app is running.
///
/// Colours travel as hex, so the watch needs none of the phone's colour tables.
struct TripSnapshot: Codable, Equatable {
    struct Leg: Codable, Equatable, Identifiable {
        var id = UUID()
        var symbol: String
        /// "S7", "M11" — nil on foot, by bike or by car.
        var line: String?
        var from: String
        var to: String
        var departure: Date
        var arrival: Date
        var meters: Double?
        var colorHex: String
    }

    struct Option: Codable, Equatable, Identifiable {
        var id: String
        /// `TravelMode.rawValue` — how the watch groups the options.
        var mode: String
        /// Block order on the phone: Rad, Rad + Bahn, Auto, Bahn & Bus.
        var modeRank: Int
        var modeTitle: String
        var symbol: String
        var colorHex: String
        /// "schnellst", "ab 14:39", "2× umsteigen" — the line under the time.
        var caption: String
        var leave: Date
        var arrival: Date
        var getReady: Date
        var transfers: Int
        var meters: Double
        var rain: String?
        var isRecommended: Bool
        /// Whether this trip has a departure worth counting down to — a train
        /// or a bus in it, or an arrival time that was asked for. Riding off
        /// "now" has nothing to count to.
        var countsDown: Bool
        var legs: [Leg]

        var duration: TimeInterval { arrival.timeIntervalSince(leave) }
    }

    var origin: String
    var destination: String
    var computedAt: Date
    var options: [Option]
    /// The trip the countdown runs on — nil when no departure is fixed.
    var countdownID: String?
    /// Die Sprache, in der das Telefon gerade spricht. Die Uhr hat keine
    /// eigene Wahl — sie zeigt den Plan des Telefons, und dann auch in dessen
    /// Sprache. nil (ältere Fassung) heißt: wie die Uhr selbst eingestellt ist.
    var language: String?

    var countdown: Option? { countdownID.flatMap { id in options.first { $0.id == id } } }
    var recommended: Option? { options.first(where: \.isRecommended) }

    /// The categories present, in the phone's block order.
    var modes: [String] {
        var seen: [String] = []
        for o in options.sorted(by: { $0.modeRank < $1.modeRank }) where !seen.contains(o.mode) {
            seen.append(o.mode)
        }
        return seen
    }

    func options(in mode: String) -> [Option] { options.filter { $0.mode == mode } }

    func title(of mode: String) -> String { options(in: mode).first?.modeTitle ?? mode }
}


/// What the wrist picked, on its way back to the phone. Mode plus position,
/// not an id: every replan brings new ids, and "the second bike route"
/// survives a replan where an id does not.
struct WatchChoice: Codable, Equatable {
    var mode: String
    var index: Int
}
