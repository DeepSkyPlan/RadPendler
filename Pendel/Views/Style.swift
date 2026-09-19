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
        case .walk: .systemGray
        case .bike: UIColor(red: 0.10, green: 0.62, blue: 0.25, alpha: 1)
        case .car: .systemOrange
        case .transit(_, let p):
            switch p {
            case .suburban: UIColor(red: 0.00, green: 0.55, blue: 0.31, alpha: 1)
            case .subway: UIColor(red: 0.07, green: 0.36, blue: 0.57, alpha: 1)
            case .tram: UIColor(red: 0.80, green: 0.04, blue: 0.13, alpha: 1)
            case .bus: UIColor(red: 0.58, green: 0.15, blue: 0.43, alpha: 1)
            case .ferry: UIColor(red: 0.00, green: 0.50, blue: 0.75, alpha: 1)
            case .express, .regional: UIColor(red: 0.89, green: 0.00, blue: 0.10, alpha: 1)
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
        case .bikeTransit: Color(red: 0.0, green: 0.55, blue: 0.45)
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
