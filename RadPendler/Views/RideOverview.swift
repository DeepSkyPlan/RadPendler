import MapKit
import SwiftUI

/// Die ganze Route im Kleinen, unten links auf dem Fahrtbildschirm: die große
/// Karte folgt dem Fahrer und zeigt die nächsten paar hundert Meter — wo man
/// auf dem ganzen Weg ist, sieht man dort nicht. Ein Tipp klappt sie zu einem
/// Knopf zusammen und wieder auf; die Wahl bleibt über die Fahrt hinaus.
///
/// Eigene Ansicht, damit die Ortung je Sekunde nur dieses Kärtchen neu
/// aufbaut. Nach Norden, ohne Gesten, ohne Tempofarben: es ist ein Lageplan.
struct RideOverview: View {
    @Environment(RideTracker.self) private var tracker
    @AppStorage("rideOverviewCollapsed") private var collapsed = false
    var side: CGFloat
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { collapsed.toggle() }
        } label: {
            if collapsed { button } else { map }
        }
        .accessibilityLabel(collapsed ? L("Übersichtskarte ausklappen") : L("Übersichtskarte einklappen"))
        .accessibilityHint(L("Übersichtskarte: die ganze Route und wo du bist"))
    }

    private var button: some View {
        Image(systemName: "map")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(width: 36, height: 36)
            .background(.regularMaterial, in: Circle())
            .contentShape(Circle())
    }

    private var map: some View {
        let route = tracker.plannedRoute
        return Map(position: $camera, interactionModes: []) {
            if route.count > 1 {
                MapPolyline(coordinates: route).stroke(.blue, lineWidth: 3)
            }
            if let end = route.last {
                Annotation("", coordinate: end) {
                    Circle().fill(.red).frame(width: 9, height: 9)
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                }
            }
            if let here = tracker.here {
                Annotation("", coordinate: here) {
                    Circle().fill(.green).frame(width: 11, height: 11)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
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
        // Der Ausschnitt ändert sich nur mit der Linie — nicht je Ortung.
        .onAppear { frame(route) }
        .onChange(of: Self.key(route)) { frame(tracker.plannedRoute) }
    }

    /// Woran eine andere Linie zu erkennen ist, ohne sie Punkt für Punkt zu
    /// vergleichen.
    static func key(_ route: [CLLocationCoordinate2D]) -> String {
        "\(route.count)|\(route.first?.latitude ?? 0)|\(route.first?.longitude ?? 0)|\(route.last?.latitude ?? 0)"
    }

    private func frame(_ route: [CLLocationCoordinate2D]) {
        guard let rect = Self.rect(around: route + [tracker.here].compactMap { $0 }) else { return }
        camera = .rect(rect)
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
