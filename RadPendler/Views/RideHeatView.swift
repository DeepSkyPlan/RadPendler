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
    @State private var focus: RideHeat.Signal?
    /// Straßennamen der Ampeln in der Liste, nachgeschlagen.
    @State private var names: [Int: String] = [:]

    /// Was mit eigener Kraft oder eigenem Lenkrad gefahren wird. Eine reine
    /// Bahnfahrt hat keine Straße und keine Ampel.
    static let modes: [TravelMode] = [.bike, .bikeTransit, .car]
    /// So viele Ampeln stehen in der Liste.
    static let listed = 8

    private var rides: [Ride] {
        store.rides.filter { ride in
            guard let m = ride.travelMode, Self.modes.contains(m) else { return false }
            return mode == nil || m == mode
        }
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
                if heat.runs.isEmpty {
                    ContentUnavailableView(L("Keine Linien"), systemImage: "map",
                                           description: Text(L("Zu diesen Fahrten liegt auf diesem Gerät keine gefahrene Linie.")))
                } else {
                    HeatMap(heat: heat, focus: focus)
                }
            } else {
                ProgressView(L("%d von %d Fahrten", loaded, rides.count))
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
            HStack(spacing: 12) {
                ForEach(RideHeat.Level.allCases, id: \.self) { level in
                    HStack(spacing: 5) {
                        Capsule().fill(Color(HeatMap.color(level))).frame(width: 22, height: HeatMap.width(level))
                        Text(Self.title(level))
                    }
                }
                Spacer(minLength: 0)
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

    static func title(_ level: RideHeat.Level) -> String {
        switch level {
        case .once: L("einmal")
        case .often: L("öfter")
        case .most: L("meist")
        }
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
                            Text(names[signal.id] ?? L("Ampel"))
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
                .accessibilityHint(L("Zeigt die Ampel auf der Karte"))
                Divider()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: heat.signals.first?.id) { await lookUpNames(heat) }
    }

    static func facts(_ signal: RideHeat.Signal) -> String {
        L("%d× gehalten · Ø %d s · längster %@", signal.stops, Int(signal.mean.rounded()), Fmt.clock(signal.longest))
    }

    /// Die Linien nacheinander von der Platte, gerechnet wird daneben: bei
    /// dreihundert Fahrten sind das ein paar Sekunden, in denen die Ansicht
    /// bedienbar bleibt.
    private func load() async {
        heat = nil
        focus = nil
        names = [:]
        loaded = 0
        var tracks: [RideTrack] = []
        for ride in rides {
            if Task.isCancelled { return }
            if let track = await store.track(for: ride) { tracks.append(track) }
            loaded += 1
        }
        let all = tracks
        let built = await Task.detached(priority: .userInitiated) { RideHeat.build(all) }.value
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

/// Die Karte dazu. `MKMapView` statt SwiftUIs `Map`: ein paar tausend Stücke
/// Linie sind dort drei `MKMultiPolyline`, hier wären es ein paar tausend
/// Ansichten.
struct HeatMap: UIViewRepresentable {
    var heat: RideHeat
    /// Die Ampel, die in der Liste angetippt wurde.
    var focus: RideHeat.Signal?

    static let shortWait: TimeInterval = 20
    static let longWait: TimeInterval = 45

    static func color(_ level: RideHeat.Level) -> UIColor {
        switch level {
        case .once: .systemBlue.withAlphaComponent(0.55)
        case .often: .systemOrange
        case .most: .systemRed
        }
    }

    static func width(_ level: RideHeat.Level) -> CGFloat {
        switch level {
        case .once: 2.5
        case .often: 4
        case .most: 5.5
        }
    }

    static func color(wait seconds: TimeInterval) -> UIColor {
        seconds < shortWait ? .systemGreen : seconds < longWait ? .systemOrange : .systemRed
    }

    final class Lines: MKMultiPolyline {
        var level = RideHeat.Level.once
    }

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
        map.pointOfInterestFilter = .excludingAll
        map.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: "signal")
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let c = context.coordinator
        // Nur neu aufbauen, wenn es andere Fahrten sind — nicht bei jedem
        // Tipp in die Liste.
        let mark = "\(heat.rides)|\(heat.runs.count)|\(heat.signals.count)|\(heat.most)"
        if c.mark != mark {
            c.mark = mark
            map.removeOverlays(map.overlays)
            map.removeAnnotations(map.annotations)
            var bounds = MKMapRect.null
            for level in RideHeat.Level.allCases {
                let lines = heat.runs.filter { $0.level == level }
                    .map { MKPolyline(coordinates: $0.coordinates, count: $0.coordinates.count) }
                guard !lines.isEmpty else { continue }
                let overlay = Lines(lines)
                overlay.level = level
                // In dieser Reihenfolge: das Häufige liegt obenauf.
                map.addOverlay(overlay, level: .aboveRoads)
                bounds = bounds.union(overlay.boundingMapRect)
            }
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
            guard let lines = overlay as? Lines else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKMultiPolylineRenderer(multiPolyline: lines)
            r.strokeColor = HeatMap.color(lines.level)
            r.lineWidth = HeatMap.width(lines.level)
            r.lineCap = .round
            r.lineJoin = .round
            return r
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
