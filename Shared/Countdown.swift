import Foundation

/// The countdown's arithmetic and its colour ramp — shared by the phone and the
/// watch, so both say the same thing at the same minute.
///
/// Everything here counts against **getting ready** (departure minus the
/// preparation time), not against the departure itself: that is the moment one
/// can still act on.
enum Countdown {
    /// How much of a hurry it is in. The steps are the default alert minutes,
    /// so the colour changes at the same moments the app beeps.
    enum Urgency: String, Equatable, Codable {
        /// No fixed departure to count to.
        case idle
        /// More than half an hour — nothing to do.
        case plenty
        /// Half an hour down to the first warning.
        case soon
        /// Past the first warning at 10 min: time to wind up.
        case wrapUp
        /// Past the last warning at 5 min, or already overdue: get going.
        case go
        /// The trip has left.
        case gone

        /// sRGB components of the pill, top to bottom. Every step is dark
        /// enough to keep white text on it.
        var colors: [(Double, Double, Double)] {
            switch self {
            case .idle: [(0.5, 0.5, 0.5), (0.5, 0.5, 0.5)]
            case .plenty: [(0.11, 0.60, 0.31), (0.05, 0.44, 0.22)]
            case .soon: [(0.72, 0.48, 0.03), (0.54, 0.35, 0.02)]
            case .wrapUp: [(0.84, 0.35, 0.03), (0.64, 0.23, 0.02)]
            case .go: [(0.90, 0.16, 0.22), (0.76, 0.07, 0.16)]
            case .gone: [(0.45, 0.05, 0.09), (0.33, 0.03, 0.06)]
            }
        }

        /// The word above the number.
        var caption: String {
            switch self {
            case .idle: "KEINE ABFAHRT"
            case .gone: "ABGEFAHREN"
            case .go: "LOS"
            default: "LOS IN"
            }
        }
    }

    /// Green, amber, orange, red, dark red — counted against getting ready,
    /// so red means the door, not the platform.
    static func urgency(_ left: TimeInterval?, gone: Bool = false) -> Urgency {
        guard let left else { return .idle }
        if gone { return .gone }
        let minutes = left / 60
        if minutes > 30 { return .plenty }
        if minutes > 10 { return .soon }
        if minutes > 5 { return .wrapUp }
        return .go
    }

    /// Seconds below ten minutes, then round minutes, then hours.
    static func text(_ left: TimeInterval) -> String {
        let s = Int(left.rounded())
        guard s >= 0 else { return "jetzt" }
        if s < 600 { return String(format: "%d:%02d", s / 60, s % 60) }
        let m = s / 60
        return m < 60 ? "\(m) min" : String(format: "%d:%02d h", m / 60, m % 60)
    }
}
