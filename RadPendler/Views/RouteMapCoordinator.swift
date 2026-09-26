import MapKit
import SwiftUI

/// Der Teil der Karte, der UIKit spricht: Delegate, Gesten, Zeichnen und alles
/// Nachführen. Er lag bis 1.4 in derselben Datei wie die Ansicht und ihre
/// Annotationen — elfhundert Zeilen, in denen man nichts wiederfand.
///
/// Die Trennlinie ist keine Geschmacksfrage: oben steht, **was** die Karte
/// zeigt (SwiftUI, deklarativ, ohne Zustand), hier steht, **wie** sie es tut
/// (MapKit, mit Zustand und Vergleichen gegen den letzten Stand). Der
/// Coordinator bleibt eine innere Klasse von `RouteMapView`, weil er ohne sie
/// keinen Sinn hat.
extension RouteMapView {
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
        private var guideKey = ""
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
            //
            // Die Kennung ist die **Geometrie**, nicht die Liste der Ids: eine
            // Planung meldet vier Zwischenstände, und in jedem sind dieselben
            // Linien mit neuen Ids. Vorher passte sich die Karte deshalb
            // viermal je Planung neu ein, mitten ins Hinsehen hinein.
            let plan = view.options.map { o in
                o.legs.first.map { "\(Int($0.departure.timeIntervalSince1970))" } ?? ""
                    + "\(Int(o.totalDistance))"
            }.joined(separator: "|")
            let key = plan + (view.selectedID?.uuidString ?? "")
            if key != routeKey {
                routeKey = key
                drawRoutes(map, view)
                if plan != planKey {
                    planKey = plan
                    zoomToRoutes(map, view)
                }
            }
            updateGuideLines(map, view)
            fitEnds(map, view)
            updateRadar(map, view)
            updateRider(map, view)
            updateTrack(map, view)
            updateLive(map, view)
            updateRideSignals(map, view)
        }

        /// Die Linie, der gerade gefolgt wird, und die ursprüngliche dünn
        /// daneben. Beide leben außerhalb des Plans: eine Neuplanung während
        /// der Fahrt ändert keine Möglichkeit, nur den Weg nach vorn — und
        /// vorher zeigte die Karte trotzdem weiter die alte Linie, während die
        /// Pfeile schon auf die neue zeigten.
        private func updateGuideLines(_ map: MKMapView, _ view: RouteMapView) {
            let key = Self.lineKey(view.guidedLine) + "|" + Self.lineKey(view.plannedLine)
            guard key != guideKey else { return }
            guideKey = key
            map.removeOverlays(map.overlays.filter { $0 is GuideLine })
            if view.plannedLine.count > 1 {
                let old = GuideLine(coordinates: view.plannedLine, count: view.plannedLine.count)
                old.faded = true
                map.addOverlay(old, level: .aboveRoads)
            }
            if view.guidedLine.count > 1 {
                let now = GuideLine(coordinates: view.guidedLine, count: view.guidedLine.count)
                now.kind = .bike
                map.addOverlay(now, level: .aboveRoads)
            }
        }

        /// Genug, um „dieselbe Linie" von „eine andere" zu unterscheiden, ohne
        /// tausend Punkte zu vergleichen.
        static func lineKey(_ line: [CLLocationCoordinate2D]) -> String {
            guard let first = line.first, let last = line.last else { return "0" }
            return String(format: "%d;%.5f,%.5f;%.5f,%.5f", line.count,
                          first.latitude, first.longitude, last.latitude, last.longitude)
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
                d.title = L("Ampel")
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
                d.title = stop.atSignal ? L("Ampel") : L("Halt")
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
            // Während einer Fahrt zeichnet `updateGuideLines` den Weg — dann
            // hier keine zweite Linie und keine zweite Ampelreihe darüber.
            let riding = view.guidedLine.count > 1
            if !riding {
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
                        let d = SignalDot(); d.coordinate = c; d.title = L("Ampel"); return d
                    })
                }
                if let selected { addLegBadges(map, selected) }
            }
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
            return o.transfers == 0 ? L("%@ · direkt", d) : L("%@ · %d× um", d, o.transfers)
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
                let p = Pin(); p.isRider = true; p.title = L("Du")
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
            if let line = overlay as? GuideLine {
                let r = MKPolylineRenderer(polyline: line)
                r.strokeColor = line.faded ? UIColor.systemGray.withAlphaComponent(0.65)
                                           : line.kind.uiColor.withAlphaComponent(0.95)
                r.lineWidth = line.faded ? 2.5 : 5
                if line.faded { r.lineDashPattern = [4, 5] }
                r.lineCap = .round
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
