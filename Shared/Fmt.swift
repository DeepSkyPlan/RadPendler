import Foundation

enum Fmt {
    static func time(_ d: Date) -> String {
        d.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    static func duration(_ t: TimeInterval) -> String {
        let m = Int((t / 60).rounded())
        return m < 60 ? "\(m) min" : String(format: "%d:%02d h", m / 60, m % 60)
    }

    static func km(_ meters: Double) -> String {
        meters < 1000 ? "\(Int(meters.rounded())) m"
            : (meters / 1000).formatted(.number.precision(.fractionLength(1))) + " km"
    }

    static func delay(_ t: TimeInterval) -> String? {
        let m = Int((t / 60).rounded())
        return m == 0 ? nil : (m > 0 ? "+\(m)" : "\(m)")
    }
}

extension Fmt {
    /// How old something is, in the shortest words that are still exact enough.
    /// The plan stamp on the map and the one on the watch read from here.
    static func age(_ seconds: TimeInterval) -> String {
        let s = Int(max(seconds, 0).rounded())
        if s < 60 { return "gerade eben" }
        let m = s / 60
        if m < 60 { return "vor \(m) min" }
        return m % 60 == 0 ? "vor \(m / 60) h" : String(format: "vor %d:%02d h", m / 60, m % 60)
    }
}

extension Fmt {
    /// A speed with one decimal — "21,3 km/h". Rides differ by tenths, and a
    /// rounded 21 says nothing about whether today was better than yesterday.
    static func kmh(_ kmh: Double) -> String {
        guard kmh.isFinite, kmh >= 0 else { return "– km/h" }
        return kmh.formatted(.number.precision(.fractionLength(1))) + " km/h"
    }

    /// A stopwatch, not a duration: "3:07", "1:12:40". Seconds matter while a
    /// ride is running, which is exactly where `duration` rounds them away.
    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(max(seconds, 0).rounded())
        return s < 3600 ? String(format: "%d:%02d", s / 60, s % 60)
                        : String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}
