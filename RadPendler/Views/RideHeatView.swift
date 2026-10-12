import MapKit
import SwiftUI

/// Die Heatmap: alle aufgezeichneten Fahrten auf einer Karte — die Straßen
/// nach Häufigkeit, die Ampeln nach Wartezeit — und darunter die Ampeln, an
/// denen am meisten Zeit liegen bleibt.
struct RideHeatView: View {
    @Environment(RideStore.self) private var store
    /// nil heißt: alle Verkehrsmittel.
    @State private var mode: TravelMode?
    @State private var heat: RideHeat?
    @State private var loaded = 0
    @State private var loading = 0
    @State private var focus: RideHeat.Signal?
    /// Straßennamen der Ampeln in der Liste, nachgeschlagen.
    @State private var names: [Int: String] = [:]

    static let modes = RideHeat.modes
    /// So viele Ampeln stehen in der Liste.
    static let listed = 8

    /// Was die Karte gerade zeigt — für die Legende.
    private var shown: [TravelMode] { mode.map { [$0] } ?? present }

    /// Die Tempofarben, die auf der Karte vorkommen: Rad und Auto haben
    /// verschiedene Skalen, sonst wäre das Auto überall dieselbe Farbe.
    private var scales: [(title: String, scale: RideColors.Scale)] {
        var out: [(String, RideColors.Scale)] = []
        for m in shown where !out.contains(where: { $0.1 == RideColors.Scale.of(m) }) {
            out.append((RideColors.Scale.of(m) == .bike ? L("Tempo Rad") : L("Tempo Auto"), .of(m)))
        }
        return out
    }

    private var present: [TravelMode] {
        Self.modes.filter { m in store.rides.contains { $0.travelMode == m } }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if present.count > 1 {
                    Picker(L("Verkehrsmittel"), selection: $mode) {
                        Text(L("Alle")).tag(TravelMode?.none)
                        ForEach(present) { Text($0.title).tag(TravelMode?.some($0)) }
                    }
                    .pickerStyle(.segmented)
                }
                map
                legend
                if let heat, !heat.signals.isEmpty { waits(heat) }
            }
            .padding(Theme.gutter)
        }
        .background(Theme.background)
        .navigationTitle(L("Heatmap"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: mode) { await load() }
    }

    @ViewBuilder private var map: some View {
        ZStack {
            if let heat {
                if heat.layers.first?.dots.isEmpty ?? true {
                    ContentUnavailableView(L("Keine Linien"), systemImage: "map",
                                           description: Text(L("Zu diesen Fahrten liegt auf diesem Gerät keine gefahrene Linie.")))
                } else {
                    HeatMap(heat: heat, focus: focus)
                }
            } else {
                ProgressView(loading > 0 ? L("%d von %d Fahrten", loaded, loading) : "")
                    .font(.system(size: 12, design: .rounded))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 420)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Größe = wie oft, Farbe = wie schnell (Nutzer, 12.10.2026).
            HStack(spacing: 6) {
                Text(L("selten"))
                ForEach([0.0, 0.5, 1], id: \.self) { f in
                    Circle().fill(.secondary).frame(width: 4 + 8 * f, height: 4 + 8 * f)
                }
                Text(L("oft"))
                Spacer(minLength: 0)
            }
            ForEach(scales, id: \.title) { entry in
                HStack(spacing: 6) {
                    SpeedLegend(scale: entry.scale)
                    Text(entry.title).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
            HStack(spacing: 12) {
                ForEach([10.0, 30, 60], id: \.self) { seconds in
                    HStack(spacing: 5) {
                        Circle().fill(Color(HeatMap.color(wait: seconds))).frame(width: 10, height: 10)
                        Text(Self.waitTitle(seconds))
                    }
                }
                Spacer(minLength: 0)
            }
            if let heat, heat.rides > 0 {
                Text(L("%d Fahrten · Kreis: je größer, desto öfter gehalten; Farbe: mittlere Wartezeit", heat.rides))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11, design: .rounded))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func waitTitle(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<HeatMap.shortWait: L("unter %d s", Int(HeatMap.shortWait))
        case ..<HeatMap.longWait: L("bis %d s", Int(HeatMap.longWait))
        default: L("länger")
        }
    }

    private func waits(_ heat: RideHeat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Wo die Zeit liegen bleibt"))
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.accent)
                .padding(.bottom, 6)
            ForEach(heat.signals.prefix(Self.listed)) { signal in
                Button {
                    focus = signal
                } label: {
                    HStack(spacing: 10) {
                        Circle().fill(Color(HeatMap.color(wait: signal.mean))).frame(width: 12, height: 12)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(names[signal.id] ?? L("Halt"))
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(Self.facts(signal))
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Text(Fmt.clock(signal.total))
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(L("Zeigt die Stelle auf der Karte"))
                Divider()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: heat.signals.first?.id) { await lookUpNames(heat) }
    }

    static func facts(_ signal: RideHeat.Signal) -> String {
        L("%d× gehalten · Ø %d s · längster %@", signal.stops, Int(signal.mean.rounded()), Fmt.clock(signal.longest))
    }

    /// Die Summe aller Fahrten liegt auf der Platte (`RideStore.heatSum`);
    /// gelesen und gerechnet wird nur, was seit dem letzten Mal dazukam. Der
    /// Wechsel des Verkehrsmittels ist dann nur noch ein Filter.
    private func load() async {
        heat = nil
        focus = nil
        names = [:]
        loaded = 0
        loading = 0
        let sum = await store.heatSum { done, of in
            loaded = done
            loading = of
        }
        let only = mode?.rawValue
        let built = await Task.detached(priority: .userInitiated) { sum.heat(only: only) }.value
        guard !Task.isCancelled else { return }
        heat = built
    }

    /// Eine Ampel ohne Namen ist eine Zahl auf einer Liste. Nachgeschlagen
    /// wird nur, was in der Liste steht, eine nach der anderen.
    private func lookUpNames(_ heat: RideHeat) async {
        for signal in heat.signals.prefix(Self.listed) where names[signal.id] == nil {
            if Task.isCancelled { return }
            let place = CLLocation(latitude: signal.coordinate.latitude, longitude: signal.coordinate.longitude)
            let mark = await Log.attemptAsync("Straße zur Ampel") {
                try await CLGeocoder().reverseGeocodeLocation(place).first
            }
            if let mark = mark ?? nil, let street = mark.thoroughfare ?? mark.name { names[signal.id] = street }
        }
    }
}

/// Die Karte dazu. `MKMapView` statt SwiftUIs `Map`: die Wolke ist eine
/// einzige Auflage mit eigenem Zeichner, dort wären es zehntausend Ansichten.
struct HeatMap: UIViewRepresentable {
    var heat: RideHeat
    /// Die Ampel, die in der Liste angetippt wurde.
    var focus: RideHeat.Signal?

    static let shortWait: TimeInterval = 20
    static let longWait: TimeInterval = 45

    static func color(wait seconds: TimeInterval) -> UIColor {
        seconds < shortWait ? .systemGreen : seconds < longWait ? .systemOrange : .systemRed
    }

    /// Die Wolke als eine Auflage: gezeichnet wird je Kachel, was in ihr liegt.
    final class Cloud: NSObject, MKOverlay {
        struct Level {
            /// Zellgröße in Kartenpunkten.
            var size: Double
            /// `weight` von 0 (eine Fahrt) bis 1 (das meistgefahrene Stück).
            var points: [(at: MKMapPoint, color: CGColor, weight: Double)]
        }

        let levels: [Level]
        let boundingMapRect: MKMapRect
        var coordinate: CLLocationCoordinate2D { MKMapPoint(x: boundingMapRect.midX, y: boundingMapRect.midY).coordinate }

        init(_ heat: RideHeat) {
            var bounds = MKMapRect.null
            levels = heat.layers.map { layer in
                let scale = layer.dots.first.map { MKMapPointsPerMeterAtLatitude($0.coordinate.latitude) } ?? 1
                // Das Seltene zuerst, damit das Häufige obenauf liegt.
                let dots = layer.dots.sorted { $0.rides < $1.rides }
                // Gemessen am dichtesten Punkt **dieses** Verkehrsmittels: drei
                // Autofahrten neben dreißig Radfahrten wären sonst Staub.
                let top = Dictionary(grouping: layer.dots, by: \.mode).mapValues { $0.map(\.rides).max() ?? 1 }
                return Level(size: layer.meters * scale, points: dots.map { dot in
                    let most = top[dot.mode] ?? layer.most
                    let weight = most > 1 ? (RideHeat.strength(dot.rides, most: most) - RideHeat.faintest) / (1 - RideHeat.faintest) : 1
                    let color = RideColors.Scale.of(TravelMode(rawValue: dot.mode)).uiColor(dot.kmh)
                    return (MKMapPoint(dot.coordinate), HeatMap.vivid(color).cgColor, weight)
                })
            }
            for p in levels.first?.points ?? [] {
                bounds = bounds.union(MKMapRect(x: p.at.x, y: p.at.y, width: 0, height: 0))
            }
            boundingMapRect = bounds
        }
    }

    /// Zeichnet die Wolke. Die Auflösung richtet sich nach dem Maßstab: die
    /// feinste, deren Zellen noch mindestens `minCell` Bildpunkte groß sind —
    /// darunter lägen die Punkte übereinander, und alles wäre gleich rot.
    final class CloudRenderer: MKOverlayRenderer {
        static let minCell = 3.0
        static let rim = UIColor.black.withAlphaComponent(0.45).cgColor
        /// Halbmesser eines Punkts, als Anteil der Zelle — und in Bildpunkten
        /// nie kleiner als das, sonst verschwindet eine einzelne Fahrt.
        static let dotSize = 0.22...0.62
        static let minRadius = 1.1...3.2

        override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
            guard let cloud = overlay as? Cloud, !cloud.levels.isEmpty else { return }
            let level = cloud.levels.first { $0.size * Double(zoomScale) >= Self.minCell } ?? cloud.levels[cloud.levels.count - 1]
            // Punkte mit Luft dazwischen: eine Spur ist eine Perlenkette, viele
            // Spuren nebeneinander eine Wolke. Bis hierher berührten sie sich
            // (0,62 der Zelle) und lasen sich als Strich (Nutzer, 12.10.2026).
            let largest = Swift.max(level.size * Self.dotSize.upperBound, Self.minRadius.upperBound / Double(zoomScale))
            let reach = mapRect.insetBy(dx: -largest, dy: -largest)
            for p in level.points where reach.contains(p.at) {
                let c = point(for: p.at)
                // Die Größe sagt, wie oft: von einem Staubkorn bis zu Punkten,
                // die sich berühren.
                let radius = Swift.max(level.size * Self.dotSize.at(p.weight),
                                       Self.minRadius.at(p.weight) / Double(zoomScale))
                let dot = CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)
                // Ein dunkler Saum: auf der hellen Karte ist Gelb sonst Papier.
                context.setFillColor(Self.rim)
                context.fillEllipse(in: dot.insetBy(dx: -radius * 0.22, dy: -radius * 0.22))
                context.setFillColor(p.color)
                context.fillEllipse(in: dot)
            }
        }
    }

    /// Dieselbe Farbe, satt und deckend: die Tempofarben sind für eine Linie
    /// auf der Karte gemacht, und als Punktwolke gingen sie auf ihr unter
    /// (Nutzer, 12.10.2026).
    static func vivid(_ color: UIColor) -> UIColor {
        var (h, s, b, a) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        guard color.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return color.withAlphaComponent(1) }
        return UIColor(hue: h, saturation: Swift.min(1, s * 1.25 + 0.1), brightness: Swift.min(1, b * 1.05), alpha: 1)
    }

    /// Ein Schleier über der ganzen Karte, unter der Wolke: die Karte tritt
    /// zurück, die Fahrten bleiben, wie sie sind.
    final class Veil: MKPolygon {}

    final class Pin: NSObject, MKAnnotation {
        let signal: RideHeat.Signal
        var coordinate: CLLocationCoordinate2D { signal.coordinate }
        var title: String? { RideHeatView.facts(signal) }
        var subtitle: String? { L("zusammen %@", Fmt.clock(signal.total)) }

        init(_ signal: RideHeat.Signal) { self.signal = signal }
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        // Gedämpft und ohne alles, was nicht Straße ist.
        let quiet = MKStandardMapConfiguration(emphasisStyle: .muted)
        quiet.pointOfInterestFilter = .excludingAll
        quiet.showsTraffic = false
        map.preferredConfiguration = quiet
        map.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: "signal")
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let c = context.coordinator
        // Nur neu aufbauen, wenn es andere Fahrten sind — nicht bei jedem
        // Tipp in die Liste.
        let mark = "\(heat.rides)|\(heat.layers.first?.dots.count ?? 0)|\(heat.signals.count)"
        if c.mark != mark {
            c.mark = mark
            map.removeOverlays(map.overlays)
            map.removeAnnotations(map.annotations)
            let cloud = Cloud(heat)
            let bounds = cloud.boundingMapRect
            let world = MKMapRect.world
            let corners = [world.origin, MKMapPoint(x: world.maxX, y: world.minY),
                           MKMapPoint(x: world.maxX, y: world.maxY), MKMapPoint(x: world.minX, y: world.maxY)]
            map.addOverlay(Veil(points: corners, count: corners.count), level: .aboveRoads)
            if !bounds.isNull { map.addOverlay(cloud, level: .aboveRoads) }
            map.addAnnotations(heat.signals.map(Pin.init))
            if !bounds.isNull {
                map.setVisibleMapRect(bounds, edgePadding: UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30),
                                      animated: false)
            }
        }
        if let focus, c.focused != focus.id,
           let pin = map.annotations.compactMap({ $0 as? Pin }).first(where: { $0.signal.id == focus.id }) {
            c.focused = focus.id
            map.setRegion(MKCoordinateRegion(center: pin.coordinate, latitudinalMeters: 500, longitudinalMeters: 500),
                          animated: true)
            map.selectAnnotation(pin, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var mark = ""
        var focused: Int?

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if overlay is Cloud { return CloudRenderer(overlay: overlay) }
            guard let veil = overlay as? Veil else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolygonRenderer(polygon: veil)
            // Hell wird heller, dunkel dunkler — in beiden Fällen blasser.
            renderer.fillColor = UIColor.systemBackground.withAlphaComponent(0.45)
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? Pin else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "signal", for: pin)
            // Je öfter gehalten, desto größer — aber nie so groß, dass die
            // Kreuzung darunter verschwindet.
            let side = Swift.min(30, 12 + 3 * CGFloat(pin.signal.stops).squareRoot() * 2)
            view.frame = CGRect(x: 0, y: 0, width: side, height: side)
            view.layer.cornerRadius = side / 2
            view.backgroundColor = HeatMap.color(wait: pin.signal.mean).withAlphaComponent(0.85)
            view.layer.borderColor = UIColor.white.cgColor
            view.layer.borderWidth = 1.5
            view.canShowCallout = true
            view.displayPriority = .defaultHigh
            view.isAccessibilityElement = true
            view.accessibilityLabel = pin.title
            return view
        }
    }
}

private extension ClosedRange where Bound == Double {
    /// Der Wert an der Stelle `f` zwischen 0 und 1.
    func at(_ f: Double) -> Double { lowerBound + (upperBound - lowerBound) * Swift.max(0, Swift.min(1, f)) }
}
