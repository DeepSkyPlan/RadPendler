import CoreLocation
import Foundation

/// One fix of a recorded ride. The names are short because a ride holds
/// thousands of them and every one of them is written out as JSON: "lat"
/// instead of "latitude" is a quarter of the file.
struct RidePoint: Codable, Equatable {
    var lat: Double
    var lon: Double
    var t: Date
    /// Metres per second — what the receiver said, or the step divided by its
    /// seconds where it said nothing.
    var v: Double

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    var kmh: Double { v * 3.6 }
}

/// A standstill long enough to be worth counting. Whether it was a red light
/// is decided here, once, against the lit junctions the route analysis found —
/// not later against whatever OpenStreetMap happens to say next month.
struct RideStop: Codable, Equatable, Identifiable {
    var id = UUID()
    var lat: Double
    var lon: Double
    var start: Date
    var seconds: TimeInterval
    var atSignal: Bool

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

/// The line and the stops of one ride. Kept apart from the summary on purpose:
/// a list of three hundred rides must not pull three hundred tracks into
/// memory to draw a table of dates and averages.
struct RideTrack: Codable, Equatable {
    var id: UUID
    var points: [RidePoint] = []
    var stops: [RideStop] = []

    var coordinates: [CLLocationCoordinate2D] { points.map(\.coordinate) }
}

/// A ride that happened, as the list remembers it. Everything here is a fact
/// that was measured; what can be derived from those facts is computed, so a
/// file written by an older version cannot disagree with itself.
struct Ride: Codable, Identifiable, Equatable {
    var id = UUID()
    var started: Date
    var ended: Date
    var origin: String
    var destination: String
    /// `TravelMode.rawValue` of the trip that was planned when the ride began.
    var mode: String
    var meters: Double
    var movingSeconds: TimeInterval
    var maxKmh: Double
    var signalStops: Int
    var otherStops: Int
    var signalWaitTotal: TimeInterval
    /// How long the plan said it would take, for the one comparison that is
    /// actually interesting: was the app right? nil when nothing was planned.
    var plannedSeconds: TimeInterval?
    var pointCount: Int = 0

    var seconds: TimeInterval { max(0, ended.timeIntervalSince(started)) }
    /// Door to door, standing time included.
    var averageKmh: Double { seconds > 0 ? meters / seconds * 3.6 : 0 }
    /// While rolling — the number that says how fast one rides, as opposed to
    /// how long the way takes.
    var movingKmh: Double { movingSeconds > 0 ? meters / movingSeconds * 3.6 : 0 }
    var standingSeconds: TimeInterval { max(0, seconds - movingSeconds) }
    var signalWaitAverage: TimeInterval {
        signalStops > 0 ? signalWaitTotal / Double(signalStops) : 0
    }
    var stops: Int { signalStops + otherStops }
    var travelMode: TravelMode? { TravelMode(rawValue: mode) }
    /// Minutes off the plan; negative means faster than announced.
    var deviationSeconds: TimeInterval? { plannedSeconds.map { seconds - $0 } }
}

// MARK: Grouping

extension Ride {
    /// The rides of one month, with the sums that make a month worth a heading.
    struct Month: Identifiable, Equatable {
        var id: String
        var title: String
        var rides: [Ride]

        var meters: Double { rides.reduce(0) { $0 + $1.meters } }
        var seconds: TimeInterval { rides.reduce(0) { $0 + $1.seconds } }
        var averageKmh: Double { seconds > 0 ? meters / seconds * 3.6 : 0 }
        var signalStops: Int { rides.reduce(0) { $0 + $1.signalStops } }
    }

    struct Year: Identifiable, Equatable {
        var id: Int
        var months: [Month]

        var rides: [Ride] { months.flatMap(\.rides) }
        var meters: Double { months.reduce(0) { $0 + $1.meters } }
        var seconds: TimeInterval { months.reduce(0) { $0 + $1.seconds } }
        var averageKmh: Double { seconds > 0 ? meters / seconds * 3.6 : 0 }
    }

    /// Years newest first, months within a year newest first, rides within a
    /// month newest first — a list one reads from the top downwards into the past.
    static func grouped(_ rides: [Ride], calendar: Calendar = .current) -> [Year] {
        var byYear: [Int: [Int: [Ride]]] = [:]
        for ride in rides {
            let parts = calendar.dateComponents([.year, .month], from: ride.started)
            guard let y = parts.year, let m = parts.month else { continue }
            byYear[y, default: [:]][m, default: []].append(ride)
        }
        return byYear.keys.sorted(by: >).map { y in
            Year(id: y, months: byYear[y]!.keys.sorted(by: >).map { m in
                Month(id: "\(y)-\(String(format: "%02d", m))",
                      title: monthName(m, calendar: calendar),
                      rides: byYear[y]![m]!.sorted { $0.started > $1.started })
            })
        }
    }

    static func monthName(_ month: Int, calendar: Calendar = .current) -> String {
        let names = calendar.standaloneMonthSymbols
        return names.indices.contains(month - 1) ? names[month - 1] : "\(month)"
    }
}
