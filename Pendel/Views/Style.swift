import SwiftUI
import UIKit

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

extension LegKind {
    var uiColor: UIColor {
        switch self {
        // Bike green, car red, bus orange, everything on rails blue — the
        // family a leg belongs to is readable before the label is.
        case .walk: .systemGray
        case .bike: UIColor(red: 0.09, green: 0.65, blue: 0.29, alpha: 1)
        case .car: UIColor(red: 0.89, green: 0.11, blue: 0.18, alpha: 1)
        case .transit(_, let p):
            switch p {
            case .suburban: UIColor(red: 0.04, green: 0.52, blue: 1.00, alpha: 1)
            case .subway: UIColor(red: 0.04, green: 0.24, blue: 0.57, alpha: 1)
            case .express, .regional: UIColor(red: 0.29, green: 0.42, blue: 0.85, alpha: 1)
            case .tram: UIColor(red: 0.45, green: 0.55, blue: 0.95, alpha: 1)
            case .ferry: UIColor(red: 0.00, green: 0.63, blue: 0.78, alpha: 1)
            case .bus: UIColor(red: 0.95, green: 0.55, blue: 0.10, alpha: 1)
            }
        }
    }

    var color: Color { Color(uiColor: uiColor) }

    var symbol: String {
        switch self {
        case .walk: "figure.walk"
        case .bike: "bicycle"
        case .car: "car.fill"
        case .transit(_, let p):
            switch p {
            case .bus: "bus.fill"
            case .tram: "tram.fill"
            case .ferry: "ferry.fill"
            case .subway: "tram.tunnel.fill"
            default: "train.side.front.car"
            }
        }
    }
}

extension TravelMode {
    var color: Color {
        switch self {
        case .bike: LegKind.bike.color
        // A blue-leaning green: it has to read apart from the S-Bahn green
        // (#008C4F) it sits next to and from the ferry blue (#0080BF) — #00A8BA,
        // bluer than the #00ADA3 it replaces (user, 20.09.).
        case .bikeTransit: Color(uiColor: UIColor(red: 0.00, green: 0.66, blue: 0.73, alpha: 1))
        case .transit: LegKind.transit(line: "", product: .suburban).color
        case .car: LegKind.car.color
        }
    }
}

extension RainLevel {
    var color: Color {
        switch self {
        case .dry: .secondary
        case .possible: .teal
        case .light: .blue
        case .rain, .heavy: .indigo
        }
    }
}

/// The legs of an option as icons with their distances: bike → S7 → bike.
struct LegChainView: View {
    var option: TripOption
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 3 : 5) {
            ForEach(Array(merged.enumerated()), id: \.offset) { i, leg in
                if i > 0, leg.isTransit, merged[i - 1].isTransit {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.system(size: compact ? 8 : 10, weight: .bold))
                        .foregroundStyle(.red)
                        .accessibilityLabel("umsteigen")
                }
                HStack(spacing: 2) {
                    if leg.isTransit {
                        LineBadge(leg: leg)
                    } else {
                        Image(systemName: leg.kind.symbol)
                            .font(.caption).foregroundStyle(leg.kind.color)
                    }
                    if let m = leg.length, m >= 50 || !leg.isTransit {
                        Text(Fmt.km(m)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Short walks between two trains are just the change; they keep their own
    /// icon only when they are a real walk (≥ 150 m).
    private var merged: [Leg] {
        option.legs.filter { $0.kind != .walk || ($0.length ?? 0) >= 150 }
    }
}

/// Coloured capsule with a transit line name, e.g. "S7".
struct LineBadge: View {
    var leg: Leg

    var body: some View {
        Text(leg.lineName ?? "")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(leg.kind.color, in: RoundedRectangle(cornerRadius: 4))
    }
}
