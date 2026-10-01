import Foundation

/// A quick choice for the start time: relative ("in 15 min") or a clock time
/// today or tomorrow ("um 8:00").
enum DeparturePreset: Hashable {
    case relative(Int)      // minutes from now
    case clock(Int, Int)    // hour, minute

    var title: String {
        switch self {
        case .relative(let m) where m < 60: L("in %d min", m)
        case .relative(let m) where m % 60 == 0: L("in %d h", m / 60)
        case .relative(let m): L("in %d h %d min", m / 60, m % 60)
        case .clock(let h, let m): m == 0 ? L("um %d Uhr", h) : L("um %d:%02d", h, m)
        }
    }

    /// The next moment this preset means, counted from `now`; a clock time that
    /// has passed today means tomorrow.
    func date(from now: Date = .now, calendar: Calendar = .current) -> Date {
        switch self {
        case .relative(let m):
            return now.addingTimeInterval(Double(m) * 60)
        case .clock(let h, let m):
            let today = calendar.date(bySettingHour: h, minute: m, second: 0, of: now) ?? now
            return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today) ?? today
        }
    }

    var stored: String {
        switch self {
        case .relative(let m): "r\(m)"
        case .clock(let h, let m): "c\(h):\(m)"
        }
    }

    init?(stored: String) {
        if stored.hasPrefix("r"), let m = Int(stored.dropFirst()) { self = .relative(m); return }
        if stored.hasPrefix("c") {
            let parts = stored.dropFirst().split(separator: ":").compactMap { Int($0) }
            if parts.count == 2 { self = .clock(parts[0], parts[1]); return }
        }
        return nil
    }

    static let choices: [DeparturePreset] = [.relative(5), .relative(10), .relative(15), .relative(30),
                                             .relative(60), .relative(120),
                                             .clock(6, 0), .clock(7, 0), .clock(8, 0), .clock(9, 0),
                                             .clock(12, 0), .clock(16, 0), .clock(17, 0), .clock(18, 0), .clock(20, 0)]
}
