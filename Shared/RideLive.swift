import Foundation

/// A ride in progress, as the watch sees it: the numbers that fit on a wrist
/// and the two ends of the way. No coordinates and no line — the watch cannot
/// draw a map anyway, and the whole point of this struct is that it is small
/// enough to send once a second.
///
/// It is also what the wrist gets after the ride: `running` goes false and the
/// same numbers stand still as the summary.
struct RideLive: Codable, Equatable {
    var origin: String
    var destination: String
    /// `TravelMode.rawValue` of the trip being ridden.
    var mode: String
    var symbol: String
    var colorHex: String
    var started: Date
    /// When these numbers were taken. The watch shows their age instead of
    /// pretending a figure from two minutes ago is current.
    var at: Date
    var running: Bool
    var meters: Double
    /// Seconds actually in motion — the rest was spent standing.
    var movingSeconds: TimeInterval
    var currentKmh: Double
    var signalStops: Int
    var otherStops: Int
    var signalWaitTotal: TimeInterval

    /// Door to door, standing time included: the number one rides against.
    var seconds: TimeInterval { max(0, at.timeIntervalSince(started)) }
    var averageKmh: Double { seconds > 0 ? meters / seconds * 3.6 : 0 }
    var movingKmh: Double { movingSeconds > 0 ? meters / movingSeconds * 3.6 : 0 }
    var signalWaitAverage: TimeInterval {
        signalStops > 0 ? signalWaitTotal / Double(signalStops) : 0
    }
    var standingSeconds: TimeInterval { max(0, seconds - movingSeconds) }
}
