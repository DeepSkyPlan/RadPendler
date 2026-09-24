import MapKit
import SwiftUI

/// MKMapView wrapper: SwiftUI's `Map` cannot show tile overlays, and the radar is one.
struct RouteMapView: UIViewRepresentable {
    var options: [TripOption]
    var selectedID: TripOption.ID?
    var radarFrames: [Date]
    /// Frame on screen; nil hides the radar.
    var radarTime: Date?
    /// Only while the frames are being played does it pay to hold the
    /// neighbours ready. Standing still on one minute, two extra tile layers
    /// are two extra downloads of a picture nobody is going to look at.
    var radarPreload = false
    /// Fixed points from the settings, drawn as flags.
    var waypoints: [Place] = []
    /// Start und Ziel, für die Sekunden **vor** der ersten Route. Ohne das
    /// steht die Karte beim Öffnen auf halb Europa: man sieht eine Karte und
    /// erkennt nichts darauf — und weil die Kästen sich jetzt nacheinander
    /// füllen, dauert dieser Zustand sichtbar länger als früher.
    var ends: [CLLocationCoordinate2D] = []
    /// The way actually ridden, coloured by speed. Grows point by point while
    /// a ride is being recorded and stands still afterwards.
    var track: [RidePoint] = []
    /// Where the ride stood still, and whether that was a red light.
    var trackStops: [RideStop] = []
    /// Lit junctions to show while riding — the planned route's and the ones
    /// this rider has learned. Afterwards one can see where one stood; ahead
    /// of time one wants to see what is coming.
    var signals: [CLLocationCoordinate2D] = []
    /// Where the rider is now; drawn as a heading arrow, not as a pin.
    var rider: CLLocationCoordinate2D? = nil
    /// Degrees from north, negative when unknown.
    var course: CLLocationDirection = -1
    /// Keep the map on the rider instead of on the whole route.
    var following = false
    /// Gesetzt, solange der Fahrer neben der Route ist: dann folgt die Karte
    /// ihm nicht mehr eng, sondern nimmt beides ins Bild — wo er ist und wo
    /// die Route liegt. Und sie steht dabei nach Norden: auf einer Karte, die
    /// sich mitdreht, ist „dort drüben liegt die Route" schwerer zu lesen als
    /// ein Pfeil auf einer, die still steht.
    var showBoth: CLLocationCoordinate2D? = nil
    /// The user dragged the map: following has to give way to the hand.
    var onPan: (() -> Void)? = nil
    /// Keeps MapKit's own controls — the compass above all — out from under
    /// whatever the app floats over the top of the map.
    var topInset: CGFloat = 0
    /// Tap on an option's label on the map.
    var onSelect: ((TripOption.ID) -> Void)? = nil

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = true
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "pin")
        map.register(OptionLabelView.self, forAnnotationViewWithReuseIdentifier: "label")
        map.register(SignalDotView.self, forAnnotationViewWithReuseIdentifier: "signal")
        map.register(StopDotView.self, forAnnotationViewWithReuseIdentifier: "stop")
        map.register(RiderView.self, forAnnotationViewWithReuseIdentifier: "rider")
        let press = UILongPressGestureRecognizer(target: context.coordinator,
                                                 action: #selector(Coordinator.handleLongPress(_:)))
        press.minimumPressDuration = 0.45
        map.addGestureRecognizer(press)
        // Rides alongside MapKit's own recognisers instead of replacing them:
        // it only has to notice that a hand was on the map, so the camera can
        // stop fighting it.
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        map.addGestureRecognizer(pan)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.update(map, self)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class LegLine: MKPolyline {
        var kind: LegKind = .walk
        var emphasized = true
        /// Belongs to a trip that misses the fixed points.
        var dimmed = false
    }

    final class Pin: MKPointAnnotation {
        var tint: UIColor = .systemGreen
        var glyph: String = "mappin"
        var isRider = false
    }

    /// A junction with traffic lights. `fromPlan` says who owns it: the ones
    /// belonging to the drawn plan are cleared whenever the plan is redrawn,
    /// the ones handed over for a ride in progress outlive it.
    final class SignalDot: MKPointAnnotation {
        var fromPlan = true
    }

    /// A stretch of the recorded ride, in the colour of the speed it was
    /// ridden at. One polyline per run of equal colour: MapKit draws a
    /// polyline in exactly one colour, so a line that changes colour is
    /// several lines.
    final class TrackLine: MKPolyline {
        var step = 0
    }

    /// Where the ride stood still. Yellow at a lit junction, grey elsewhere —
    /// the difference the whole counting is about.
    final class StopDot: MKPointAnnotation {
        var atSignal = false
        var seconds: TimeInterval = 0
    }

    /// A red light on a ridden route reads at a glance: yellow, a light, and
    /// the seconds it cost. Everything else that stood still is grey and small
    /// — the difference between the two is what the counting is about.
    final class StopDotView: MKAnnotationView {
        private let icon = UIImageView()
        private let label = UILabel()

        override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
            super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
            let stack = UIStackView(arrangedSubviews: [icon, label])
            stack.spacing = 2
            stack.alignment = .center
            stack.isLayoutMarginsRelativeArrangement = true
            stack.layoutMargins = UIEdgeInsets(top: 2, left: 4, bottom: 2, right: 5)
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
                stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            icon.contentMode = .scaleAspectFit
            icon.preferredSymbolConfiguration = .init(pointSize: 9, weight: .bold)
            label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .bold)
            layer.cornerRadius = 9
            layer.borderWidth = 1.5
            layer.borderColor = UIColor.white.cgColor
            collisionMode = .circle
            canShowCallout = false
        }

        required init?(coder: NSCoder) { fatalError() }

        func configure(_ dot: StopDot) {
            let seconds = Int(dot.seconds.rounded())
            if dot.atSignal {
                backgroundColor = UIColor(red: 0.98, green: 0.78, blue: 0.11, alpha: 1)
                icon.image = UIImage(systemName: "light.beacon.max.fill")
                icon.tintColor = .black.withAlphaComponent(0.75)
                label.textColor = .black
                displayPriority = .required
                zPriority = .defaultSelected
            } else {
                backgroundColor = .systemGray3
                icon.image = UIImage(systemName: "pause.fill")
                icon.tintColor = .white
                label.textColor = .white
                displayPriority = .defaultLow
                zPriority = .defaultUnselected
            }
            label.text = seconds < 60 ? "\(seconds)s" : "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
            frame.size = systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        }
    }

    /// Where the rider is, pointing the way they are going.
    final class Rider: MKPointAnnotation {
        var course: CLLocationDirection = -1
    }

    final class RiderView: MKAnnotationView {
        private let arrow = UIImageView()

        override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
            super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
            frame = CGRect(x: 0, y: 0, width: 30, height: 30)
            backgroundColor = UIColor(red: 0.00, green: 0.62, blue: 0.51, alpha: 1)
            layer.cornerRadius = 15
            layer.borderWidth = 3
            layer.borderColor = UIColor.white.cgColor
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.3
            layer.shadowRadius = 3
            layer.shadowOffset = .zero
            arrow.frame = bounds.insetBy(dx: 6, dy: 6)
            arrow.contentMode = .scaleAspectFit
            arrow.tintColor = .white
            arrow.image = UIImage(systemName: "location.north.fill")
            addSubview(arrow)
            displayPriority = .required
            zPriority = .max
            collisionMode = .circle
            canShowCallout = false
        }

        required init?(coder: NSCoder) { fatalError() }

        /// The arrow points where the ride is going — **on screen**, which is
        /// not the same as "at the course". While the map follows the rider it
        /// is itself turned to the course, and an arrow rotated by the course
        /// on top of that points at twice the angle. So it is always the
        /// course *minus the map's own heading*.
        ///
        /// Without any course at all the arrow would point north and lie about
        /// it; then a plain dot says the same thing without the lie.
        func configure(_ r: Rider, mapHeading: CLLocationDirection) {
            arrow.isHidden = r.course < 0
            arrow.transform = CGAffineTransform(rotationAngle: (r.course - mapHeading) * .pi / 180)
        }
    }

    final class SignalDotView: MKAnnotationView {
        override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
            super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
            frame = CGRect(x: 0, y: 0, width: 9, height: 9)
            backgroundColor = UIColor(red: 0.98, green: 0.71, blue: 0.11, alpha: 1)
            layer.cornerRadius = 4.5
            layer.borderWidth = 1.5
            layer.borderColor = UIColor.white.cgColor
            displayPriority = .defaultLow
            collisionMode = .circle
            canShowCallout = false
        }

        required init?(coder: NSCoder) { fatalError() }
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

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var onSelect: ((TripOption.ID) -> Void)?
        var onPan: (() -> Void)?
        /// The rectangle that holds every drawn route — where a long press goes back to.
        private var fitRect: MKMapRect?

        /// Long press anywhere on the map: back to the whole route in view,
        /// however far one has panned and zoomed away.
        @objc func handleLongPress(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let map = g.view as? MKMapView, let fitRect else { return }
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            map.setVisibleMapRect(fitRect, edgePadding: Self.fitInsets, animated: true)
        }

        /// A hand on the map outranks the camera. Only the start of the drag
        /// counts — reporting every movement would send one message per frame.
        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            guard g.state == .began else { return }
            onPan?()
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        static let fitInsets = UIEdgeInsets(top: 50, left: 30, bottom: 110, right: 30)
        private var routeKey = ""
        private var planKey = ""
        private var radar: [Date: RadarTileOverlay] = [:]
        private var renderers: [Date: MKTileOverlayRenderer] = [:]
        private var shownRadar: Date?
        private var rider: Pin?
        /// How many points of the ride are already drawn. The line only ever
        /// grows, so a redraw is a few new segments — not a thousand polylines
        /// torn down and rebuilt once a second.
        private var drawnTrack = 0
        private var stopKey = 0
        private var rideSignals = -1
        private var lastCamera: (center: CLLocationCoordinate2D, heading: CLLocationDirection)?
        private var lastBoth: (CLLocationCoordinate2D, CLLocationCoordinate2D)?
        private var lastBothHeading: CLLocationDirection = 0
        private var endsKey: String?
        /// What we last told the map. Never read back from the view: that is
        /// how the margins loop started.
        private var hidesCompass = false
        private var live: Rider?

        func update(_ map: MKMapView, _ view: RouteMapView) {
            onSelect = view.onSelect
            onPan = view.onPan
            // Never `layoutMargins`. Setting them on an MKMapView whose
            // `insetsLayoutMarginsFromSafeArea` is on — the default — reads
            // back as safe area *plus* what was set, so a comparison against
            // the wanted value never matches and it is set again on the next
            // redraw. That loop laid the map out over and over and shrank its
            // usable area a little each time: the app got slower the longer it
            // ran, with a map window that kept getting smaller. (1.2, Build 24.)
            //
            // The compass was the whole reason. While a turn banner covers the
            // top of the screen it can simply go: the banner says where to go,
            // and the arrow says which way one is pointing.
            if hidesCompass != (view.topInset > 0) {
                hidesCompass = view.topInset > 0
                map.showsCompass = !hidesCompass
            }
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
            fitEnds(map, view)
            updateRadar(map, view)
            updateRider(map, view)
            updateTrack(map, view)
            updateLive(map, view)
            updateRideSignals(map, view)
        }

        /// Solange es noch keine Route gibt: auf Start und Ziel einpassen.
        /// Sobald eine Route da ist, übernimmt `zoomToRoutes` — und wenn der
        /// Fahrer verfolgt wird, gar nichts davon.
        private func fitEnds(_ map: MKMapView, _ view: RouteMapView) {
            guard view.options.isEmpty, !view.following, view.ends.count >= 2 else {
                if !view.options.isEmpty { endsKey = nil }
                return
            }
            let key = view.ends.map { String(format: "%.4f,%.4f", $0.latitude, $0.longitude) }.joined()
            guard key != endsKey else { return }
            endsKey = key
            let rect = view.ends.reduce(MKMapRect.null) {
                $0.union(MKMapRect(origin: MKMapPoint($1), size: MKMapSize(width: 1, height: 1)))
            }
            guard !rect.isNull else { return }
            fitTrack(map, rect)
        }

        /// The lit junctions of a ride in progress. Drawn once and left alone:
        /// the list is frozen when the ride starts.
        private func updateRideSignals(_ map: MKMapView, _ view: RouteMapView) {
            guard view.signals.count != rideSignals else {
                return
            }
            rideSignals = view.signals.count
            map.removeAnnotations(map.annotations.filter { ($0 as? SignalDot)?.fromPlan == false })
            map.addAnnotations(view.signals.map { c in
                let d = SignalDot()
                d.coordinate = c
                d.fromPlan = false
                d.title = "Ampel"
                return d
            })
        }

        // MARK: The ride being recorded

        /// The ridden line in the colours of the speeds it was ridden at. A
        /// segment belongs to the step of the speed at its *end*: that is the
        /// speed that was reached over it.
        private func updateTrack(_ map: MKMapView, _ view: RouteMapView) {
            guard view.track.count >= 2 else {
                if drawnTrack > 0 {
                    map.removeOverlays(map.overlays.filter { $0 is TrackLine })
                    drawnTrack = 0
                }
                return
            }
            // A different ride (the detail map, or a new recording) — start over.
            if view.track.count < drawnTrack {
                map.removeOverlays(map.overlays.filter { $0 is TrackLine })
                drawnTrack = 0
            }
            let first = drawnTrack == 0
            let from = Swift.max(drawnTrack - 1, 0)
            var added: [TrackLine] = []
            for line in Self.lines(of: view.track, from: from) {
                map.addOverlay(line, level: .aboveRoads)
                added.append(line)
            }
            drawnTrack = view.track.count
            updateStops(map, view)
            // A finished ride is shown on its own, without a plan under it —
            // then there is no route rectangle to open on and the track is
            // the only thing that says where in the world this happened.
            guard first, !view.following, view.options.isEmpty,
                  let start = added.first?.boundingMapRect else { return }
            fitTrack(map, added.dropFirst().reduce(start) { $0.union($1.boundingMapRect) })
        }

        /// Insets for a bare track: no radar bar underneath, only the colour
        /// scale in the corner.
        static let trackInsets = UIEdgeInsets(top: 24, left: 24, bottom: 44, right: 24)

        /// Before the first layout the map has no size and a fit is thrown
        /// away — the same trap `zoomToRoutes` sits in, and the same way out.
        /// Bounded, so a view that never gets a size does not keep a runloop
        /// hop alive forever.
        private func fitTrack(_ map: MKMapView, _ rect: MKMapRect, tries: Int = 20) {
            fitRect = rect
            guard map.bounds.width > 0 else {
                guard tries > 0 else { return }
                DispatchQueue.main.async { [weak self, weak map] in
                    guard let self, let map else { return }
                    self.fitTrack(map, rect, tries: tries - 1)
                }
                return
            }
            map.setVisibleMapRect(rect, edgePadding: Self.trackInsets, animated: false)
        }

        /// Colour step of a point, smoothed over its neighbours.
        ///
        /// Not the raw speed: a receiver reports 19,8 and 20,1 km/h in
        /// consecutive seconds, and the unsmoothed line then becomes hundreds
        /// of two-point polylines flickering between two greens. Every one of
        /// them is an overlay MapKit has to draw while the thumb is moving,
        /// which is precisely what made panning stutter.
        static func smoothed(_ track: [RidePoint], at i: Int) -> Double {
            let lo = Swift.max(0, i - 2), hi = Swift.min(track.count - 1, i + 2)
            var sum = 0.0
            for j in lo...hi { sum += track[j].kmh }
            return sum / Double(hi - lo + 1)
        }

        /// How wide a speed has to be inside the next step before the colour
        /// changes. Without it a ride at almost exactly twenty km/h becomes a
        /// striped line, because the average still crosses the boundary every
        /// few seconds.
        static let colourMargin = 1.5

        /// The colour step, with hysteresis: the colour changes only once the
        /// smoothed speed is `colourMargin` clear of the boundary it just
        /// crossed. Sitting *on* a boundary keeps whatever colour is running —
        /// but a speed well inside another step always wins, so a steady
        /// twenty-five is drawn as twenty-five and not as whatever came before.
        static func step(of track: [RidePoint], at i: Int, current: Int?) -> Int {
            let v = smoothed(track, at: i)
            let raw = RideColors.index(v)
            guard let current, raw != current else { return raw }
            // The boundary between the two steps is the upper bound of the
            // lower one.
            let boundary = RideColors.steps[Swift.min(current, raw)].kmh
            return abs(v - boundary) >= colourMargin ? raw : current
        }

        /// One polyline per run of equal colour, built from `from` onwards.
        /// Runs overlap by a point so the line has no gaps at a colour change.
        static func lines(of track: [RidePoint], from: Int) -> [TrackLine] {
            guard track.count >= 2, from < track.count - 1 else { return [] }
            var out: [TrackLine] = []
            var run: [CLLocationCoordinate2D] = [track[from].coordinate]
            var step = Self.step(of: track, at: from + 1, current: nil)
            for i in (from + 1)..<track.count {
                let next = Self.step(of: track, at: i, current: step)
                if next != step, run.count >= 2 {
                    out.append(line(run, step))
                    run = [run[run.count - 1]]
                    step = next
                }
                run.append(track[i].coordinate)
            }
            if run.count >= 2 { out.append(line(run, step)) }
            return out
        }

        private static func line(_ coords: [CLLocationCoordinate2D], _ step: Int) -> TrackLine {
            let l = TrackLine(coordinates: coords, count: coords.count)
            l.step = step
            return l
        }

        private func updateStops(_ map: MKMapView, _ view: RouteMapView) {
            // Count alone would miss a different ride with the same number of
            // stops, which is exactly what two commutes of the same route are.
            let key = view.trackStops.count &+ Int(view.trackStops.first?.start.timeIntervalSince1970 ?? 0)
            guard key != stopKey else { return }
            stopKey = key
            map.removeAnnotations(map.annotations.filter { $0 is StopDot })
            map.addAnnotations(view.trackStops.map { stop in
                let d = StopDot()
                d.coordinate = stop.coordinate
                d.atSignal = stop.atSignal
                d.seconds = stop.seconds
                d.title = stop.atSignal ? "Ampel" : "Halt"
                return d
            })
        }

        /// The rider's own position, and the camera that follows it. Following
        /// keeps a fixed scale and turns with the course, because on a bike one
        /// reads the map as "what is in front of me", not as "where is north".
        private func updateLive(_ map: MKMapView, _ view: RouteMapView) {
            guard let here = view.rider else {
                if let live { map.removeAnnotation(live); self.live = nil }
                return
            }
            if live == nil {
                let r = Rider()
                live = r
                map.addAnnotation(r)
            }
            live?.coordinate = here
            live?.course = view.course
            if view.following, let other = view.showBoth {
                fitBoth(map, here, other,
                        heading: view.course >= 0 ? view.course : map.camera.heading)
            } else if view.following {
                let heading = view.course >= 0 ? view.course : map.camera.heading
                // Only when something actually moved. A camera animation
                // started every second, each one interrupting the last, is a
                // map that never settles.
                let moved = lastCamera.map {
                    $0.center.distance(to: here) > 3 || abs($0.heading - heading) > 4
                } ?? true
                if moved {
                    lastCamera = (here, heading)
                    map.setCamera(MKMapCamera(lookingAtCenter: here, fromDistance: 700,
                                              pitch: 0, heading: heading), animated: true)
                }
            } else {
                lastCamera = nil
            }
            if view.showBoth == nil { lastBoth = nil }
            // After the camera, not before: the arrow is drawn against the
            // heading the map is about to have.
            if let live, let v = map.view(for: live) as? RiderView {
                v.configure(live, mapHeading: view.following && view.course >= 0 ? view.course : map.camera.heading)
            }
        }

        /// Beides ins Bild: der Fahrer und der nächste Punkt der Route. Neu
        /// eingepasst wird nur, wenn sich wirklich etwas bewegt hat — sonst
        /// setzt sich die Karte im Sekundentakt selbst neu und steht nie still.
        ///
        /// **Die Karte bleibt dabei in Fahrtrichtung gedreht.** Sie kurz auf
        /// Norden zu stellen war ein Fehlgriff: auf dem Rad liest man die
        /// Karte als „was vor mir liegt", und eine Karte, die sich beim
        /// Verlassen der Route plötzlich dreht, ist genau dann unlesbar, wenn
        /// man sie am nötigsten braucht. Der Pfeil zeigt entsprechend auf
        /// `Richtung − Kurs`, wie der Fahrerpfeil auch.
        private func fitBoth(_ map: MKMapView, _ here: CLLocationCoordinate2D,
                             _ other: CLLocationCoordinate2D, heading: CLLocationDirection) {
            if let last = lastBoth, last.0.distance(to: here) < 25, last.1.distance(to: other) < 25,
               abs(lastBothHeading - heading) < 4 { return }
            lastBoth = (here, other)
            lastBothHeading = heading
            lastCamera = nil
            let mid = CLLocationCoordinate2D(latitude: (here.latitude + other.latitude) / 2,
                                             longitude: (here.longitude + other.longitude) / 2)
            // Anderthalbmal der Abstand, mindestens so viel, dass man noch
            // Straßen erkennt: ein Bild, das genau die beiden Punkte umfasst,
            // zeigt sie am Rand und nichts dazwischen.
            let apart = here.distance(to: other)
            map.setCamera(MKMapCamera(lookingAtCenter: mid, fromDistance: Swift.max(apart * 2.5, 600),
                                      pitch: 0, heading: heading), animated: true)
        }

        private func drawRoutes(_ map: MKMapView, _ view: RouteMapView) {
            map.removeOverlays(map.overlays.filter { $0 is LegLine })
            map.removeAnnotations(map.annotations.compactMap { $0 as? Pin }.filter { !$0.isRider })
            map.removeAnnotations(map.annotations.filter {
                $0 is OptionLabel || ($0 as? SignalDot)?.fromPlan == true
            })
            let selected = view.options.first { $0.id == view.selectedID }
            // Unselected options faint underneath, the selected one on top.
            let ordered = view.options.filter { $0.id != selected?.id } + (selected.map { [$0] } ?? [])
            for option in ordered {
                for leg in option.legs where leg.coordinates.count > 1 {
                    let line = LegLine(coordinates: leg.coordinates, count: leg.coordinates.count)
                    line.kind = leg.kind
                    line.emphasized = selected == nil || option.id == selected?.id
                    line.dimmed = !option.passesWaypoints
                    map.addOverlay(line, level: .aboveRoads)
                }
            }
            addLabels(map, view.options, selected: selected?.id)
            // Lit junctions of the chosen route — where the waiting happens.
            if let points = selected?.bikeRoute?.stats?.signalPoints ?? selected?.carRoute?.signalPoints {
                map.addAnnotations(points.map { c in
                    let d = SignalDot(); d.coordinate = c; d.title = "Ampel"; return d
                })
            }
            if let selected { addLegBadges(map, selected) }
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
            for w in view.waypoints {
                let p = Pin(); p.coordinate = w.coordinate; p.title = w.shortName
                p.tint = .systemIndigo; p.glyph = "pin.fill"
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
            if let bike = o.bikeRoute { return "\(d) · \(bike.shortTitle)" }
            if let car = o.carRoute { return "\(d) · \(car.variants.first?.title ?? "Route")" }
            guard !o.transitLegs.isEmpty else { return d }
            return o.transfers == 0 ? "\(d) · direkt" : "\(d) · \(o.transfers)× um"   // short form of transferText
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            guard let label = annotation as? OptionLabel, let id = label.optionID else { return }
            mapView.deselectAnnotation(annotation, animated: false)
            onSelect?(id)
        }

        /// Small badge on every leg of the chosen trip, so it is obvious which
        /// stretch is ridden, driven or taken by train.
        private func addLegBadges(_ map: MKMapView, _ trip: TripOption) {
            for leg in trip.legs where leg.coordinates.count > 1 {
                guard let m = leg.length, m >= 300,
                      let c = RainSampler.position(on: leg.coordinates, departure: leg.departure,
                                                   arrival: leg.arrival,
                                                   at: leg.departure.addingTimeInterval(leg.duration / 2)) else { continue }
                let a = OptionLabel()
                a.coordinate = c
                a.optionID = trip.id
                a.symbol = leg.kind.symbol
                a.text = [leg.lineName, Fmt.km(m)].compactMap { $0 }.joined(separator: " · ")
                a.color = leg.kind.uiColor
                a.selected = true
                map.addAnnotation(a)
            }
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
            fitRect = all
            // Bottom inset clears the radar controls floating over the map.
            map.setVisibleMapRect(all, edgePadding: Self.fitInsets, animated: false)
        }

        /// Only the shown frame and its two neighbours hang on the map. Keeping
        /// all twenty-two there cost about seven hundred tile requests in the
        /// first forty seconds — MapKit loads the tiles of every overlay, alpha
        /// 0 or not. The neighbours are what keeps scrubbing and playback
        /// smooth; anything beyond them is a download for a picture nobody sees.
        ///
        /// Nothing is mounted before the map has been fitted to the route: on
        /// the opening world zoom a single frame covers the planet.
        private func updateRadar(_ map: MKMapView, _ view: RouteMapView) {
            guard let time = view.radarTime, fitRect != nil else {
                renderers.values.forEach { $0.alpha = 0 }
                shownRadar = nil
                return
            }
            let wanted = view.radarPreload ? Self.window(around: time, in: view.radarFrames) : [time]
            let plan = Self.radarPlan(mounted: Set(radar.keys), wanted: wanted)
            for t in plan.drop {
                if let overlay = radar[t] { map.removeOverlay(overlay) }
                radar[t] = nil
                renderers[t] = nil
            }
            for t in plan.add {
                let o = RadarTileOverlay(time: t)
                radar[t] = o
                map.insertOverlay(o, at: 0, level: .aboveRoads)
            }
            if shownRadar != time {
                shownRadar = time
                for (t, r) in renderers { r.alpha = t == time ? 0.7 : 0 }
            }
        }

        /// Which radar overlays to take off the map and which to put on.
        ///
        /// It has to settle: called again with nothing changed it must return
        /// two empty sets. The version before 1.2 mounted **every** frame
        /// after dropping all but three, so each redraw tore nineteen tile
        /// overlays off the map and hung them back on — hundreds of tile
        /// requests a second, for pictures nobody was looking at. That is what
        /// made the whole app feel busy: panning stuttered, and so did setting
        /// the time on a screen that merely had the map behind it.
        static func radarPlan(mounted: Set<Date>, wanted: Set<Date>) -> (drop: Set<Date>, add: Set<Date>) {
            (drop: mounted.subtracting(wanted), add: wanted.subtracting(mounted))
        }

        /// The shown minute and one step either side.
        static func window(around time: Date, in frames: [Date]) -> Set<Date> {
            guard let i = frames.firstIndex(of: time) else { return [time] }
            let lo = Swift.max(0, i - 1), hi = Swift.min(frames.count - 1, i + 1)
            return Set(frames[lo...hi])
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
            if let track = overlay as? TrackLine {
                let r = MKPolylineRenderer(polyline: track)
                r.strokeColor = RideColors.steps[track.step].color
                r.lineWidth = 7
                r.lineCap = .round
                r.lineJoin = .round
                return r
            }
            if let line = overlay as? LegLine {
                let r = MKPolylineRenderer(polyline: line)
                // Other options grey underneath, the chosen one in colour on top.
                r.strokeColor = line.emphasized ? line.kind.uiColor.withAlphaComponent(line.dimmed ? 0.45 : 0.95)
                                                : UIColor.systemGray.withAlphaComponent(line.dimmed ? 0.25 : 0.55)
                r.lineWidth = line.emphasized ? 5 : 4
                if line.dimmed { r.lineDashPattern = [6, 5] }
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
            if let rider = annotation as? Rider {
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: "rider", for: rider) as! RiderView
                v.configure(rider, mapHeading: mapView.camera.heading)
                return v
            }
            if let stop = annotation as? StopDot {
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: "stop", for: stop) as! StopDotView
                v.configure(stop)
                return v
            }
            if annotation is SignalDot {
                return mapView.dequeueReusableAnnotationView(withIdentifier: "signal", for: annotation)
            }
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

/// Play/pause and scrubber for the radar frames — and, on the main screen, the
/// line underneath that says how old the plan above it is.
struct RadarControls: View {
    var frames: [Date]
    @Binding var index: Int
    @Binding var visible: Bool
    /// Lifted out of this view so the map knows whether to hold the
    /// neighbouring frames ready.
    @Binding var playing: Bool
    /// When the plan on screen was computed; nil leaves the second line away.
    var lastRun: Date? = nil
    var loading = false
    var onRefresh: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 5) {
            controls
            if let onRefresh { LastRunLine(lastRun: lastRun, loading: loading, action: onRefresh) }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Toggle(isOn: $visible) { Image(systemName: "cloud.rain") }
                .toggleStyle(.button)
                .accessibilityLabel("Regenradar")
            // Tiles still coming in: say so, an empty sky and a missing sky
            // look exactly alike.
            if visible, RadarLoads.shared.isLoading {
                ProgressView().controlSize(.mini)
                    .accessibilityLabel("Radarbilder werden geladen")
            }
            if visible, !frames.isEmpty {
                Button { playing.toggle() } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                }
                .accessibilityLabel(playing ? "Anhalten" : "Abspielen")
                Slider(value: Binding(get: { Double(index) }, set: { index = Int($0.rounded()) }),
                       in: 0...Double(max(frames.count - 1, 1)), step: 1)
                // Which minute is on the map — "jetzt 14:48", "in 25 min 15:10".
                // Tapping jumps back to the current frame.
                Button {
                    playing = false
                    index = Self.nearest(.now, in: frames)
                } label: {
                    VStack(alignment: .trailing, spacing: -1) {
                        Text(Self.relative(shown))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(Fmt.time(shown))
                            .font(.callout.monospacedDigit().weight(.bold))
                            .foregroundStyle(.primary)
                    }
                    .frame(width: 74, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Regenradar \(Self.relative(shown)), \(Fmt.time(shown)). Tippen für jetzt.")
            } else {
                Text("Regenradar (DWD)").font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .task(id: playing) {
            while playing, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(700))
                guard playing else { break }
                index = index + 1 < frames.count ? index + 1 : 0
            }
        }
    }

    private var shown: Date { frames[min(index, frames.count - 1)] }

    /// A radar frame in words: measured minutes ago, now, or a forecast ahead.
    static func relative(_ frame: Date, now: Date = .now) -> String {
        let m = Int((frame.timeIntervalSince(now) / 60).rounded())
        if m <= -60 { return "vor \(-m / 60) h" }
        if m < -2 { return "vor \(-m) min" }
        if m <= 2 { return "jetzt" }
        if m < 60 { return "in \(m) min" }
        return m % 60 == 0 ? "in \(m / 60) h" : "in \(m / 60):\(String(format: "%02d", m % 60)) h"
    }

    /// Index of the frame closest to a moment.
    static func nearest(_ target: Date, in frames: [Date]) -> Int {
        frames.enumerated()
            .min { abs($0.element.timeIntervalSince(target)) < abs($1.element.timeIntervalSince(target)) }?.offset ?? 0
    }
}

/// When the plan above was computed and how long ago that was, on the same
/// axis as the radar minutes. Tapping it plans again — the main screen does not
/// scroll any more, so there is no pull.
struct LastRunLine: View {
    var lastRun: Date?
    var loading: Bool
    var action: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            Button(action: action) {
                HStack(spacing: 5) {
                    Text(text(now: context.date))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if loading {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .bold))
                    }
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lastRun == nil ? "Neu berechnen" : "Berechnet \(text(now: context.date)). Tippen für neu berechnen.")
        }
    }

    private func text(now: Date) -> String {
        guard let lastRun else { return loading ? "wird berechnet …" : "neu berechnen" }
        return "Stand \(Fmt.time(lastRun)) · \(Fmt.age(now.timeIntervalSince(lastRun)))"
    }

}

/// Map plus radar controls, shared by the map tab and the detail screen.
struct TripMapPanel: View {
    var options: [TripOption]
    var selectedID: TripOption.ID?
    var waypoints: [Place] = []
    /// Start und Ziel, für die Zeit vor der ersten Route.
    var ends: [CLLocationCoordinate2D] = []
    var onSelect: ((TripOption.ID) -> Void)? = nil
    /// The stamp on the time axis: when the plan was computed, and the way back
    /// to a fresh one. Left away on the detail screen, which plans nothing.
    var lastRun: Date? = nil
    var loading = false
    var onRefresh: (() -> Void)? = nil
    @State private var frames = RadarTileOverlay.frameTimes()
    @State private var index = 0
    @State private var radarOn = true
    @State private var playing = false

    private var trip: TripOption? { options.first { $0.id == selectedID } }

    var body: some View {
        ZStack(alignment: .bottom) {
            RouteMapView(options: options, selectedID: selectedID, radarFrames: radarOn ? frames : [],
                         radarTime: radarOn && frames.indices.contains(index) ? frames[index] : nil,
                         radarPreload: playing,
                         waypoints: waypoints, ends: ends, onSelect: onSelect)
            RadarControls(frames: frames, index: $index, visible: $radarOn, playing: $playing,
                          lastRun: lastRun, loading: loading, onRefresh: onRefresh)
                .padding(8)
        }
        .onAppear { resetFrames() }
        .onChange(of: selectedID) { resetFrames() }
    }

    /// Frames around the selected trip, so pressing play runs the ride and the
    /// rain forward together — but the map opens on the current minute, because
    /// that is the one thing you always want to see first.
    private func resetFrames() {
        guard let trip else {
            frames = RadarTileOverlay.frameTimes()
            index = RadarControls.nearest(.now, in: frames)
            return
        }
        frames = RadarTileOverlay.frameTimes(forTripFrom: trip.leave, to: trip.arrival)
        index = RadarControls.nearest(.now, in: frames)
    }
}
