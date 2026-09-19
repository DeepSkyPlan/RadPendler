import MapKit
import SwiftUI

/// MKMapView wrapper: SwiftUI's `Map` cannot show tile overlays, and the radar is one.
struct RouteMapView: UIViewRepresentable {
    var options: [TripOption]
    var selectedID: TripOption.ID?
    var radarFrames: [Date]
    /// Frame on screen; nil hides the radar.
    var radarTime: Date?
    /// Tap on an option's label on the map.
    var onSelect: ((TripOption.ID) -> Void)? = nil

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = true
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "pin")
        map.register(OptionLabelView.self, forAnnotationViewWithReuseIdentifier: "label")
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.update(map, self)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class LegLine: MKPolyline {
        var kind: LegKind = .walk
        var emphasized = true
    }

    final class Pin: MKPointAnnotation {
        var tint: UIColor = .systemGreen
        var glyph: String = "mappin"
        var isRider = false
    }

    /// Duration and transfers of one option, placed on its route.
    final class OptionLabel: MKPointAnnotation {
        var optionID: TripOption.ID?
        var symbol = "bicycle"
        var text = ""
        var color: UIColor = .systemGray
        var selected = false
    }

    final class OptionLabelView: MKAnnotationView {
        private let icon = UIImageView()
        private let label = UILabel()

        override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
            super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
            let stack = UIStackView(arrangedSubviews: [icon, label])
            stack.spacing = 4
            stack.alignment = .center
            stack.isLayoutMarginsRelativeArrangement = true
            stack.layoutMargins = UIEdgeInsets(top: 3, left: 6, bottom: 3, right: 7)
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
                stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            icon.contentMode = .scaleAspectFit
            icon.preferredSymbolConfiguration = .init(pointSize: 11, weight: .semibold)
            layer.cornerRadius = 9
            layer.borderWidth = 1.5
            collisionMode = .rectangle
        }

        required init?(coder: NSCoder) { fatalError() }

        func configure(_ a: OptionLabel) {
            icon.image = UIImage(systemName: a.symbol)
            label.text = a.text
            let fg: UIColor = a.selected ? .white : .secondaryLabel
            icon.tintColor = fg
            label.textColor = fg
            backgroundColor = a.selected ? a.color : .systemBackground.withAlphaComponent(0.92)
            layer.borderColor = (a.selected ? a.color : UIColor.systemGray3).cgColor
            displayPriority = a.selected ? .required : .defaultHigh
            zPriority = a.selected ? .max : .defaultUnselected
            let size = systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            frame.size = size
            centerOffset = .zero
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onSelect: ((TripOption.ID) -> Void)?
        private var routeKey = ""
        private var planKey = ""
        private var radar: [Date: RadarTileOverlay] = [:]
        private var renderers: [Date: MKTileOverlayRenderer] = [:]
        private var shownRadar: Date?
        private var rider: Pin?

        func update(_ map: MKMapView, _ view: RouteMapView) {
            onSelect = view.onSelect
            // New plan → redraw and fit; new selection only → redraw.
            let plan = view.options.map { $0.id.uuidString }.joined()
            let key = plan + (view.selectedID?.uuidString ?? "")
            if key != routeKey {
                routeKey = key
                drawRoutes(map, view)
                if plan != planKey {
                    planKey = plan
                    zoomToRoutes(map, view)
                }
            }
            updateRadar(map, view)
            updateRider(map, view)
        }

        private func drawRoutes(_ map: MKMapView, _ view: RouteMapView) {
            map.removeOverlays(map.overlays.filter { $0 is LegLine })
            map.removeAnnotations(map.annotations.compactMap { $0 as? Pin }.filter { !$0.isRider })
            map.removeAnnotations(map.annotations.filter { $0 is OptionLabel })
            let selected = view.options.first { $0.id == view.selectedID }
            // Unselected options faint underneath, the selected one on top.
            let ordered = view.options.filter { $0.id != selected?.id } + (selected.map { [$0] } ?? [])
            for option in ordered {
                for leg in option.legs where leg.coordinates.count > 1 {
                    let line = LegLine(coordinates: leg.coordinates, count: leg.coordinates.count)
                    line.kind = leg.kind
                    line.emphasized = selected == nil || option.id == selected?.id
                    map.addOverlay(line, level: .aboveRoads)
                }
            }
            addLabels(map, view.options, selected: selected?.id)
            guard let trip = selected ?? view.options.first, let first = trip.legs.first, let last = trip.legs.last else { return }
            var pins: [Pin] = []
            let start = Pin(); start.coordinate = first.coordinates.first ?? CLLocationCoordinate2D()
            start.title = first.fromName; start.tint = .systemGreen; start.glyph = "figure.stand"
            pins.append(start)
            let end = Pin(); end.coordinate = last.coordinates.last ?? CLLocationCoordinate2D()
            end.title = last.toName; end.tint = .systemRed; end.glyph = "flag.checkered"
            pins.append(end)
            for leg in trip.legs where leg.isTransit {
                let p = Pin(); p.coordinate = leg.coordinates.first ?? CLLocationCoordinate2D()
                p.title = "\(leg.lineName ?? "") \(Fmt.time(leg.departure))"
                p.subtitle = leg.fromName
                p.tint = leg.kind.uiColor; p.glyph = leg.kind.symbol
                pins.append(p)
            }
            map.addAnnotations(pins)
        }

        /// One label per option, spread along each route (35 %…65 % of its length)
        /// so that options sharing a track do not stack their labels.
        private func addLabels(_ map: MKMapView, _ options: [TripOption], selected: TripOption.ID?) {
            guard options.count > 1 else { return }
            for (i, o) in options.enumerated() {
                let path = o.legs.flatMap(\.coordinates)
                guard path.count > 1 else { continue }
                let f = 0.35 + 0.3 * Double(i) / Double(max(options.count - 1, 1))
                let span = o.arrival.timeIntervalSince(o.leave)
                guard let c = RainSampler.position(on: path, departure: o.leave, arrival: o.arrival,
                                                   at: o.leave.addingTimeInterval(span * f)) else { continue }
                let a = OptionLabel()
                a.coordinate = c
                a.optionID = o.id
                a.symbol = o.mode.symbol
                a.text = Self.labelText(o)
                a.color = UIColor(o.mode.color)
                a.selected = o.id == selected
                map.addAnnotation(a)
            }
        }

        static func labelText(_ o: TripOption) -> String {
            let d = Fmt.duration(o.duration)
            guard !o.transitLegs.isEmpty else { return d }
            return o.transfers == 0 ? "\(d) · direkt" : "\(d) · \(o.transfers)× um"   // short form of transferText
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            guard let label = annotation as? OptionLabel, let id = label.optionID else { return }
            mapView.deselectAnnotation(annotation, animated: false)
            onSelect?(id)
        }

        private func zoomToRoutes(_ map: MKMapView, _ view: RouteMapView) {
            let rects = map.overlays.compactMap { ($0 as? LegLine)?.boundingMapRect }
            guard let first = rects.first else { return }
            // Before the first layout the map has no size and the fit is lost.
            guard map.bounds.width > 0 else {
                DispatchQueue.main.async { [weak self, weak map] in
                    if let self, let map { self.zoomToRoutes(map, view) }
                }
                return
            }
            let all = rects.dropFirst().reduce(first) { $0.union($1) }
            // Bottom inset clears the radar controls floating over the map.
            map.setVisibleMapRect(all, edgePadding: UIEdgeInsets(top: 50, left: 30, bottom: 110, right: 30), animated: false)
        }

        /// All frames stay on the map once loaded; only the shown one is
        /// visible. Swapping overlays per frame would reload tiles and flicker.
        private func updateRadar(_ map: MKMapView, _ view: RouteMapView) {
            guard let time = view.radarTime else {
                renderers.values.forEach { $0.alpha = 0 }
                shownRadar = nil
                return
            }
            let wanted = Set(view.radarFrames)
            for (t, overlay) in radar where !wanted.contains(t) {
                map.removeOverlay(overlay)
                radar[t] = nil
                renderers[t] = nil
            }
            for t in view.radarFrames where radar[t] == nil {
                let o = RadarTileOverlay(time: t)
                radar[t] = o
                map.insertOverlay(o, at: 0, level: .aboveRoads)
            }
            if shownRadar != time {
                shownRadar = time
                for (t, r) in renderers { r.alpha = t == time ? 0.7 : 0 }
            }
        }

        /// Where the rider would be at the radar frame's time on the selected trip.
        private func updateRider(_ map: MKMapView, _ view: RouteMapView) {
            let trip = view.options.first { $0.id == view.selectedID }
            var position: CLLocationCoordinate2D?
            var onBike = false
            if let time = view.radarTime, let trip {
                for leg in trip.legs {
                    if let p = RainSampler.position(on: leg.coordinates, departure: leg.departure,
                                                    arrival: leg.arrival, at: time) {
                        position = p
                        onBike = leg.kind == .bike
                        break
                    }
                }
            }
            guard let position else {
                if let rider { map.removeAnnotation(rider); self.rider = nil }
                return
            }
            if rider == nil {
                let p = Pin(); p.isRider = true; p.title = "Du"
                rider = p
                map.addAnnotation(p)
            }
            rider?.coordinate = position
            rider?.glyph = onBike ? "bicycle" : "person.fill"
            rider?.tint = .systemPurple
            if let rider, let v = map.view(for: rider) as? MKMarkerAnnotationView {
                v.glyphImage = UIImage(systemName: rider.glyph)
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let line = overlay as? LegLine {
                let r = MKPolylineRenderer(polyline: line)
                // Other options grey underneath, the chosen one in colour on top.
                r.strokeColor = line.emphasized ? line.kind.uiColor.withAlphaComponent(0.95)
                                                : UIColor.systemGray.withAlphaComponent(0.55)
                r.lineWidth = line.emphasized ? 5 : 4
                if line.kind == .walk { r.lineDashPattern = [2, 6] }
                r.lineCap = .round
                return r
            }
            if let tiles = overlay as? RadarTileOverlay {
                let r = MKTileOverlayRenderer(tileOverlay: tiles)
                r.alpha = tiles.time == shownRadar ? 0.7 : 0
                renderers[tiles.time] = r
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let label = annotation as? OptionLabel {
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: "label", for: label) as! OptionLabelView
                v.configure(label)
                return v
            }
            guard let pin = annotation as? Pin else { return nil }
            let v = mapView.dequeueReusableAnnotationView(withIdentifier: "pin", for: pin) as! MKMarkerAnnotationView
            v.markerTintColor = pin.tint
            v.glyphImage = UIImage(systemName: pin.glyph)
            v.displayPriority = pin.isRider ? .required : .defaultHigh
            v.titleVisibility = pin.isRider ? .visible : .adaptive
            v.zPriority = pin.isRider ? .max : .defaultUnselected
            return v
        }
    }
}

/// Play/pause and scrubber for the radar frames.
struct RadarControls: View {
    var frames: [Date]
    @Binding var index: Int
    @Binding var visible: Bool
    @State private var playing = false

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: $visible) { Image(systemName: "cloud.rain") }
                .toggleStyle(.button)
                .accessibilityLabel("Regenradar")
            if visible, !frames.isEmpty {
                Button { playing.toggle() } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                }
                .accessibilityLabel(playing ? "Anhalten" : "Abspielen")
                Slider(value: Binding(get: { Double(index) }, set: { index = Int($0.rounded()) }),
                       in: 0...Double(max(frames.count - 1, 1)), step: 1)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(Fmt.time(frames[min(index, frames.count - 1)]))
                        .font(.callout.monospacedDigit().weight(.semibold))
                    Text(frames[min(index, frames.count - 1)] > .now ? "Vorhersage" : "gemessen")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .frame(width: 72, alignment: .trailing)
            } else {
                Text("Regenradar (DWD)").font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .task(id: playing) {
            while playing, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(700))
                guard playing else { break }
                index = (index + 1) % max(frames.count, 1)
            }
        }
    }
}

/// Map plus radar controls, shared by the map tab and the detail screen.
struct TripMapPanel: View {
    var options: [TripOption]
    var selectedID: TripOption.ID?
    var onSelect: ((TripOption.ID) -> Void)? = nil
    @State private var frames = RadarTileOverlay.frameTimes()
    @State private var index = 0
    @State private var radarOn = true

    var body: some View {
        ZStack(alignment: .bottom) {
            RouteMapView(options: options, selectedID: selectedID, radarFrames: radarOn ? frames : [],
                         radarTime: radarOn && frames.indices.contains(index) ? frames[index] : nil,
                         onSelect: onSelect)
            RadarControls(frames: frames, index: $index, visible: $radarOn)
                .padding(8)
        }
        .onAppear { resetFrames() }
        .onChange(of: selectedID) { resetFrames() }
    }

    /// Fresh frames, starting at the frame closest to the selected trip's
    /// departure so "play" shows the rain coming towards the ride.
    private func resetFrames() {
        frames = RadarTileOverlay.frameTimes()
        let leave = options.first { $0.id == selectedID }?.leave ?? .now
        index = frames.enumerated().min { abs($0.element.timeIntervalSince(leave)) < abs($1.element.timeIntervalSince(leave)) }?.offset ?? 0
    }
}
