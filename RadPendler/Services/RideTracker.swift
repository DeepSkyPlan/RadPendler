import CoreLocation
import Observation
import simd
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
        /// Apples Fahrzeit für den Weg, der gilt — siehe `Ride.appleSeconds`.
        var appleSeconds: TimeInterval?
        /// Der Kasten „Auto" fuhr Motorrad — landet so in der Fahrt, damit sie
        /// nicht in den Auto-Schnitt eingeht.
        var motorcycle = false
    }

    /// Was `RideMeter` misst, plus was nur der Anlass der Fahrt weiß.
    private func result(_ subject: Subject, end: Date) -> (Ride, RideTrack) {
        var (ride, track) = meter.result(id: subject.id, origin: subject.origin,
                                         destination: subject.destination, mode: subject.mode,
                                         plannedSeconds: subject.plannedSeconds, end: end,
                                         plannedMeters: subject.plannedMeters,
                                         plannedSignals: subject.plannedSignals)
        if subject.motorcycle { ride.motorcycle = true }
        ride.appleSeconds = subject.appleSeconds
        track.events = events.isEmpty ? nil : events
        if replans > 0 {
            track.routes = (pastRoutes + [plannedRoute]).map { Geo.thinned($0).map(TrackPoint.init) }
        }
        return (ride, track)
    }

    // MARK: Protokoll für die Auswertung

    /// Was während der Fahrt geschah — landet in der Linie und in der
    /// geteilten Auswertung (Fahrten → Fahrt → Teilen). Die Fahrt vom
    /// 30.09.2026 ließ sich nicht aufklären, weil niemand wusste, wann neu
    /// geplant wurde und woran es scheiterte; das steht jetzt hier.
    private var events: [RideEvent] = []
    /// Mehr wird es auf keiner Pendelfahrt; eine Endlosschleife soll die
    /// Datei nicht aufblähen.
    static let maxEvents = 400

    private func log(_ kind: String, _ note: String? = nil, at c: CLLocationCoordinate2D? = nil) {
        guard events.count < Self.maxEvents else { return }
        let p = c ?? here ?? CLLocationCoordinate2D()
        events.append(RideEvent(t: .now, lat: (p.latitude * 1e5).rounded() / 1e5,
                                lon: (p.longitude * 1e5).rounded() / 1e5, kind: kind, note: note))
    }

    /// Wann zuletzt eine ungenaue Ortung protokolliert wurde — eine je
    /// halbe Minute reicht, um ein Funkloch zu sehen.
    private var lastPoorFixLog = Date.distantPast

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
        replanner = Replanner()
        super.init()
        replanner.log = { [weak self] kind, note, at in self?.log(kind, note, at: at) }
        replanner.isActive = { [weak self] in self?.isRecording ?? false }
        replanner.onAdopt = { [weak self] route, lights in self?.follow(route, lights: lights) }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.applyIdleTimer() }
        }
        manager.delegate = self
        // `Best`, not `BestForNavigation`: the latter keeps the receiver and
        // its sensor fusion at full tilt for turn-by-turn guidance the app
        // does not give, and it is the most expensive mode there is. On a bike
        // the difference in the drawn line is not visible; in the battery it is.
        tune(.full)
        manager.activityType = .otherNavigation
        // A pause looks like an arrival to iOS and never resumes on its own.
        manager.pausesLocationUpdatesAutomatically = false
    }

    /// Wie genau und wie oft der Empfänger meldet: voll während der Fahrt,
    /// sparsam in der selbst gemachten Pause.
    enum Receiver: Equatable {
        case full, waiting

        var accuracy: CLLocationAccuracy {
            self == .full ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters
        }
        var distanceFilter: CLLocationDistance {
            self == .full ? kCLDistanceFilterNone : RideTracker.wakeMeters
        }
    }

    /// Der Empfänger gehört dem Tracker, nicht der Fahrt, und überlebt sie.
    /// Endete eine Fahrt in der selbst gemachten Pause, blieb er bis 1.13
    /// sparsam — und die nächste Fahrt bekam eine Ortung je fünfzig Meter und
    /// im Stehen gar keine: kein Halt, keine Ampel, 64 m je Punkt
    /// (Fahrten 04.10.2026). Deshalb stellt jeder Start und jedes Ende ihn
    /// wieder voll.
    private(set) var receiver = Receiver.full

    func tune(_ to: Receiver) {
        receiver = to
        manager.desiredAccuracy = to.accuracy
        manager.distanceFilter = to.distanceFilter
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
    var plannedRoute: [CLLocationCoordinate2D] { replanner.plannedRoute }
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
    /// Die Linie, mit der die Fahrt begonnen hat, und jede, die eine
    /// Neuplanung verworfen hat — beides führt der `Replanner`.
    var originalRoute: [CLLocationCoordinate2D] { replanner.originalRoute }
    var pastRoutes: [[CLLocationCoordinate2D]] { replanner.pastRoutes }
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

    /// Neben der Route und neu geplant: das macht der `Replanner`. Was die
    /// Fahrtansicht davon braucht, steht hier unter den alten Namen.
    private let replanner: Replanner
    var detour: OffRoute.Fix? { replanner.detour }
    var replans: Int { replanner.replans }
    var offSince: Date? { replanner.offSince }

    /// The next turn, recomputed **per fix**, not per redraw. A view that
    /// scans the whole route on every frame is how the map starts to stutter.
    private(set) var nextTurn: (step: TurnGuide.Step, meters: Double)?

    func start(_ plan: RidePlan) {
        guard !isRecording else { return }
        tune(.full)
        let route = plan.route
        self.autoStopSeconds = plan.autoStopMinutes * 60
        self.autoPauseSeconds = plan.autoPauseMinutes * 60
        automatic = .full
        self.roadPoints = plan.roadPoints
        replanner.reset(route: route, config: Replanner.Config(
            mode: plan.subject.mode == TravelMode.car.rawValue ? .car : .bike,
            offRouteMeters: plan.replanOffRouteMeters, profile: plan.bikeProfile,
            avoidCobbles: plan.avoidCobbles, via: plan.via, knownSignals: plan.signals))
        routeLengths = TurnGuide.cumulative(route)
        routeIndex = 0
        turns = TurnGuide.steps(on: route)
        nextTurn = nil
        signals = plan.signals
        plannedSignals = plan.plannedSignals
        signalsBehind = 0
        signalStations = Self.stations(of: plannedSignals, on: route, cum: routeLengths)
        progress = Self.progress(travelled: 0, cum: routeLengths, stations: signalStations)
        switch manager.authorizationStatus {
        case .notDetermined:
            pending = plan
            // `plannedRoute` and `turns` are already set; they survive the
            // permission sheet.
            manager.requestWhenInUseAuthorization()
            return
        case .denied, .restricted:
            failure = L("Ortung ist für RadPendler nicht erlaubt — in den iOS-Einstellungen freigeben.")
            return
        default: break
        }
        begin(plan)
    }

    /// Die Fahrt, die auf die Erlaubnis zur Ortung wartet. Der Rest des Plans
    /// ist schon übernommen und übersteht das Abfragefenster.
    private var pending: RidePlan?
    /// Ab wann ein Halt, der keine Ampel ist, die Fahrt beendet; 0 schaltet
    /// es ab.
    private var autoStopSeconds: TimeInterval = 0
    /// Und ab wann er sie nur **anhält**. Das ist der Regelfall: eine Schranke,
    /// ein Stau, ein Schwatz am Straßenrand. Rollt es wieder, läuft die
    /// Aufzeichnung von selbst weiter.
    private var autoPauseSeconds: TimeInterval = 0
    /// Was die Aufzeichnung bei langem Stillstand von selbst tun darf.
    ///
    /// Drei Stellungen, weil zwei nicht reichen: wer im Stau steht, will keine
    /// Pause; wer das Beenden fürchtet, will nur die Pause; und wer beides
    /// nicht will, will durchfahren. Der Knopf auf dem Fahrtbildschirm schaltet
    /// im Kreis, und die Stellung gilt für **diese** Fahrt — beim nächsten
    /// Start steht sie wieder auf `.full`.
    enum Automatic: CaseIterable {
        /// Erst anhalten, später beenden — wie die Einstellungen es sagen.
        case full
        /// Nur beenden. Für die Fahrt, die nicht unterbrochen werden soll.
        case stopOnly
        /// Nichts von beidem.
        case off

        var next: Automatic {
            switch self {
            case .full: .stopOnly
            case .stopOnly: .off
            case .off: .full
            }
        }

        var pauses: Bool { self == .full }
        var stops: Bool { self != .off }

        var symbol: String {
            switch self {
            case .full: "pause.circle"
            case .stopOnly: "stop.circle"
            case .off: "figure.outdoor.cycle"
            }
        }

        var title: String {
            switch self {
            case .full: L("Anhalten und beenden")
            case .stopOnly: L("Nur beenden")
            case .off: L("Durchfahren")
            }
        }
    }

    private(set) var automatic: Automatic = .full
    /// Ob die laufende Pause von der App kommt. Nur sie endet von selbst; eine
    /// Pause per Knopf wartet auf den Knopf.
    private(set) var autoPaused = false
    /// Wo die Pause begann; von dort aus wird gemessen, ob es weitergeht.
    private var pausedAt: CLLocationCoordinate2D?

    /// Eine Stellung weiter. Steht die Aufzeichnung gerade in einer selbst
    /// gemachten Pause und wird das Anhalten abgeschaltet, heißt das:
    /// weiterfahren.
    func cycleAutomatic() {
        automatic = automatic.next
        if !automatic.pauses, autoPaused { resume() }
    }
    /// Ob die letzte Fahrt von selbst endete. Steht in der Zusammenfassung,
    /// sonst fragt sich der Fahrer, wer da auf „beenden" getippt hat.
    private(set) var stoppedByItself = false
    /// Was sonst der Knopf „Fahrt beenden" auslöst — nachmessen, dazulernen,
    /// die eigene Ausrichtung wiederherstellen. Beendet die Fahrt sich selbst, muss
    /// dasselbe passieren, und der Bildschirm ist dabei aus.
    var onAutoStop: (() -> Void)?
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
        let on = isRecording && !meter.isPaused
        guard UIApplication.shared.isIdleTimerDisabled != on else { return }
        UIApplication.shared.isIdleTimerDisabled = on
    }
    private var roadPoints: [RoadPoint] = []

    private func begin(_ plan: RidePlan) {
        let subject = plan.subject
        failure = nil
        finished = nil
        stoppedByItself = false
        self.subject = subject
        meter = RideMeter()
        if TravelMode(rawValue: subject.mode) == .bike { meter.speedLimit = RideMeter.maxBikeSpeed }
        events = []
        lastPoorFixLog = .distantPast
        directionChecked = false
        log("start", "\(subject.mode), Profil \(plan.bikeProfile.rawValue), Pflaster meiden \(plan.avoidCobbles ? "an" : "aus"), "
            + "\(plan.via.count) Fixpunkte, Route \(Int(TurnGuide.cumulative(plannedRoute).last ?? 0)) m, "
            + "Neuplanung ab \(Int(plan.replanOffRouteMeters)) m, App \(RideMeter.appVersion ?? "?")",
            at: plannedRoute.first)
        meter.signals = signals
        meter.roadPoints = roadPoints
        meter.plannedLine = originalRoute
        // Only now, and only for as long as the ride lasts.
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        applyIdleTimer()
        pushToWatch(force: true)
        announcedTurn = nil
        calledTurn = nil
        RideSounds.shared.play(.start)
    }

    /// Welche Abbiegung schon ihren Ton hatte — einer beim Ankündigen, einer
    /// kurz davor, und keiner doppelt, auch wenn der Abstand um die Grenze
    /// herum zappelt.
    private var announcedTurn: TurnGuide.Step?
    /// Ab wie vielen Metern vor einer Abbiegung Pfeil und Ton kommen — je
    /// nachdem, womit gefahren wird.
    var announceMeters: Double {
        TurnGuide.announceMeters(for: subject.flatMap { TravelMode(rawValue: $0.mode) })
    }
    private var calledTurn: TurnGuide.Step?

    private func soundTurn(_ step: TurnGuide.Step, meters: Double) {
        if meters <= TurnGuide.nowMeters, calledTurn != step {
            calledTurn = step
            announcedTurn = step
            RideSounds.shared.play(.turnNow(side: step.turn.side))
        } else if meters <= announceMeters, announcedTurn != step {
            announcedTurn = step
            RideSounds.shared.play(.turnAhead(side: step.turn.side))
        }
    }

    // MARK: Pause

    var isPaused: Bool { meter.isPaused }

    /// Eine gewollte Unterbrechung — Einkauf, Kaffee, Panne. Die Uhr steht,
    /// und mit ihr die Ortung: das ist der einzige Knopf dieser App, der
    /// wirklich Strom spart, denn der Empfänger ist das Teuerste an einer
    /// Aufzeichnung. Der Bildschirm darf währenddessen wieder einschlafen.
    func pause() {
        guard isRecording, !meter.isPaused else { return }
        meter.pause()
        log("pause", "von Hand")
        RideSounds.shared.play(.pause)
        autoPaused = false
        stopPauseWatch()
        // Von Hand angehalten heißt: die Ortung darf ganz aus. Weiter geht es
        // über den Knopf, und der braucht keine Fixe.
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        applyIdleTimer()
        saveInterrupted(at: .now)
        pushToWatch(force: true)
    }

    /// Von selbst angehalten. Anders als beim Knopf bleibt die Ortung an —
    /// nur sparsam: ohne sie wüsste niemand, wann es weitergeht. Hundert Meter
    /// Genauigkeit und ein Filter von fünfzig Metern kosten einen Bruchteil
    /// dessen, was die volle Aufzeichnung kostet, und reichen für die eine
    /// Frage, die jetzt zählt: rollt es wieder?
    private func pauseAutomatically(at now: Date) {
        guard isRecording, !meter.isPaused else { return }
        meter.pause(at: now)
        log("pause", "von selbst")
        RideSounds.shared.play(.pause)
        autoPaused = true
        startPauseWatch()
        pausedAt = here
        tune(.waiting)
        applyIdleTimer()
        saveInterrupted(at: now)
        pushToWatch(force: true)
        Alarm.note(title: L("Fahrt angehalten"),
                   body: L("Du stehst seit %d Minuten. Die Aufzeichnung läuft weiter, sobald es weitergeht.",
                           Int(autoPauseSeconds / 60)))
    }

    /// Während der selbst gemachten Pause kommen kaum Fixe — fünfzig Meter
    /// Filter, und wer parkt, bewegt sich nicht. Ob aus der Pause inzwischen
    /// „angekommen" geworden ist, fragt deshalb eine Uhr, nicht die Ortung.
    /// Ohne sie blieb eine Fahrt, die von selbst angehalten hatte, für immer
    /// angehalten: das Selbstbeenden sah nur Stillstände, keine Pausen.
    private var pauseWatch: Timer?

    private func startPauseWatch() {
        pauseWatch?.invalidate()
        pauseWatch = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.stopIfPausedTooLong() }
        }
    }

    private func stopPauseWatch() {
        pauseWatch?.invalidate()
        pauseWatch = nil
    }

    /// Die Pause beginnt am Anfang des Stillstands, also misst sie dieselbe
    /// Zeit, die das Selbstbeenden sonst am Stillstand gemessen hätte. Die
    /// Fahrt endet dort, wo das Stehen anfing.
    private func stopIfPausedTooLong(at now: Date = .now) {
        guard isRecording, autoPaused, automatic.stops, autoStopSeconds > 0,
              let since = meter.pausedSince, meter.currentPause(at: now) >= autoStopSeconds else { return }
        stop(at: since)
        stoppedByItself = true
        onAutoStop?()
        Alarm.note(title: L("Fahrt beendet"),
                   body: L("Du standst länger als %d Minuten an derselben Stelle — die Aufzeichnung ist gespeichert.", Int(autoStopSeconds / 60)))
    }

    /// So weit muss man sich vom Ort der Pause entfernen, damit die
    /// Aufzeichnung von selbst weiterläuft — oder so schnell wieder sein.
    static let wakeMeters = 50.0
    static let wakeSpeed = 2.0

    func resume() {
        guard isRecording, meter.isPaused else { return }
        meter.resume()
        log("weiter")
        RideSounds.shared.play(.resume)
        autoPaused = false
        pausedAt = nil
        stopPauseWatch()
        tune(.full)
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
        log("ende", "\(replans)× neu geplant")
        stopPauseWatch()
        autoPaused = false
        pausedAt = nil
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        tune(.full)
        meter.finish(at: end)
        RideSounds.shared.play(.stop)
        let (ride, track) = result(subject, end: end)
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

    /// Der Schnitt, den der Plan für diese Fahrt versprochen hat — Tür zu Tür,
    /// wie der gemessene. nil, wenn nichts geplant war.
    var plannedAverageKmh: Double? {
        guard let s = subject, let seconds = s.plannedSeconds, seconds > 0,
              let meters = s.plannedMeters, meters > 0 else { return nil }
        return meters / seconds * 3.6
    }
    func averageKmh(at now: Date = .now) -> Double { meter.averageKmh(at: now) }

    /// What the watch gets. `running` false is the summary after the ride.
    func live(at now: Date = .now, running: Bool = true) -> RideLive? {
        guard let subject else { return nil }
        return RideLive(origin: subject.origin, destination: subject.destination,
                        mode: subject.mode,
                        symbol: subject.motorcycle ? Vehicle.motorcycleSymbol
                            : TravelMode(rawValue: subject.mode)?.symbol ?? "bicycle",
                        colorHex: UIColor(TravelMode(rawValue: subject.mode)?.color ?? .green).hexString,
                        started: meter.started ?? now, at: now, running: running,
                        meters: meter.meters, movingSeconds: meter.movingSeconds,
                        currentKmh: meter.currentSpeed * 3.6,
                        signalStops: meter.signalStops, otherStops: meter.otherStops,
                        signalWaitTotal: meter.signalWaitTotal,
                        pausedSeconds: meter.pausedSeconds + meter.currentPause(at: now),
                        paused: meter.isPaused)
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
                                           symbol: ride.symbol,
                                           colorHex: UIColor(ride.travelMode?.color ?? .green).hexString,
                                           started: ride.started, at: ride.ended, running: false,
                                           meters: ride.meters, movingSeconds: ride.movingSeconds,
                                           currentKmh: 0, signalStops: ride.signalStops,
                                           otherStops: ride.otherStops,
                                           signalWaitTotal: ride.signalWaitTotal))
    }

    // MARK: CLLocationManagerDelegate

    /// Älter als das ist die Ortung aus dem Zwischenspeicher des Empfängers.
    /// `startUpdatingLocation` liefert als Erstes gern die letzte bekannte
    /// Position, und die kann Minuten alt sein — sie würde die Fahrt vor dem
    /// Losfahren beginnen lassen und den gemessenen Schnitt drücken, der über
    /// `calibrate` in **jede** spätere Planung wandert.
    static let maxFixAge: TimeInterval = 5

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let locations = locations.filter { abs($0.timestamp.timeIntervalSinceNow) <= Self.maxFixAge }
        guard !locations.isEmpty else { return }
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
        // Während einer selbst gemachten Pause nimmt das Messwerk nichts an —
        // hier wird nur noch die eine Frage gestellt: rollt es wieder?
        if meter.isPaused {
            if autoPaused, let last = fixes.last, wokeUp(last) { resume() } else { stopIfPausedTooLong() }
            return
        }
        // Vor dem ersten Fix, den das Messwerk annimmt: danach hat es die
        // Beläge schon in der falschen Richtung zugeordnet. Für die Frage
        // „Start oder Ziel?“ bei 400 m reicht eine gröbere Ortung als fürs
        // Messen — drinnen, vor dem Losfahren, kommt oft nichts unter 50 m
        // (1.10.1 drehte deshalb im Test nie um).
        if !directionChecked,
           let first = fixes.first(where: { $0.accuracy >= 0 && $0.accuracy <= Self.directionAccuracy }) {
            directionChecked = true
            let here = first.coordinate
            if let a = plannedRoute.first, let b = plannedRoute.last {
                log("richtung", "\(Int(here.distance(to: a))) m vom Start, \(Int(here.distance(to: b))) m vom Ziel, ±\(Int(first.accuracy)) m", at: here)
            }
            if Self.startsAtEnd(here, route: plannedRoute) { turnAround(at: here) }
        }
        for fix in fixes { meter.add(fix) }
        if let poor = fixes.last(where: { $0.accuracy < 0 || $0.accuracy > RideMeter.maxAccuracy }),
           Date.now.timeIntervalSince(lastPoorFixLog) >= 30 {
            lastPoorFixLog = .now
            log("ungenau", "±\(Int(poor.accuracy)) m — verworfen", at: poor.coordinate)
        }
        if let last = fixes.last {
            here = last.coordinate
            if !turns.isEmpty,
               let n = TurnGuide.next(after: last.coordinate, on: plannedRoute, steps: turns,
                                      cum: routeLengths, from: routeIndex) {
                routeIndex = n.index
                nextTurn = (n.step, n.meters)
                // Neben der Route liegt die Abbiegung auf einer anderen Straße.
                if detour == nil { soundTurn(n.step, meters: n.meters) }
                let next = Self.progress(travelled: routeLengths[Swift.min(n.index, routeLengths.count - 1)],
                                         cum: routeLengths, stations: signalStations, behind: signalsBehind)
                if progress != next { progress = next }
            }
            // Nur mit einer Ortung, der das Messwerk selbst traut. Beim
            // Losfahren ohne Netz kommen Ortungen aus Funkzellen, Hunderte
            // Meter daneben — und jede davon war „neben der Route" und eine
            // Neuplanung von einem Ort, an dem niemand war (Fahrt 30.09.2026).
            if last.accuracy >= 0, last.accuracy <= RideMeter.maxAccuracy {
                replanner.update(at: last.coordinate, course: course)
            }
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
        // Zwei Stufen, beide gegen denselben Stillstand gemessen und beide
        // abschaltbar: nach ein paar Minuten hält die Aufzeichnung an und
        // wartet darauf, dass es weitergeht; erst nach langer Zeit ist der
        // Fahrer angekommen und hat das Beenden vergessen.
        if automatic != .off,
           let stand = meter.standstill(at: Date.now, beyond: autoPauseSeconds * 2) {
            if automatic.stops, autoStopSeconds > 0, stand.seconds >= autoStopSeconds {
                stop(at: stand.since)
                stoppedByItself = true
                onAutoStop?()
                Alarm.note(title: L("Fahrt beendet"),
                           body: L("Du standst länger als %d Minuten an derselben Stelle — die Aufzeichnung ist gespeichert.", Int(autoStopSeconds / 60)))
                return
            }
            if automatic.pauses, autoPauseSeconds > 0, stand.seconds >= autoPauseSeconds {
                pauseAutomatically(at: Date.now)
                return
            }
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
        if now.timeIntervalSince(lastSave) >= every { saveInterrupted(at: now) }
    }

    // MARK: Falsch herum

    /// Ob die erste brauchbare Ortung schon geprüft hat, in welche Richtung
    /// die Fahrt geht.
    private var directionChecked = false

    /// Losgefahren am **Ziel** der geplanten Linie, nicht an ihrem Anfang:
    /// auf dem Bildschirm stand noch der Hinweg vom Morgen, gefahren wird der
    /// Heimweg (Fahrt 01.10.2026). Die Linie deckt sich fast mit dem
    /// Rückweg, also merkt die Neuplanung nichts — aber Restweg und Restzeit
    /// zählen hoch statt herunter, und geführt wird auf der Gegenfahrbahn.
    nonisolated static func startsAtEnd(_ here: CLLocationCoordinate2D,
                                        route: [CLLocationCoordinate2D]) -> Bool {
        guard let start = route.first, let end = route.last else { return false }
        // Auf einer kurzen Strecke ist 400 m die halbe Strecke: der Test am
        // 02.10.2026 (Start und Ziel 480 m auseinander, 84 m vom Ziel
        // losgegangen) fiel deshalb ganz aus der Prüfung. Die Grenze ist ein
        // Drittel des Abstands, höchstens 400 m — näher am Ziel heißt dann
        // immer auch: weit genug vom Start.
        let radius = Swift.min(endMeters, start.distance(to: end) / 3)
        guard radius >= minEndMeters else { return false }
        return here.distance(to: end) < radius && here.distance(to: start) > radius
    }

    /// So nah am Ende heißt „dort losgefahren" — dieselbe Grenze wie beim
    /// Erraten der Pendelrichtung (`AppSettings.commuteDestination`).
    static let endMeters = 400.0
    /// Darunter liegen Start und Ziel so dicht, dass die Ortung sie nicht
    /// auseinanderhält (Start und Ziel unter 150 m).
    static let minEndMeters = 50.0
    /// So genau muss die Ortung für diese Frage sein — die Hälfte der Grenze.
    static let directionAccuracy = 200.0

    /// Dreht die Fahrt um: Anlass, Linie, Abbiegungen, Ampeln, Beläge — und
    /// plant den Weg zum bisherigen Start neu, auch wenn die Neuplanung
    /// unterwegs abgeschaltet ist; die umgedrehte Linie ist nur ein Behelf.
    private func turnAround(at here: CLLocationCoordinate2D) {
        if var s = subject {
            (s.origin, s.destination) = (s.destination, s.origin)
            subject = s
        }
        replanner.turnAround()
        let route = plannedRoute
        routeLengths = TurnGuide.cumulative(route)
        routeIndex = 0
        turns = TurnGuide.steps(on: route)
        nextTurn = nil
        signalStations = Self.stations(of: plannedSignals, on: route, cum: routeLengths)
        progress = Self.progress(travelled: 0, cum: routeLengths, stations: signalStations)
        roadPoints.reverse()
        meter.roadPoints = roadPoints
        meter.plannedLine = originalRoute
        log("verkehrt", "am Ziel losgefahren — Richtung gedreht", at: here)
        replanner.replan(from: here, course: course)
    }

    // MARK: Neues Ziel

    /// Unterwegs woandershin: Ziel im Anlass, Weg dorthin von hier. Was der
    /// Plan versprochen hat — Zeit, Länge, Ampeln —, galt dem alten Ziel; es
    /// fällt weg, damit hinterher nichts gegen einen Plan verglichen wird, der
    /// nie gefahren werden sollte.
    func changeDestination(to place: Place) {
        guard var s = subject else { return }
        s.destination = place.shortName
        s.plannedSeconds = nil
        s.plannedMeters = nil
        s.plannedSignals = nil
        s.appleSeconds = nil
        subject = s
        log("neues ziel", place.shortName, at: here)
        guard let from = here ?? plannedRoute.first else { return }
        replanner.redirect(to: place.coordinate, from: from, course: course)
        pushToWatch(force: true)
    }

    private func saveInterrupted(at now: Date) {
        guard let subject else { return }
        lastSave = now
        store.saveInterrupted(result(subject, end: now))
    }

    // MARK: Ampeln und Fortschritt

    /// Eine Neuplanung ist übernommen: Abbiegungen, Ampeln und Beläge gelten
    /// ab hier gegen den neuen Weg.
    private func follow(_ route: StreetRoute, lights: [CLLocationCoordinate2D]) {
        // Apples Ansage gilt ab hier dem neuen Weg: was schon gefahren ist,
        // plus was Apple für den Rest braucht.
        if subject?.mode == TravelMode.car.rawValue {
            subject?.appleSeconds = Self.appleSeconds(elapsed: meter.seconds(at: .now), rest: route.expectedTravelTime)
        }
        signalsBehind = progress?.signalsPassed ?? signalsBehind
        routeLengths = TurnGuide.cumulative(route.coordinates)
        routeIndex = 0
        turns = TurnGuide.steps(on: route.coordinates)
        // Die Ampeln der alten Route liegen auf der neuen woanders — oder gar
        // nicht mehr. Gezählt wird ab hier gegen den neuen Weg; was schon
        // gemessen wurde, bleibt gemessen.
        signalStations = Self.stations(of: lights, on: route.coordinates, cum: routeLengths)
        progress = Self.progress(travelled: 0, cum: routeLengths, stations: signalStations, behind: signalsBehind)
        nextTurn = nil
        // Die Beläge des neuen Wegs kommen hinten dran. Zugeordnet wird nach
        // Nähe mit einem mitlaufenden Index — was schon zugeordnet ist, bleibt.
        meter.addRoadPoints(route.roadPoints)
    }

    /// Apples Fahrzeit nach einer Neuplanung. nil, wenn Apple für den Rest
    /// keine Zeit genannt hat — dann lieber keine Ansage als die alte.
    nonisolated static func appleSeconds(elapsed: TimeInterval, rest: TimeInterval) -> TimeInterval? {
        rest > 0 ? Swift.max(0, elapsed) + rest : nil
    }

    /// Wo auf der Route jede Ampel liegt, in Metern vom Anfang — nur die, die
    /// überhaupt auf ihr liegen. `RouteAnalyzer` hat sie schon einmal der
    /// Linie zugeordnet; hier geht es nur noch um die Reihenfolge, also reicht
    /// der nächste Punkt der Linie.
    nonisolated static func stations(of signals: [CLLocationCoordinate2D],
                                     on route: [CLLocationCoordinate2D], cum: [Double]) -> [Double] {
        guard route.count > 1, cum.count == route.count else { return [] }
        // Gegen die **Strecken** zwischen den Stützpunkten, nicht gegen die
        // Stützpunkte selbst: eine gerade Straße hat oft nur alle paar hundert
        // Meter einen, und eine Ampel mittendrin lag dann weiter als
        // `offMeters` von jedem entfernt — sie fiel aus der Zählung.
        let flat = Flat(latitude: route[0].latitude)
        let pts = route.map(flat.point)
        var out: [Double] = []
        for s in signals {
            let p = flat.point(s)
            var best = (d: Double.infinity, at: 0.0)
            for i in 0..<(pts.count - 1) {
                let a = pts[i], ab = pts[i + 1] - a
                let len2 = simd_length_squared(ab)
                let t = len2 > 0 ? Swift.min(Swift.max(simd_dot(p - a, ab) / len2, 0), 1) : 0
                let d = simd_length(p - (a + ab * t))
                if d < best.d { best = (d, cum[i] + t * (cum[i + 1] - cum[i])) }
            }
            guard best.d <= Self.stationMeters else { continue }
            out.append(best.at)
        }
        // Eine Kreuzung mit mehreren Ampelknoten ist eine Ampel.
        var merged: [Double] = []
        for s in out.sorted() where merged.last.map({ s - $0 > Self.stationMerge }) ?? true { merged.append(s) }
        return merged
    }

    /// So nah muss eine Ampel an der Linie liegen, um auf ihr zu zählen —
    /// dieselbe Grenze wie beim Planen (`RouteAnalyzer`: 15 m), mit etwas
    /// Luft für Linien, die die Fahrbahnmitte und nicht den Radweg zeichnen.
    static let stationMeters = 25.0
    /// Und so nah beieinander sind zwei Ampeln eine Kreuzung.
    static let stationMerge = 40.0

    nonisolated static func progress(travelled: Double, cum: [Double], stations: [Double],
                                     behind: Int = 0) -> Progress {
        let total = cum.last ?? 0
        let passed = stations.filter { $0 <= travelled + 20 }.count
        return Progress(metersLeft: Swift.max(0, total - travelled),
                        signalsLeft: stations.count - passed, signalsPassed: behind + passed,
                        plannedSignals: behind + stations.count, plannedMeters: total)
    }

    /// Ampeln, die vor der letzten Neuplanung schon hinter einem lagen. Die
    /// Anzeige „5/27" zählt die ganze Fahrt, nicht nur den neuen Weg — sonst
    /// stand nach einer Neuplanung „5/7" da, weil von der alten Route nur
    /// sieben Ampeln auf der neuen lagen.
    private var signalsBehind = 0

    /// Ob diese Ortung heißt, dass es weitergeht: schnell genug, oder weit
    /// genug weg von der Stelle, an der die Pause begann. Beides, weil der
    /// Empfänger im Sparbetrieb oft keine Geschwindigkeit liefert.
    private func wokeUp(_ fix: RideMeter.Fix) -> Bool {
        if fix.speed >= Self.wakeSpeed { return true }
        guard let from = pausedAt else { return false }
        return from.distance(to: fix.coordinate) >= Self.wakeMeters
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
                self.failure = L("Ortung ist für RadPendler nicht erlaubt — in den iOS-Einstellungen freigeben.")
                self.stop()
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard let plan = self.pending else { return }
            switch manager.authorizationStatus {
            case .notDetermined: return
            case .denied, .restricted:
                self.pending = nil
                self.failure = L("Ortung ist für RadPendler nicht erlaubt — in den iOS-Einstellungen freigeben.")
            default:
                self.pending = nil
                self.begin(plan)
            }
        }
    }
}
