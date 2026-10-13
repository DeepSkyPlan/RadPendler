import MapKit
import SwiftUI

/// Die ganze Route im Kleinen, unten links auf dem Fahrtbildschirm: die große
/// Karte folgt dem Fahrer und zeigt die nächsten paar hundert Meter — wo man
/// auf dem ganzen Weg ist, sieht man dort nicht. Ein Tipp schaltet weiter:
/// ganze Route → doppelt so nah, um den Fahrer → aus (Nutzer, 12.10.2026);
/// die Wahl bleibt über die Fahrt hinaus.
///
/// Eigene Ansicht, damit die Ortung je Sekunde nur dieses Kärtchen neu
/// aufbaut. Nach Norden, ohne Gesten, ohne Tempofarben: es ist ein Lageplan.
struct RideOverview: View {
    @Environment(RideTracker.self) private var tracker
    @AppStorage("rideOverviewMode") private var mode = Mode.route
    var side: CGFloat
    @State private var camera: MapCameraPosition = .automatic

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
            frame()
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
        Map(position: $camera, interactionModes: []) {
            // Was schon gefahren ist, grün wie auf der großen Karte — nach
            // einer Neuplanung beginnt die blaue Linie erst beim Fahrer.
            if ridden.count > 1 {
                MapPolyline(coordinates: ridden).stroke(.green, lineWidth: 3)
            }
            if route.count > 1 {
                MapPolyline(coordinates: route).stroke(.blue, lineWidth: 3)
            }
            if let end = route.last {
                Annotation("", coordinate: end) {
                    Circle().fill(.red).frame(width: 9, height: 9)
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                }
            }
            if let here {
                Annotation("", coordinate: here) {
                    Circle().fill(.green).frame(width: 13, height: 13)
                        .overlay(Circle().stroke(.white, lineWidth: 2.5))
                        .shadow(color: .black.opacity(0.4), radius: 2)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        // Der Tipp gehört dem Knopf darum, nicht der Karte.
        .allowsHitTesting(false)
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(.white.opacity(0.7), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        // Die ganze Route: der Ausschnitt ändert sich nur mit der Linie.
        // Nah: er wandert mit dem Fahrer, aber erst nach ein paar Metern —
        // nicht je Ortung.
        .onAppear { frame() }
        .onChange(of: Self.key(route)) { frame() }
        .onChange(of: here.map(Self.step)) {
            if mode == .near { frame() }
        }
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
    private func frame() {
        let whole = Self.whole(original: tracker.originalRoute, planned: tracker.plannedRoute,
                               ridden: tracker.meter.points.first?.coordinate, here: tracker.here)
        guard let rect = Self.rect(around: whole) else { return }
        camera = .rect(mode == .near ? Self.zoomed(rect, on: tracker.here) : rect)
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
