import CoreLocation
import Observation
import UIKit

/// Records a ride: the way actually taken, how fast, and where it stood still.
///
/// This is the one place in the app that follows anybody, and it only does so
/// between "Fahrt starten" and "Fahrt beenden". Outside a recording no manager
/// is running, the background flag is off and `LocationService` goes on doing
/// what it always did — a single fix when asked.
///
/// The recording does continue with the screen locked and the phone in a
/// pocket, which is the only way a commute can be recorded at all; iOS shows
/// the blue indicator for as long as it lasts.
@MainActor
@Observable
final class RideTracker: NSObject, CLLocationManagerDelegate {
    /// What is being ridden — copied from the plan when the ride starts, so a
    /// replan in the middle cannot rename the ride under way.
    struct Subject: Equatable {
        var id = UUID()
        var origin: String
        var destination: String
        var mode: String
        var plannedSeconds: TimeInterval?
        /// Was der Plan versprochen hat: Länge und Ampeln. Beides wandert in
        /// die gespeicherte Fahrt, damit sich hinterher vergleichen lässt,
        /// was angekündigt und was gefahren wurde.
        var plannedMeters: Double?
        var plannedSignals: Int?
    }

    private(set) var subject: Subject?
    private(set) var meter = RideMeter()
    /// Why nothing is being recorded, when something should be.
    private(set) var failure: String?
    /// Where the rider is right now, for the map.
    private(set) var here: CLLocationCoordinate2D?
    /// Degrees from north, for turning the camera with the rider.
    private(set) var course: CLLocationDirection = -1
    /// The finished ride, held until the summary sheet is dismissed.
    private(set) var finished: Ride?

    var isRecording: Bool { subject != nil }

    private let manager = CLLocationManager()
    private var lastWatchPush = Date.distantPast
    private var lastSave = Date.distantPast
    /// The store the finished ride goes to; injected so tests can leave it out.
    private let store: RideStore

    init(store: RideStore = .shared) {
        self.store = store
        super.init()
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.applyIdleTimer() }
        }
        manager.delegate = self
        // `Best`, not `BestForNavigation`: the latter keeps the receiver and
        // its sensor fusion at full tilt for turn-by-turn guidance the app
        // does not give, and it is the most expensive mode there is. On a bike
        // the difference in the drawn line is not visible; in the battery it is.
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .otherNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        // A pause looks like an arrival to iOS and never resumes on its own.
        manager.pausesLocationUpdatesAutomatically = false
    }

    // MARK: Start and stop

    /// Begins recording the trip that is on screen. The lit junctions of that
    /// trip come along: they are what turns a standstill into a red light, and
    /// they must be the ones of the route that was planned, not of whatever is
    /// planned by the time the ride ends.
    /// The way ahead, frozen at the start of the ride, and its corners.
    /// Like the lit junctions, and for the same reason: a replan half way must
    /// not be able to point the arrow at a road one is not on — and a plan that
    /// quietly comes back empty must not take the guidance with it.
    private(set) var plannedRoute: [CLLocationCoordinate2D] = []
    private(set) var turns: [TurnGuide.Step] = []
    /// Cumulative lengths of `plannedRoute`, computed once. Without it every
    /// redraw allocated an array as long as the route.
    private var routeLengths: [Double] = []
    /// Where on the route the rider was matched last, so the next search does
    /// not start at the beginning again.
    private var routeIndex = 0
    /// The lit junctions this ride is being judged against — handed to the map
    /// so they can be seen while riding, not only afterwards.
    private(set) var signals: [CLLocationCoordinate2D] = []
    /// Davon die Ampeln der **geplanten Route**. Nur sie gehören auf die Karte
    /// und in die Zählung „soundsoviel von soundsoviel": `signals` enthält
    /// zusätzlich alles, was dieser Fahrer irgendwo gelernt hat, und das sind
    /// quer durch die Stadt ein paar hundert Punkte.
    private(set) var plannedSignals: [CLLocationCoordinate2D] = []
    /// Die Linie, mit der die Fahrt begonnen hat. Sie bleibt, auch wenn
    /// unterwegs neu geplant wird — auf der Karte liegt sie dann dünn neben
    /// der neuen, und hinterher neben der gefahrenen.
    private(set) var originalRoute: [CLLocationCoordinate2D] = []
    /// Wie weit jede geplante Ampel vom Anfang der Route entfernt liegt,
    /// aufsteigend. Damit ist „wie viele kommen noch" ein Vergleich und keine
    /// Suche über die halbe Stadt.
    private var signalStations: [Double] = []

    /// Wie weit es noch ist und was davon noch kommt. Einmal je Ortung
    /// gerechnet, nicht je Bild.
    struct Progress: Equatable {
        var metersLeft: Double
        var signalsLeft: Int
        var signalsPassed: Int
        var plannedSignals: Int
        var plannedMeters: Double
    }

    private(set) var progress: Progress?

    /// Wo die geplante Linie liegt, solange man nicht auf ihr ist — nil,
    /// solange man auf ihr fährt. Treibt den Pfeil und das Herauszoomen.
    private(set) var detour: OffRoute.Fix?
    /// Wie oft der Weg unterwegs neu berechnet wurde. Nur fürs Protokoll.
    private(set) var replans = 0
    private var lastReplan = Date.distantPast
    /// Ab wann neu berechnet wird; 0 schaltet es ab.
    private var replanOffRouteMeters = OffRoute.replanMeters
    private var replanOffRouteMinutes = 0.0
    /// Seit wann ohne Unterbrechung neben der Route.
    private var offSince: Date?
    private var replanTask: Task<Void, Never>?
    private let router = CompositeRouter()

    /// The next turn, recomputed **per fix**, not per redraw. A view that
    /// scans the whole route on every frame is how the map starts to stutter.
    private(set) var nextTurn: (step: TurnGuide.Step, meters: Double)?

    func start(subject: Subject, signals: [CLLocationCoordinate2D],
               route: [CLLocationCoordinate2D] = [],
               roadPoints: [RoadPoint] = [],
               signalSeconds: TimeInterval = RideMeter.defaultSignalSeconds,
               replanOffRouteMeters: Double = OffRoute.replanMeters,
               replanOffRouteMinutes: Double = 0,
               plannedSignals: [CLLocationCoordinate2D] = []) {
        guard !isRecording else { return }
        self.signalSeconds = signalSeconds
        self.replanOffRouteMeters = replanOffRouteMeters
        self.replanOffRouteMinutes = replanOffRouteMinutes
        self.roadPoints = roadPoints
        plannedRoute = route
        originalRoute = route
        routeLengths = TurnGuide.cumulative(route)
        routeIndex = 0
        turns = TurnGuide.steps(on: route)
        nextTurn = nil
        detour = nil
        replans = 0
        offSince = nil
        lastReplan = .distantPast
        replanTask?.cancel()
        replanTask = nil
        self.signals = signals
        self.plannedSignals = plannedSignals
        signalStations = Self.stations(of: plannedSignals, on: route, cum: routeLengths)
        progress = Self.progress(travelled: 0, cum: routeLengths, stations: signalStations)
        switch manager.authorizationStatus {
        case .notDetermined:
            pending = (subject, signals)
            // `plannedRoute` and `turns` are already set; they survive the
            // permission sheet.
            manager.requestWhenInUseAuthorization()
            return
        case .denied, .restricted:
            failure = "Ortung ist für RadPendler nicht erlaubt — in den iOS-Einstellungen freigeben."
            return
        default: break
        }
        begin(subject, signals)
    }

    private var pending: (Subject, [CLLocationCoordinate2D])?
    private var signalSeconds = RideMeter.defaultSignalSeconds
    /// Während einer Fahrt bleibt der Bildschirm an, bis die Fahrt beendet
    /// ist — ohne Schalter. Es gab einen („Bildschirm anlassen", voreingestellt
    /// aus, wegen des Stroms); er ist wieder weg, weil ein Blick auf die Karte
    /// an der Kreuzung nichts nützt, wenn man vorher entsperren muss. Der
    /// Strom, den das kostet, ist der Preis dafür, und er ist gewollt.
    ///
    /// **Einmal setzen reicht nicht.** `isIdleTimerDisabled` gilt nur, solange
    /// die App vorn ist; kommt sie aus dem Hintergrund zurück — und das tut
    /// sie auf einer Fahrt dauernd, weil der Bildschirm sich sperrt und wieder
    /// aufwacht —, steht das Flag wieder auf dem Voreingestellten, und das
    /// Telefon schläft mitten auf der Kreuzung ein. Deshalb wird es bei jeder
    /// Rückkehr nach vorn und bei jeder Ortung neu behauptet; die Zuweisung
    /// kostet nichts, wenn sie schon stimmt.
    private func applyIdleTimer() {
        guard UIApplication.shared.isIdleTimerDisabled != isRecording else { return }
        UIApplication.shared.isIdleTimerDisabled = isRecording
    }
    private var roadPoints: [RoadPoint] = []

    private func begin(_ subject: Subject, _ signals: [CLLocationCoordinate2D]) {
        failure = nil
        finished = nil
        self.subject = subject
        meter = RideMeter()
        meter.signals = signals
        meter.signalSeconds = signalSeconds
        meter.roadPoints = roadPoints
        meter.plannedLine = originalRoute
        // Only now, and only for as long as the ride lasts.
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        applyIdleTimer()
        pushToWatch(force: true)
    }

    /// Ends the recording and keeps what was measured. Returns the ride so the
    /// caller can show its summary; it is already stored either way.
    @discardableResult
    func stop(at end: Date = .now) -> Ride? {
        guard let subject else { return nil }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        meter.finish(at: end)
        let (ride, track) = meter.result(id: subject.id, origin: subject.origin,
                                         destination: subject.destination, mode: subject.mode,
                                         plannedSeconds: subject.plannedSeconds, end: end,
                                         plannedMeters: subject.plannedMeters,
                                         plannedSignals: subject.plannedSignals)
        self.subject = nil
        applyIdleTimer()
        // A ride of thirty seconds is a tap on the wrong button, not a commute.
        if ride.seconds >= 60, ride.meters >= 100 {
            store.add(ride, track: track)
            finished = ride
        }
        store.clearInterrupted()
        pushFinished(ride)
        return finished
    }

    /// The summary sheet was dismissed.
    func clearFinished() { finished = nil }

    // MARK: Live numbers

    func seconds(at now: Date = .now) -> TimeInterval { meter.seconds(at: now) }
    func averageKmh(at now: Date = .now) -> Double { meter.averageKmh(at: now) }

    /// What the watch gets. `running` false is the summary after the ride.
    func live(at now: Date = .now, running: Bool = true) -> RideLive? {
        guard let subject else { return nil }
        return RideLive(origin: subject.origin, destination: subject.destination,
                        mode: subject.mode,
                        symbol: TravelMode(rawValue: subject.mode)?.symbol ?? "bicycle",
                        colorHex: UIColor(TravelMode(rawValue: subject.mode)?.color ?? .green).hexString,
                        started: meter.started ?? now, at: now, running: running,
                        meters: meter.meters, movingSeconds: meter.movingSeconds,
                        currentKmh: meter.currentSpeed * 3.6,
                        signalStops: meter.signalStops, otherStops: meter.otherStops,
                        signalWaitTotal: meter.signalWaitTotal)
    }

    /// Twice a minute would be too slow to watch, once a second is a
    /// Bluetooth message per second for numbers that change by a tenth. Two
    /// seconds reads as live and costs half.
    static let watchInterval: TimeInterval = 2

    private func pushToWatch(force: Bool = false) {
        let now = Date.now
        guard force || now.timeIntervalSince(lastWatchPush) >= Self.watchInterval else { return }
        lastWatchPush = now
        WatchLink.shared.sendLive(live(at: now))
    }

    /// The last picture the wrist gets: the numbers stop moving instead of
    /// vanishing, because the first thing one does after arriving is look.
    private func pushFinished(_ ride: Ride) {
        WatchLink.shared.sendLive(RideLive(origin: ride.origin, destination: ride.destination,
                                           mode: ride.mode,
                                           symbol: ride.travelMode?.symbol ?? "bicycle",
                                           colorHex: UIColor(ride.travelMode?.color ?? .green).hexString,
                                           started: ride.started, at: ride.ended, running: false,
                                           meters: ride.meters, movingSeconds: ride.movingSeconds,
                                           currentKmh: 0, signalStops: ride.signalStops,
                                           otherStops: ride.otherStops,
                                           signalWaitTotal: ride.signalWaitTotal))
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fixes = locations.map {
            RideMeter.Fix(coordinate: $0.coordinate, time: $0.timestamp,
                          speed: $0.speed, accuracy: $0.horizontalAccuracy,
                          altitude: $0.altitude, verticalAccuracy: $0.verticalAccuracy)
        }
        let courses = locations.map(\.course)
        Task { @MainActor in self.accept(fixes, courses) }
    }

    private func accept(_ fixes: [RideMeter.Fix], _ courses: [CLLocationDirection]) {
        guard isRecording else { return }
        applyIdleTimer()
        for fix in fixes { meter.add(fix) }
        if let last = fixes.last {
            here = last.coordinate
            if !turns.isEmpty,
               let n = TurnGuide.next(after: last.coordinate, on: plannedRoute, steps: turns,
                                      cum: routeLengths, from: routeIndex) {
                routeIndex = n.index
                nextTurn = (n.step, n.meters)
                let next = Self.progress(travelled: routeLengths[Swift.min(n.index, routeLengths.count - 1)],
                                         cum: routeLengths, stations: signalStations)
                if progress != next { progress = next }
            }
            updateDetour(at: last.coordinate)
        }
        // The receiver only reports a course while it is sure of one. Standing
        // at a light it reports nothing, and an arrow that disappears or snaps
        // north every time one stops is worse than a slightly stale one — so
        // the last known course stands, and where there never was one, the
        // line itself says which way the ride is going.
        if let c = courses.last, c >= 0 {
            course = c
        } else if course < 0, let derived = Self.courseFromTrack(meter.points) {
            course = derived
        }
        pushToWatch()
        // The app can be killed in a pocket; what was ridden up to then is
        // still a ride, and the next start finds it and files it.
        let now = Date.now
        // Alle halbe Minute, solange die Linie kurz ist — danach seltener.
        // Geschrieben wird jedes Mal die ganze Linie, und was sie kostet,
        // wächst mit der Fahrt; eine Pendelfahrt ist nach dieser Grenze
        // ohnehin vorbei, und eine Tagestour braucht keine Sicherung im
        // Halbminutentakt. (Inkrementell wäre schöner, verlangt aber ein
        // anderes Dateiformat — und seit das Schreiben neben dem Hauptthread
        // läuft und die Kopie gedeckelt ist, kauft das nichts mehr.)
        let every: TimeInterval = meter.points.count > 3_000 ? 120 : 30
        if now.timeIntervalSince(lastSave) >= every {
            lastSave = now
            if let subject {
                store.saveInterrupted(meter.result(id: subject.id, origin: subject.origin,
                                                   destination: subject.destination, mode: subject.mode,
                                                   plannedSeconds: subject.plannedSeconds, end: now,
                                                   plannedMeters: subject.plannedMeters,
                                                   plannedSignals: subject.plannedSignals))
            }
        }
    }

    // MARK: Neben der Route

    /// Einmal je Ortung, also einmal die Sekunde. Zugewiesen wird nur, was sich
    /// unterscheidet: `@Observable` fragt nicht nach, und ein `detour = nil`
    /// auf ein bereits leeres `detour` wäre eine gemeldete Änderung pro
    /// Sekunde — und damit ein Neuaufbau des ganzen Fahrtbildschirms samt
    /// Karte, die ganze Fahrt lang.
    private func updateDetour(at here: CLLocationCoordinate2D) {
        guard !plannedRoute.isEmpty, let fix = OffRoute.nearest(to: here, on: plannedRoute) else {
            if detour != nil { detour = nil }
            return
        }
        let next = OffRoute.isOff(fix.meters, was: detour != nil) ? fix : nil
        if detour != next { detour = next }
        guard let next else { offSince = nil; return }
        let since = offSince ?? .now
        offSince = since
        guard OffRoute.shouldReplan(meters: next.meters,
                                    offFor: Date.now.timeIntervalSince(since),
                                    afterMeters: replanOffRouteMeters,
                                    afterMinutes: replanOffRouteMinutes) else { return }
        replan(from: here)
    }

    /// Über einem Kilometer daneben ist die geplante Linie keine Hilfe mehr,
    /// sondern ein Pfeil auf eine Straße, die man nicht mehr erreicht. Dann
    /// wird der Weg zum Ziel **von hier aus** neu berechnet.
    ///
    /// Das ist die einzige Ausnahme von der Regel, dass die Führung beim Start
    /// der Fahrt einfriert. Die Regel gibt es, damit eine beiläufige
    /// Neuplanung nicht nachträglich umdeutet, was schon gemessen wurde — und
    /// genau das passiert hier nicht: gemessen bleibt, was gemessen wurde, neu
    /// ist nur der Weg nach vorn. Die Ampeln der alten Route bleiben deshalb
    /// stehen; für den neuen Weg gibt es keine Kartendaten, aber die Regel
    /// „ein Halt ab `signalStopSeconds` ist eine Ampel" gilt weiter.
    private func replan(from here: CLLocationCoordinate2D) {
        guard replanTask == nil, Date.now.timeIntervalSince(lastReplan) >= OffRoute.replanEvery,
              let destination = plannedRoute.last else { return }
        lastReplan = .now
        let mode: StreetMode = subject?.mode == TravelMode.car.rawValue ? .car : .bike
        let router = router
        replanTask = Task { [weak self] in
            let route = try? await router.route(from: here, to: destination, mode: mode, departure: nil)
            await MainActor.run { self?.adopt(route) }
        }
    }

    private func adopt(_ route: StreetRoute?) {
        replanTask = nil
        guard isRecording, let route, route.coordinates.count > 1 else { return }
        plannedRoute = route.coordinates
        routeLengths = TurnGuide.cumulative(route.coordinates)
        routeIndex = 0
        turns = TurnGuide.steps(on: route.coordinates)
        // Die Ampeln der alten Route liegen auf der neuen woanders — oder gar
        // nicht mehr. Gezählt wird ab hier gegen den neuen Weg; was schon
        // gemessen wurde, bleibt gemessen.
        signalStations = Self.stations(of: plannedSignals, on: route.coordinates, cum: routeLengths)
        progress = Self.progress(travelled: 0, cum: routeLengths, stations: signalStations)
        nextTurn = nil
        if detour != nil { detour = nil }
        offSince = nil
        replans += 1
        // Die Beläge des neuen Wegs kommen hinten dran. Zugeordnet wird nach
        // Nähe mit einem mitlaufenden Index — was schon zugeordnet ist, bleibt.
        meter.roadPoints += route.roadPoints
    }

    /// Wo auf der Route jede Ampel liegt, in Metern vom Anfang — nur die, die
    /// überhaupt auf ihr liegen. `RouteAnalyzer` hat sie schon einmal der
    /// Linie zugeordnet; hier geht es nur noch um die Reihenfolge, also reicht
    /// der nächste Punkt der Linie.
    nonisolated static func stations(of signals: [CLLocationCoordinate2D],
                                     on route: [CLLocationCoordinate2D], cum: [Double]) -> [Double] {
        guard route.count > 1, cum.count == route.count else { return [] }
        var out: [Double] = []
        for s in signals {
            var best = (d: Double.infinity, at: 0.0)
            for (i, c) in route.enumerated() {
                let d = c.distance(to: s)
                if d < best.d { best = (d, cum[i]) }
            }
            guard best.d <= OffRoute.offMeters else { continue }
            out.append(best.at)
        }
        return out.sorted()
    }

    nonisolated static func progress(travelled: Double, cum: [Double], stations: [Double]) -> Progress {
        let total = cum.last ?? 0
        let passed = stations.filter { $0 <= travelled + 20 }.count
        return Progress(metersLeft: Swift.max(0, total - travelled),
                        signalsLeft: stations.count - passed, signalsPassed: passed,
                        plannedSignals: stations.count, plannedMeters: total)
    }

    /// Bearing of the last stretch actually ridden, for the fixes that carry
    /// no course of their own. `nonisolated` so a test can drive it without
    /// a manager and without the main actor.
    nonisolated static func courseFromTrack(_ points: [RidePoint]) -> CLLocationDirection? {
        guard points.count >= 2 else { return nil }
        let b = points[points.count - 1].coordinate, a = points[points.count - 2].coordinate
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        guard x != 0 || y != 0 else { return nil }
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.isRecording else { return }
            // A single failed fix is normal in a tunnel; only a refusal matters.
            if (error as? CLError)?.code == .denied {
                self.failure = "Ortung ist für RadPendler nicht erlaubt — in den iOS-Einstellungen freigeben."
                self.stop()
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard let (subject, signals) = self.pending else { return }
            switch manager.authorizationStatus {
            case .notDetermined: return
            case .denied, .restricted:
                self.pending = nil
                self.failure = "Ortung ist für RadPendler nicht erlaubt — in den iOS-Einstellungen freigeben."
            default:
                self.pending = nil
                self.begin(subject, signals)
            }
        }
    }
}
