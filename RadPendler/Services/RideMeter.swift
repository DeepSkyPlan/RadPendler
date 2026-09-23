import CoreLocation
import Foundation

/// Turns a stream of fixes into a ride: the line, the distance, the stops and
/// the numbers underneath them.
///
/// It knows nothing about `CLLocationManager`, which is the point — a ride is
/// a sequence of four numbers per fix, and a test can hand it any sequence it
/// likes. Everything that could be quietly wrong (a stop counted twice, a
/// jump in the receiver taken for a sprint, a red light two streets away
/// credited to the wrong junction) is decided in here.
struct RideMeter {
    struct Fix: Equatable {
        var coordinate: CLLocationCoordinate2D
        var time: Date
        /// Metres per second from the receiver; negative means it does not know.
        var speed: Double = -1
        /// Metres of horizontal uncertainty; negative means the fix is invalid.
        var accuracy: Double = 5

        static func == (a: Fix, b: Fix) -> Bool {
            a.coordinate.latitude == b.coordinate.latitude
                && a.coordinate.longitude == b.coordinate.longitude
                && a.time == b.time && a.speed == b.speed && a.accuracy == b.accuracy
        }
    }

    /// Worse than this and the fix says more about the sky than about the rider.
    static let maxAccuracy = 50.0
    /// Under this the rider counts as standing …
    static let stopSpeed = 1.0
    /// … and only over this as moving again. The gap keeps a slow roll from
    /// flickering between the two states and inventing a stop per pedal stroke.
    static let goSpeed = 1.8
    /// Shorter than this is a wobble at a kerb, not a stop worth counting.
    static let minStop: TimeInterval = 5.0
    /// How close a standstill has to be to a lit junction to be a red light.
    /// Wider than it sounds: one waits at the stop line, and the junction is
    /// the node in the middle of it.
    static let signalRadius = 45.0
    /// Two fixes further apart in time than this are a gap — a tunnel, a
    /// pocket, a suspended app — and the straight line between them is not a
    /// stretch that was ridden.
    static let maxGap: TimeInterval = 30
    /// Nobody commutes faster than 108 km/h. A jump past it is the receiver.
    static let maxSpeed = 30.0
    /// Under this the line does not move; recording it anyway would fill the
    /// track with the receiver's own noise while standing at a light.
    static let minStep = 4.0
    /// … but a point every two seconds regardless, so a slow stretch still
    /// has a line and the times stay attached to it.
    static let maxPointGap: TimeInterval = 2.0

    /// Lit junctions of the planned route, plus the ones this rider has been
    /// stopped at before — what turns a standstill into a traffic light.
    var signals: [CLLocationCoordinate2D] = []

    /// A standstill at least this long is a red light wherever it happens.
    /// OpenStreetMap does not know every light, and it knows none of the
    /// crossings that merely behave like one; half a minute standing on a
    /// commute is not something one does for the view.
    var signalSeconds: TimeInterval = RideMeter.defaultSignalSeconds
    static let defaultSignalSeconds: TimeInterval = 30

    /// The planned route with the kind of road each stretch is. Empty means
    /// nobody classified it, and then `mix` stays empty too — an empty bar is
    /// an honest "not known", a full one would be a guess.
    var roadPoints: [RoadPoint] = []
    private(set) var mix = RoadMix()
    private var roadIndex = 0

    private(set) var points: [RidePoint] = []
    private(set) var stops: [RideStop] = []
    private(set) var meters = 0.0
    private(set) var movingSeconds: TimeInterval = 0
    private(set) var maxSpeed = 0.0
    private(set) var started: Date?
    private(set) var lastFix: Fix?
    private(set) var currentSpeed = 0.0

    private var lastPoint: Fix?
    private var standingSince: Date?
    private var standingAt: CLLocationCoordinate2D?

    var signalStops: Int { stops.filter(\.atSignal).count }
    var otherStops: Int { stops.count - signalStops }
    var signalWaitTotal: TimeInterval { stops.filter(\.atSignal).reduce(0) { $0 + $1.seconds } }
    var isStanding: Bool { standingSince != nil }

    func seconds(at now: Date) -> TimeInterval {
        guard let started else { return 0 }
        return max(0, now.timeIntervalSince(started))
    }

    /// Door to door, standing time included — the honest average.
    func averageKmh(at now: Date) -> Double {
        let t = seconds(at: now)
        return t > 0 ? meters / t * 3.6 : 0
    }

    var movingKmh: Double { movingSeconds > 0 ? meters / movingSeconds * 3.6 : 0 }

    // MARK: Feeding

    /// One fix in. Everything that follows from it — the step, the stop, the
    /// point on the line — happens here and nowhere else.
    mutating func add(_ fix: Fix) {
        guard fix.accuracy >= 0, fix.accuracy <= Self.maxAccuracy, Geo.valid(fix.coordinate) else { return }
        guard let previous = lastFix else {
            begin(with: fix)
            return
        }
        let dt = fix.time.timeIntervalSince(previous.time)
        // Fixes out of order, or the same one twice: nothing happened.
        guard dt > 0 else { return }
        let step = previous.coordinate.distance(to: fix.coordinate)
        let gap = dt > Self.maxGap
        // What the receiver says, else what the step implies. A step across a
        // gap implies nothing — it is not a stretch that was ridden.
        let speed = fix.speed >= 0 ? fix.speed : (gap ? 0 : step / dt)
        let jump = !gap && step / dt > Self.maxSpeed

        currentSpeed = min(max(speed, 0), Self.maxSpeed)
        if !gap, !jump {
            // Distance only while moving: standing at a light for two minutes
            // otherwise walks the rider a hundred metres down the street.
            if currentSpeed >= Self.stopSpeed {
                meters += step
                movingSeconds += dt
                attribute(step, at: fix.coordinate)
            }
            maxSpeed = Swift.max(maxSpeed, currentSpeed)
        }
        updateStops(fix, gap: gap)
        record(fix)
        lastFix = fix
    }

    /// Which kind of road these metres were ridden on. Off the planned line
    /// by more than `RoadPoint.matchRadius`, the honest answer is "sonstiges";
    /// that is also what a detour looks like, and it should.
    private mutating func attribute(_ metres: Double, at c: CLLocationCoordinate2D) {
        guard !roadPoints.isEmpty else { return }
        guard let match = RoadPoint.nearest(roadPoints, to: c, from: roadIndex) else {
            mix.add(metres, to: .other)
            return
        }
        roadIndex = match.index
        mix.add(metres, to: match.cls)
    }

    private mutating func begin(with fix: Fix) {
        started = started ?? fix.time
        currentSpeed = fix.speed >= 0 ? Swift.min(fix.speed, Self.maxSpeed) : 0
        lastFix = fix
        record(fix, force: true)
    }

    /// A point joins the line when it moved the line, or when two seconds
    /// passed — whichever comes first.
    private mutating func record(_ fix: Fix, force: Bool = false) {
        guard points.count < Geo.maxPoints else { return }
        if !force, let last = lastPoint {
            let moved = last.coordinate.distance(to: fix.coordinate)
            guard moved >= Self.minStep || fix.time.timeIntervalSince(last.time) >= Self.maxPointGap else { return }
        }
        lastPoint = fix
        points.append(RidePoint(lat: fix.coordinate.latitude, lon: fix.coordinate.longitude,
                                t: fix.time, v: currentSpeed))
    }

    /// Standing starts under `stopSpeed` and ends over `goSpeed`. A gap ends a
    /// standstill too: what happened during it is not known, and a stop of
    /// unknown length is worse than none.
    private mutating func updateStops(_ fix: Fix, gap: Bool) {
        if gap {
            standingSince = nil
            standingAt = nil
            return
        }
        if standingSince == nil, currentSpeed < Self.stopSpeed {
            standingSince = lastFix?.time ?? fix.time
            standingAt = fix.coordinate
        } else if let since = standingSince, currentSpeed > Self.goSpeed {
            close(since: since, until: fix.time)
        }
    }

    private mutating func close(since: Date, until: Date) {
        let seconds = until.timeIntervalSince(since)
        if seconds >= Self.minStop, let at = standingAt {
            stops.append(RideStop(lat: at.latitude, lon: at.longitude, start: since,
                                  seconds: seconds,
                                  atSignal: nearSignal(at) || seconds >= signalSeconds))
        }
        standingSince = nil
        standingAt = nil
    }

    /// The last standstill has no fix to end it — the ride ends instead.
    mutating func finish(at end: Date) {
        if let since = standingSince { close(since: since, until: end) }
        currentSpeed = 0
    }

    /// Flat approximation on purpose: this runs against every lit junction of
    /// the route for every stop, and at 45 m the curvature of the earth is
    /// not what decides it.
    func nearSignal(_ c: CLLocationCoordinate2D) -> Bool {
        guard !signals.isEmpty else { return false }
        let mPerDegLat = 111_320.0
        let mPerDegLon = mPerDegLat * cos(c.latitude * .pi / 180)
        let r2 = Self.signalRadius * Self.signalRadius
        return signals.contains { s in
            let dx = (s.longitude - c.longitude) * mPerDegLon
            let dy = (s.latitude - c.latitude) * mPerDegLat
            return dx * dx + dy * dy <= r2
        }
    }

    /// Everything measured, as the two records that get stored.
    func result(id: UUID, origin: String, destination: String, mode: String,
                plannedSeconds: TimeInterval?, end: Date) -> (Ride, RideTrack) {
        let ride = Ride(id: id, started: started ?? end, ended: end,
                        origin: origin, destination: destination, mode: mode,
                        meters: meters, movingSeconds: movingSeconds, maxKmh: maxSpeed * 3.6,
                        signalStops: signalStops, otherStops: otherStops,
                        signalWaitTotal: signalWaitTotal, plannedSeconds: plannedSeconds,
                        pointCount: points.count, mix: mix.isEmpty ? nil : mix)
        return (ride, RideTrack(id: id, points: points, stops: stops))
    }
}
