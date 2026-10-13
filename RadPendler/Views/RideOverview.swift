import MapKit
import SwiftUI

/// Die ganze Route im Kleinen, unten links auf dem Fahrtbildschirm: die große
/// Karte folgt dem Fahrer und zeigt die nächsten paar hundert Meter — wo man
/// auf dem ganzen Weg ist, sieht man dort nicht. Ein Tipp schaltet weiter:
/// ganze Route → doppelt so nah, um den Fahrer → aus (Nutzer, 12.10.2026);
/// die Wahl bleibt über die Fahrt hinaus.
///
/// Eigene Ansicht, damit die Ortung je Sekunde nur dieses Kärtchen neu
/// aufbaut. Nach Norden, ohne Gesten, ohne Tempofarben: es ist ein Lageplan —
/// mit dem Regenradar von jetzt darüber (Nutzer, 13.10.2026): die große Karte
/// zeigt die nächste Kreuzung, ob auf dem Rest der Strecke ein Schauer steht,
/// sieht man nur von weitem.
struct RideOverview: View {
    @Environment(RideTracker.self) private var tracker
    @AppStorage("rideOverviewMode") private var mode = Mode.route
    var side: CGFloat
    /// Das Radarbild, das gerade auf der Karte liegt.
    @State private var radar = RideOverview.radarFrame()

    enum Mode: String, CaseIterable {
        /// Die ganze Route.
        case route
        /// Doppelt so nah, mit dem Fahrer in der Mitte.
        case near
        /// Nur der Knopf.
        case off

        var next: Mode {
            let all = Self.allCases
            return all.firstIndex(of: self).map { all[($0 + 1) % all.count] } ?? self
        }

        var title: String {
            switch self {
            case .route: L("ganze Route")
            case .near: L("doppelt so nah")
            case .off: L("aus")
            }
        }
    }

    var body: some View {
        // Hier gelesen und nicht erst im Inhalt der Karte: `Map` wertet seinen
        // Inhalt außerhalb dieser Ansicht aus, und was nur dort gelesen wird,
        // meldet sich bei SwiftUI nie als Änderung. Bis 1.20 blieb der grüne
        // Punkt deshalb am Start stehen (Nutzer, 12.10.2026).
        let here = tracker.here
        let route = tracker.plannedRoute
        let ridden = Self.sparse(tracker.meter.points)
        return Button {
            withAnimation(.snappy(duration: 0.2)) { mode = mode.next }
        } label: {
            if mode == .off { button } else { map(route, ridden: ridden, here: here) }
        }
        .accessibilityLabel(L("Übersichtskarte: %@", mode.title))
        .accessibilityHint(L("Tippen für %@", mode.next.title))
    }

    private var button: some View {
        Image(systemName: "map")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(width: 36, height: 36)
            .background(.regularMaterial, in: Circle())
            .contentShape(Circle())
    }

    private func map(_ route: [CLLocationCoordinate2D], ridden: [CLLocationCoordinate2D],
                     here: CLLocationCoordinate2D?) -> some View {
        OverviewMap(route: route, ridden: ridden, here: here, rect: rect(), radar: radar, follows: mode == .near)
            // Der Tipp gehört dem Knopf darum, nicht der Karte.
            .allowsHitTesting(false)
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(.white.opacity(0.7), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            // Der Regen von jetzt: alle fünf Minuten gibt es ein neues Bild.
            .task {
                while !Task.isCancelled {
                    radar = Self.radarFrame()
                    try? await Task.sleep(for: .seconds(60))
                }
            }
    }

    /// Das Radarbild, das jetzt gilt: der letzte volle Fünf-Minuten-Schritt.
    static func radarFrame(at now: Date = .now) -> Date {
        Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 300).rounded(.down) * 300)
    }

    /// Die Lage auf rund zehn Meter: so oft wandert der nahe Ausschnitt mit.
    static func step(_ c: CLLocationCoordinate2D) -> String {
        "\(Int(c.latitude * 10_000))|\(Int(c.longitude * 10_000))"
    }

    /// Woran eine andere Linie zu erkennen ist, ohne sie Punkt für Punkt zu
    /// vergleichen.
    static func key(_ route: [CLLocationCoordinate2D]) -> String {
        "\(route.count)|\(route.first?.latitude ?? 0)|\(route.first?.longitude ?? 0)|\(route.last?.latitude ?? 0)"
    }

    /// Immer die **ganze** Fahrt — von dort, wo sie begann, bis zum Ziel —
    /// oder der nahe Ausschnitt davon. Bis 1.21 nur die Linie, die gerade
    /// galt: nach einer Neuplanung unterwegs begann sie beim Fahrer, und die
    /// Übersicht zeigte nur noch den Rest (Nutzer, 13.10.2026).
    private func rect() -> MKMapRect? {
        let whole = Self.whole(original: tracker.originalRoute, planned: tracker.plannedRoute,
                               ridden: tracker.meter.points.first?.coordinate, here: tracker.here)
        guard let rect = Self.rect(around: whole) else { return nil }
        return mode == .near ? Self.zoomed(rect, on: tracker.here) : rect
    }

    /// Alles, was ins Bild muss: die ursprüngliche Linie, die jetzt gültige,
    /// wo die Aufzeichnung begann und wo der Fahrer ist.
    static func whole(original: [CLLocationCoordinate2D], planned: [CLLocationCoordinate2D],
                      ridden: CLLocationCoordinate2D?, here: CLLocationCoordinate2D?) -> [CLLocationCoordinate2D] {
        original + planned + [ridden, here].compactMap { $0 }
    }

    /// Die gefahrene Linie in höchstens `most` Punkten: für ein Kärtchen von
    /// der Größe eines Daumens reicht das, und es wird je Ortung neu gebaut.
    static func sparse(_ points: [RidePoint], most: Int = 150) -> [CLLocationCoordinate2D] {
        guard points.count > most else { return points.map(\.coordinate) }
        let step = (points.count + most - 1) / most
        var out = stride(from: 0, to: points.count, by: step).map { points[$0].coordinate }
        if let last = points.last { out.append(last.coordinate) }
        return out
    }

    /// Derselbe Ausschnitt in halber Kantenlänge, um den Fahrer herum. Ohne
    /// Ortung um die Mitte.
    static func zoomed(_ rect: MKMapRect, on here: CLLocationCoordinate2D?, by factor: Double = 2) -> MKMapRect {
        let centre = here.map { MKMapPoint($0) } ?? MKMapPoint(x: rect.midX, y: rect.midY)
        let (w, h) = (rect.width / factor, rect.height / factor)
        return MKMapRect(x: centre.x - w / 2, y: centre.y - h / 2, width: w, height: h)
    }

    /// Der Ausschnitt um alle Punkte, mit einem Rand — und nie kleiner als
    /// ein paar hundert Meter, sonst zeigt eine kurze Linie eine Hauswand.
    static func rect(around points: [CLLocationCoordinate2D]) -> MKMapRect? {
        guard !points.isEmpty else { return nil }
        var rect = MKMapRect.null
        for c in points {
            let p = MKMapPoint(c)
            rect = rect.union(MKMapRect(x: p.x, y: p.y, width: 0, height: 0))
        }
        let least = 300 * MKMapPointsPerMeterAtLatitude(points[0].latitude)
        let pad = Swift.max(rect.width, rect.height, least) * 0.12
        let grow = Swift.max(0, least - Swift.min(rect.width, rect.height)) / 2
        return rect.insetBy(dx: -(pad + (rect.width < least ? grow : 0)), dy: -(pad + (rect.height < least ? grow : 0)))
    }
}

/// Die Karte der Übersicht. `MKMapView` statt SwiftUIs `Map`, weil das Radar
/// eine Kachelauflage ist und `Map` keine zeigen kann.
struct OverviewMap: UIViewRepresentable {
    var route: [CLLocationCoordinate2D]
    var ridden: [CLLocationCoordinate2D]
    var here: CLLocationCoordinate2D?
    var rect: MKMapRect?
    /// Zeit des Radarbilds.
    var radar: Date
    /// Der Ausschnitt wandert mit dem Fahrer — dann gleitend.
    var follows: Bool

    final class Line: MKPolyline { var ridden = false }
    final class Dot: MKPointAnnotation { var end = false }

    /// Sagt Bescheid, sobald die Karte eine Größe hat: vorher geht ein
    /// Ausschnitt verloren, und das Kärtchen stünde auf ganz Europa.
    final class SizedMap: MKMapView {
        var onSize: (() -> Void)?
        private var sized = false

        override func layoutSubviews() {
            super.layoutSubviews()
            guard !sized, bounds.width > 0 else { return }
            sized = true
            onSize?()
        }
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = SizedMap()
        map.onSize = { [weak map, coordinator = context.coordinator] in
            if let map { coordinator.fit(map) }
        }
        map.delegate = context.coordinator
        map.isUserInteractionEnabled = false
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: "dot")
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) { context.coordinator.update(map, self) }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var routeKey = ""
        private var riddenKey = ""
        private var rectKey = ""
        private var radar: RadarTileOverlay?
        private var end: Dot?
        private var rider: Dot?

        func update(_ map: MKMapView, _ view: OverviewMap) {
            // Das Radar zuunterst, die Linien darüber.
            if radar?.time != view.radar {
                if let radar { map.removeOverlay(radar) }
                let overlay = RadarTileOverlay(time: view.radar)
                radar = overlay
                map.insertOverlay(overlay, at: 0, level: .aboveRoads)
            }
            let key = RideOverview.key(view.route)
            if key != routeKey {
                routeKey = key
                map.removeOverlays(map.overlays.filter { ($0 as? Line)?.ridden == false })
                if view.route.count > 1 {
                    map.addOverlay(Line(coordinates: view.route, count: view.route.count), level: .aboveRoads)
                }
                if let last = view.route.last {
                    let dot = end ?? Dot()
                    dot.end = true
                    dot.coordinate = last
                    if end == nil { map.addAnnotation(dot); end = dot }
                }
            }
            // Die gefahrene Linie wächst je Ortung; neu gezeichnet wird sie
            // erst, wenn man es auf dem Kärtchen sähe.
            let grown = "\(view.ridden.count)|" + (view.ridden.last.map(RideOverview.step) ?? "")
            if grown != riddenKey {
                riddenKey = grown
                map.removeOverlays(map.overlays.filter { ($0 as? Line)?.ridden == true })
                if view.ridden.count > 1 {
                    let line = Line(coordinates: view.ridden, count: view.ridden.count)
                    line.ridden = true
                    map.addOverlay(line, level: .aboveRoads)
                }
            }
            if let here = view.here {
                let dot = rider ?? Dot()
                dot.coordinate = here
                if rider == nil { map.addAnnotation(dot); rider = dot }
            } else if let rider {
                map.removeAnnotation(rider)
                self.rider = nil
            }
            wanted = view.rect
            follows = view.follows
            fit(map)
        }

        private var wanted: MKMapRect?
        private var follows = false

        func fit(_ map: MKMapView) {
            guard let rect = wanted, map.bounds.width > 0 else { return }
            // Auf rund zehn Meter: der nahe Ausschnitt wandert mit, aber
            // nicht je Ortung um einen halben Bildpunkt.
            let now = "\(Int(rect.midX / 100))|\(Int(rect.midY / 100))|\(Int(rect.width / 100))"
            guard now != rectKey else { return }
            let first = rectKey.isEmpty
            rectKey = now
            map.setVisibleMapRect(rect, animated: follows && !first)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tiles = overlay as? RadarTileOverlay {
                let r = MKTileOverlayRenderer(tileOverlay: tiles)
                r.alpha = 0.7
                return r
            }
            guard let line = overlay as? Line else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKPolylineRenderer(polyline: line)
            r.strokeColor = line.ridden ? .systemGreen : .systemBlue
            r.lineWidth = 3
            r.lineCap = .round
            r.lineJoin = .round
            return r
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let dot = annotation as? Dot else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "dot", for: dot)
            let side: CGFloat = dot.end ? 10 : 14
            view.frame = CGRect(x: 0, y: 0, width: side, height: side)
            view.layer.cornerRadius = side / 2
            view.backgroundColor = dot.end ? .systemRed : .systemGreen
            view.layer.borderColor = UIColor.white.cgColor
            view.layer.borderWidth = dot.end ? 1.5 : 2.5
            view.displayPriority = .required
            view.zPriority = dot.end ? .defaultUnselected : .max
            view.canShowCallout = false
            return view
        }
    }
}
