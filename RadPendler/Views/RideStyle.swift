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
        .accessibilityLabel(L("Farbskala der Geschwindigkeit, rot unter 8 bis grün über 26 km/h"))
    }
}

extension RoadClass {
    /// Loud to quiet: the main road keeps the warning colour the car mode
    /// uses, the bike path the green the bike has everywhere else.
    var color: Color {
        switch self {
        case .main: Color(red: 0.89, green: 0.25, blue: 0.21)
        case .side: Color(red: 0.95, green: 0.65, blue: 0.13)
        case .cycleway: Color(red: 0.09, green: 0.65, blue: 0.29)
        case .path: Color(red: 0.42, green: 0.56, blue: 0.24)
        case .footway: Color(red: 0.36, green: 0.52, blue: 0.72)
        case .other: Color.secondary
        }
    }
}

/// How much of a route runs on what kind of road, as one bar and a legend.
///
/// The question it answers is the one a commuter actually asks about an
/// alternative: *wie viel davon ist Hauptstraße?* A number of kilometres does
/// not answer it; a bar does, at a glance, and the legend is there for the
/// times one wants the kilometres after all.
struct RoadMixBar: View {
    var mix: RoadMix
    /// Without the legend, for the places where a single line has to do.
    var compact = false

    private static let gap: CGFloat = 1.5

    var body: some View {
        if !mix.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                bar
                if !compact { legend }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(spoken))
        }
    }

    private var classes: [RoadClass] { mix.present }

    /// Drawn, not laid out. A `GeometryReader` here would read the width and
    /// hand it back to its children as a `frame(width:)`, and in a scrolling
    /// column that is a size negotiation SwiftUI has to settle every time —
    /// work in the layout pass, which is the one place that must stay cheap.
    /// A `Canvas` takes the size it is offered and paints.
    private var bar: some View {
        Canvas { context, size in
            let gaps = Self.gap * CGFloat(max(classes.count - 1, 0))
            let usable = max(size.width - gaps, 1)
            var x: CGFloat = 0
            for c in classes {
                // A stretch of eighty metres in a twenty-kilometre route is a
                // hairline, but leaving it out would be a lie about what the
                // bar adds up to.
                let w = max(2, usable * mix.share(c))
                context.fill(Path(roundedRect: CGRect(x: x, y: 0, width: w, height: size.height),
                                  cornerRadius: Swift.min(2.5, size.height / 2)),
                             with: .color(c.color))
                x += w + Self.gap
            }
        }
        .frame(height: compact ? 5 : 11)
    }

    private var legend: some View {
        HStack(spacing: 5) {
            ForEach(classes) { c in
                HStack(spacing: 3) {
                    Circle().fill(c.color).frame(width: 6, height: 6)
                    Text("\(c.title) \(Fmt.km(mix[c]))")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private var spoken: String {
        classes.map { "\($0.title) \(Fmt.km(mix[$0]))" }.joined(separator: ", ")
    }
}
