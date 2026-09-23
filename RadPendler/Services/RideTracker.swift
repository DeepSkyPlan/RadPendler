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
    }

    private(set) var subject: Subject?
    private(set) var meter = RideMeter()
    /// Why nothing is being recorded, when something should be.
    private(set) var failure: String?
    /// Where the rider is right now, for the map.
    private(set) var here: CLLocationCoordinate2D?
    /// Degrees from north, for turning the camera with the rider.
    private(set) var course: CLLocationDirection = -1
    /// The next turn on the frozen route, and how far it is — nil once there
    /// is no route, no position, or nothing left to say.
    var nextTurn: (step: TurnGuide.Step, meters: Double)? {
        guard let here, !turns.isEmpty else { return nil }
        return TurnGuide.next(after: here, on: plannedRoute, steps: turns)
    }

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
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
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

    func start(subject: Subject, signals: [CLLocationCoordinate2D],
               route: [CLLocationCoordinate2D] = [],
               signalSeconds: TimeInterval = RideMeter.defaultSignalSeconds) {
        guard !isRecording else { return }
        self.signalSeconds = signalSeconds
        plannedRoute = route
        turns = TurnGuide.steps(on: route)
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

    private func begin(_ subject: Subject, _ signals: [CLLocationCoordinate2D]) {
        failure = nil
        finished = nil
        self.subject = subject
        meter = RideMeter()
        meter.signals = signals
        meter.signalSeconds = signalSeconds
        // Only now, and only for as long as the ride lasts.
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        UIApplication.shared.isIdleTimerDisabled = true
        pushToWatch(force: true)
    }

    /// Ends the recording and keeps what was measured. Returns the ride so the
    /// caller can show its summary; it is already stored either way.
    @discardableResult
    func stop(at end: Date = .now) -> Ride? {
        guard let subject else { return nil }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        UIApplication.shared.isIdleTimerDisabled = false
        meter.finish(at: end)
        let (ride, track) = meter.result(id: subject.id, origin: subject.origin,
                                         destination: subject.destination, mode: subject.mode,
                                         plannedSeconds: subject.plannedSeconds, end: end)
        self.subject = nil
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

    private func pushToWatch(force: Bool = false) {
        let now = Date.now
        guard force || now.timeIntervalSince(lastWatchPush) >= 1 else { return }
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
                          speed: $0.speed, accuracy: $0.horizontalAccuracy)
        }
        let courses = locations.map(\.course)
        Task { @MainActor in self.accept(fixes, courses) }
    }

    private func accept(_ fixes: [RideMeter.Fix], _ courses: [CLLocationDirection]) {
        guard isRecording else { return }
        for fix in fixes { meter.add(fix) }
        if let last = fixes.last { here = last.coordinate }
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
        if now.timeIntervalSince(lastSave) >= 30 {
            lastSave = now
            if let subject {
                store.saveInterrupted(meter.result(id: subject.id, origin: subject.origin,
                                                   destination: subject.destination, mode: subject.mode,
                                                   plannedSeconds: subject.plannedSeconds, end: now))
            }
        }
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
