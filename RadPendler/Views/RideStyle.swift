import SwiftUI
import UIKit

/// How a recorded ride is coloured. The line on the map is the ride's own
/// speedometer: red where it crawled, green where it ran.
///
/// Five steps, not a smooth ramp. A continuous gradient looks better on a
/// screenshot and reads worse on a street: one wants to see *where* the way
/// was slow, and five colours put a border at the place where that changed.
enum RideColors {
    /// Upper bound in km/h and the colour for everything under it. The steps
    /// are set around a commute on a city bike — 29 km/h rolling is this
    /// user's fast, not a racer's.
    static let steps: [(kmh: Double, color: UIColor)] = [
        (8, UIColor(red: 0.85, green: 0.16, blue: 0.20, alpha: 1)),   // standing or crawling
        (14, UIColor(red: 0.95, green: 0.55, blue: 0.10, alpha: 1)),  // traffic, bad surface
        (20, UIColor(red: 0.92, green: 0.78, blue: 0.11, alpha: 1)),  // normal city riding
        (26, UIColor(red: 0.29, green: 0.70, blue: 0.24, alpha: 1)),  // a good stretch
        (.infinity, UIColor(red: 0.00, green: 0.62, blue: 0.51, alpha: 1)), // free run
    ]

    static let titles = ["< 8", "8–14", "14–20", "20–26", "> 26"]

    /// A speed that is not a number is not a fast one: it lands in the
    /// slowest step rather than painting the line the colour of a free run.
    static func index(_ kmh: Double) -> Int {
        guard !kmh.isNaN else { return 0 }
        return steps.firstIndex { kmh < $0.kmh } ?? steps.count - 1
    }

    static func uiColor(_ kmh: Double) -> UIColor { steps[index(kmh)].color }
    static func color(_ kmh: Double) -> Color { Color(uiColor: uiColor(kmh)) }
}

/// The five colours with their ranges, small enough to sit in a corner of the
/// map. Without it the line is pretty and says nothing.
struct SpeedLegend: View {
    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(RideColors.steps.indices), id: \.self) { i in
                VStack(spacing: 1) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(RideColors.color(RideColors.steps[i].kmh - 1))
                        .frame(width: 20, height: 4)
                    Text(RideColors.titles[i])
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Text("km/h")
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.top, 5)
        }
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Farbskala der Geschwindigkeit, rot unter 8 bis grün über 26 km/h")
    }
}
