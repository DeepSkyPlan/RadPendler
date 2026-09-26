import SwiftUI
import UIKit

/// How a recorded ride is coloured. The line on the map is the ride's own
/// speedometer: red where it crawled, green where it ran.
///
/// Five steps, not a smooth ramp. A continuous gradient looks better on a
/// screenshot and reads worse on a street: one wants to see *where* the way
/// was slow, and five colours put a border at the place where that changed.
enum RideColors {
    /// Die fünf Farben, von „steht" bis „läuft". Nur sie stehen fest; **wo**
    /// die Grenzen liegen, hängt davon ab, womit gefahren wird.
    static let palette: [UIColor] = [
        UIColor(red: 0.85, green: 0.16, blue: 0.20, alpha: 1),   // steht oder kriecht
        UIColor(red: 0.95, green: 0.55, blue: 0.10, alpha: 1),   // zäh
        UIColor(red: 0.92, green: 0.78, blue: 0.11, alpha: 1),   // normal
        UIColor(red: 0.29, green: 0.70, blue: 0.24, alpha: 1),   // gut
        UIColor(red: 0.00, green: 0.62, blue: 0.51, alpha: 1),   // freie Fahrt
    ]

    /// Die Grenzen dazu.
    ///
    /// Eine Skala von 8 bis 26 km/h ist für ein Stadtrad gemacht und für ein
    /// Auto sinnlos: dort ist **alles** tiefgrün, und die Linie sagt nichts
    /// mehr. Deshalb hängt die Skala am Verkehrsmittel — und im Rückblick auf
    /// eine gefahrene Fahrt an dem, was diese Fahrt wirklich hatte.
    struct Scale: Equatable {
        /// Vier Obergrenzen; darüber liegt die fünfte, offene Stufe.
        var bounds: [Double]

        static let bike = Scale(bounds: [8, 14, 20, 26])
        /// Auto und Bahn: Stadtverkehr, Landstraße, Schnellstraße, Autobahn.
        static let fast = Scale(bounds: [20, 50, 80, 100])

        static func of(_ mode: TravelMode?) -> Scale {
            switch mode {
            case .bike, .bikeTransit, .none: .bike
            case .car, .transit: .fast
            }
        }

        /// Auf eine gefahrene Fahrt zugeschnitten: vier gleiche Schritte
        /// zwischen dem langsamsten und dem schnellsten Stück. So trägt die
        /// Linie auch bei einer Fahrt Farbe, die nie über 15 km/h kam.
        static func fitted(to speeds: [Double], fallback: Scale = .bike) -> Scale {
            let moving = speeds.filter { $0.isFinite && $0 > 1 }.sorted()
            guard moving.count >= 10 else { return fallback }
            // Nicht das äußerste Prozent: ein einzelner Ausreißer des
            // Empfängers verschöbe sonst die ganze Skala.
            let low = moving[moving.count / 20]
            let high = moving[moving.count - 1 - moving.count / 20]
            guard high - low >= 4 else { return fallback }
            let step = (high - low) / 4
            return Scale(bounds: (1...4).map { (low + step * Double($0 - 1) + step).rounded() })
        }

        func index(_ kmh: Double) -> Int {
            guard !kmh.isNaN else { return 0 }
            return bounds.firstIndex { kmh < $0 } ?? bounds.count
        }

        func uiColor(_ kmh: Double) -> UIColor { palette[index(kmh)] }
        func color(_ kmh: Double) -> Color { Color(uiColor: uiColor(kmh)) }

        /// „< 8", „8–14", … „> 26" — die Beschriftung der Legende.
        var titles: [String] {
            var out = ["< \(Self.number(bounds[0]))"]
            for i in 1..<bounds.count { out.append("\(Self.number(bounds[i - 1]))–\(Self.number(bounds[i]))") }
            out.append("> \(Self.number(bounds[bounds.count - 1]))")
            return out
        }

        private static func number(_ v: Double) -> String { String(Int(v.rounded())) }
    }

    /// Solange nichts anderes gesagt wird, gilt das Rad — so war es immer.
    static func index(_ kmh: Double, scale: Scale = .bike) -> Int { scale.index(kmh) }
    static func uiColor(_ kmh: Double, scale: Scale = .bike) -> UIColor { scale.uiColor(kmh) }
    static func color(_ kmh: Double, scale: Scale = .bike) -> Color { scale.color(kmh) }
}

/// The five colours with their ranges, small enough to sit in a corner of the
/// map. Without it the line is pretty and says nothing.
struct SpeedLegend: View {
    var scale: RideColors.Scale = .bike

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(RideColors.palette.indices), id: \.self) { i in
                VStack(spacing: 1) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(uiColor: RideColors.palette[i]))
                        .frame(width: 20, height: 4)
                    Text(scale.titles[i])
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
        .accessibilityLabel(L("Farbskala der Geschwindigkeit, rot langsam bis grün schnell"))
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
