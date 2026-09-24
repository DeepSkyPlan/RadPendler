import CoreLocation
import XCTest
@testable import RadPendler

/// The recording is the part that can be quietly wrong: a stop counted twice,
/// a jump in the receiver taken for a sprint, or a red light credited to a
/// junction two streets away all render as a perfectly plausible ride.
final class RideTests: XCTestCase {
    /// Neutral geometry, like the rest of the fixtures — no address of the
    /// user's is allowed anywhere near this repository.
    private let base = CLLocationCoordinate2D(latitude: 52.5000, longitude: 13.4000)
    private let start = Date(timeIntervalSince1970: 1_780_000_000)

    /// Metres east of `base`, at the latitude of `base`.
    private func east(_ meters: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: base.latitude,
                               longitude: base.longitude + meters / (111_320 * cos(base.latitude * .pi / 180)))
    }

    private func fix(_ meters: Double, _ second: Double, speed: Double, accuracy: Double = 5) -> RideMeter.Fix {
        RideMeter.Fix(coordinate: east(meters), time: start.addingTimeInterval(second),
                      speed: speed, accuracy: accuracy)
    }

    // MARK: Distance and averages

    func testDistanceAndAveragesOfAStraightRun() {
        var m = RideMeter()
        // Ten seconds at 5 m/s, one fix a second.
        for i in 0...10 { m.add(fix(Double(i) * 5, Double(i), speed: 5)) }
        XCTAssertEqual(m.meters, 50, accuracy: 1)
        XCTAssertEqual(m.movingSeconds, 10, accuracy: 0.01)
        XCTAssertEqual(m.movingKmh, 18, accuracy: 0.5)
        XCTAssertEqual(m.averageKmh(at: start.addingTimeInterval(10)), 18, accuracy: 0.5)
        XCTAssertEqual(m.maxSpeed, 5, accuracy: 0.01)
        XCTAssertEqual(m.seconds(at: start.addingTimeInterval(20)), 20, accuracy: 0.01)
        // The door-to-door average counts the standing about, the rolling one
        // does not — that is the whole difference between the two numbers.
        XCTAssertEqual(m.averageKmh(at: start.addingTimeInterval(20)), 9, accuracy: 0.5)
    }

    /// Standing still drifts by a few metres a minute; a hundred of those
    /// would be a hundred metres of street the rider never rode.
    func testStandingStillAddsNoDistance() {
        var m = RideMeter()
        m.add(fix(0, 0, speed: 0))
        for i in 1...30 { m.add(fix(Double(i).truncatingRemainder(dividingBy: 3), Double(i), speed: 0.2)) }
        XCTAssertEqual(m.meters, 0, accuracy: 0.001)
        XCTAssertEqual(m.movingSeconds, 0, accuracy: 0.001)
    }

    // MARK: Stops

    func testAStopIsCountedOnceAndKeepsItsLength() {
        var m = RideMeter()
        for i in 0...4 { m.add(fix(Double(i) * 5, Double(i), speed: 5)) }
        // Twenty seconds at a standstill …
        for i in 5...25 { m.add(fix(20, Double(i), speed: 0.1)) }
        // … then off again.
        for i in 26...30 { m.add(fix(20 + Double(i - 25) * 5, Double(i), speed: 5)) }
        XCTAssertEqual(m.stops.count, 1)
        XCTAssertEqual(m.stops.first?.seconds ?? 0, 22, accuracy: 1.5)
    }

    /// A slow roll dips under the stop threshold all the time; without the gap
    /// between stopping and going every pedal stroke would be a stop.
    func testSlowRollingIsNotAStop() {
        var m = RideMeter()
        var d = 0.0
        for i in 0...40 {
            let v = i % 2 == 0 ? 0.9 : 1.4
            d += v
            m.add(fix(d, Double(i), speed: v))
        }
        XCTAssertEqual(m.stops.count, 0)
    }

    func testAWobbleAtTheKerbIsNoStop() {
        var m = RideMeter()
        for i in 0...4 { m.add(fix(Double(i) * 5, Double(i), speed: 5)) }
        for i in 5...7 { m.add(fix(20, Double(i), speed: 0.2)) }   // three seconds
        for i in 8...12 { m.add(fix(20 + Double(i - 7) * 5, Double(i), speed: 5)) }
        XCTAssertEqual(m.stops.count, 0)
    }

    func testTheLastStopIsClosedByTheEndOfTheRide() {
        var m = RideMeter()
        for i in 0...4 { m.add(fix(Double(i) * 5, Double(i), speed: 5)) }
        for i in 5...20 { m.add(fix(20, Double(i), speed: 0.0)) }
        XCTAssertEqual(m.stops.count, 0, "noch offen, solange niemand wieder losfährt")
        m.finish(at: start.addingTimeInterval(20))
        XCTAssertEqual(m.stops.count, 1)
        XCTAssertEqual(m.stops.first?.seconds ?? 0, 16, accuracy: 1.5)
    }

    // MARK: Red lights

    func testAStopAtALitJunctionIsATrafficLight() {
        var m = RideMeter()
        m.signals = [east(100), east(400)]
        for i in 0...19 { m.add(fix(Double(i) * 5, Double(i), speed: 5)) }   // to 95 m
        for i in 20...40 { m.add(fix(95, Double(i), speed: 0.1)) }
        for i in 41...45 { m.add(fix(95 + Double(i - 40) * 5, Double(i), speed: 5)) }
        m.finish(at: start.addingTimeInterval(45))
        XCTAssertEqual(m.signalStops, 1)
        XCTAssertEqual(m.otherStops, 0)
        XCTAssertEqual(m.signalWaitTotal, 22, accuracy: 1.5)
    }

    func testAStopAwayFromAJunctionIsJustAStop() {
        var m = RideMeter()
        m.signals = [east(400)]
        for i in 0...19 { m.add(fix(Double(i) * 5, Double(i), speed: 5)) }
        for i in 20...40 { m.add(fix(95, Double(i), speed: 0.1)) }
        m.finish(at: start.addingTimeInterval(40))
        XCTAssertEqual(m.signalStops, 0)
        XCTAssertEqual(m.otherStops, 1)
        XCTAssertEqual(m.signalWaitTotal, 0)
    }

    func testTheSignalRadiusIsGenerousButNotEndless() {
        var m = RideMeter()
        m.signals = [base]
        XCTAssertTrue(m.nearSignal(east(RideMeter.signalRadius - 5)))
        XCTAssertFalse(m.nearSignal(east(RideMeter.signalRadius + 15)))
    }

    // MARK: What the receiver gets wrong

    func testBadFixesAreIgnored() {
        var m = RideMeter()
        m.add(fix(0, 0, speed: 5))
        m.add(fix(1000, 1, speed: 5, accuracy: 200))   // a cell-tower guess
        m.add(fix(5, 1, speed: 5))
        XCTAssertEqual(m.meters, 5, accuracy: 0.5)
    }

    /// A jump of a kilometre between two fixes is the receiver finding itself
    /// again, not a sprint. It must not enter the distance.
    func testAJumpIsNotRidden() {
        var m = RideMeter()
        m.add(fix(0, 0, speed: 5))
        m.add(fix(5, 1, speed: 5))
        m.add(fix(1005, 2, speed: -1))
        XCTAssertEqual(m.meters, 5, accuracy: 0.5)
        XCTAssertLessThanOrEqual(m.maxSpeed, RideMeter.maxSpeed)
    }

    /// A tunnel, a pocket, an app the system suspended: the straight line
    /// across the gap is not a stretch that was ridden, and the standstill
    /// before it is of unknown length.
    func testAGapEndsTheStandstillAndAddsNoDistance() {
        var m = RideMeter()
        m.add(fix(0, 0, speed: 0.1))
        m.add(fix(0, 10, speed: 0.1))
        m.add(fix(600, 200, speed: 5))
        m.finish(at: start.addingTimeInterval(200))
        XCTAssertEqual(m.meters, 0, accuracy: 0.5)
        XCTAssertEqual(m.stops.count, 0)
    }

    func testFixesOutOfOrderChangeNothing() {
        var m = RideMeter()
        m.add(fix(0, 10, speed: 5))
        let before = m.meters
        m.add(fix(50, 5, speed: 5))
        XCTAssertEqual(m.meters, before)
    }

    // MARK: The line

    func testTheLineSkipsTheNoiseAndKeepsTheShape() {
        var m = RideMeter()
        // A metre every second: under the step, so the line is carried by the
        // two-second rule instead of by every wobble.
        for i in 0...20 { m.add(fix(Double(i), Double(i), speed: 1.0)) }
        XCTAssertLessThan(m.points.count, 15)
        XCTAssertGreaterThan(m.points.count, 5)
    }

    func testTheResultCarriesEverythingMeasured() {
        var m = RideMeter()
        m.signals = [east(100)]
        for i in 0...19 { m.add(fix(Double(i) * 5, Double(i), speed: 5)) }
        for i in 20...40 { m.add(fix(95, Double(i), speed: 0.1)) }
        let end = start.addingTimeInterval(40)
        m.finish(at: end)
        let id = UUID()
        let (ride, track) = m.result(id: id, origin: "A", destination: "B",
                                     mode: TravelMode.bike.rawValue, plannedSeconds: 600, end: end)
        XCTAssertEqual(ride.id, id)
        XCTAssertEqual(track.id, id)
        XCTAssertEqual(ride.signalStops, 1)
        XCTAssertEqual(ride.pointCount, track.points.count)
        XCTAssertEqual(ride.seconds, 40, accuracy: 0.01)
        XCTAssertEqual(ride.deviationSeconds ?? 0, -560, accuracy: 0.01)
        XCTAssertEqual(ride.travelMode, .bike)
    }

    // MARK: Grouping

    func testRidesFallIntoMonthsAndYearsNewestFirst() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        func ride(_ y: Int, _ m: Int, _ d: Int) -> Ride {
            let t = c.date(from: DateComponents(year: y, month: m, day: d, hour: 8))!
            return Ride(started: t, ended: t.addingTimeInterval(1800), origin: "A", destination: "B",
                        mode: TravelMode.bike.rawValue, meters: 9000, movingSeconds: 1500,
                        maxKmh: 32, signalStops: 4, otherStops: 1, signalWaitTotal: 80,
                        plannedSeconds: nil)
        }
        let years = Ride.grouped([ride(2026, 1, 5), ride(2026, 9, 2), ride(2026, 9, 20), ride(2025, 12, 1)],
                                 calendar: c)
        XCTAssertEqual(years.map(\.id), [2026, 2025])
        XCTAssertEqual(years[0].months.map(\.id), ["2026-09", "2026-01"])
        XCTAssertEqual(years[0].months[0].rides.count, 2)
        // Newest ride first inside the month.
        XCTAssertGreaterThan(years[0].months[0].rides[0].started, years[0].months[0].rides[1].started)
        XCTAssertEqual(years[0].meters, 27000, accuracy: 0.1)
        XCTAssertEqual(years[0].months[0].signalStops, 8)
        XCTAssertEqual(years[1].months[0].title, Ride.monthName(12, calendar: c))
    }

    // MARK: Storage

    private func ride(_ offsetDays: Int, meters: Double = 9000) -> Ride {
        let t = start.addingTimeInterval(Double(offsetDays) * 86_400)
        return Ride(started: t, ended: t.addingTimeInterval(1700), origin: "A", destination: "B",
                    mode: TravelMode.bike.rawValue, meters: meters, movingSeconds: 1400,
                    maxKmh: 34.2, signalStops: 7, otherStops: 2, signalWaitTotal: 190,
                    plannedSeconds: 1800, pointCount: 812)
    }

    /// The summaries travel in the same one-megabyte store as the settings, so
    /// their size is not a detail — it is the reason the lines stay at home.
    func testSummariesPackSmallEnoughForTheKeyValueStore() {
        let rides = (0..<RideStore.maxRides).map { ride(-$0) }
        guard let packed = RideStore.encode(rides) else { return XCTFail("nicht verpackt") }
        XCTAssertLessThan(packed.count, 300_000, "eintausend Fahrten müssen weit unter 1 MB bleiben")
        XCTAssertEqual(RideStore.decode(packed)?.count, RideStore.maxRides)
        XCTAssertEqual(RideStore.decode(packed)?.first, rides.first)
    }

    /// A value written before there was compression still has to read.
    func testUncompressedSummariesStillRead() {
        let rides = [ride(0), ride(-1)]
        let plain = try! JSONEncoder().encode(rides)
        XCTAssertEqual(RideStore.decode(plain)?.count, 2)
    }

    /// Two devices, one list: nothing counted twice, nothing dropped because
    /// the other side had not heard of it yet.
    func testTwoDevicesMergeIntoOneList() {
        let shared = ride(0)
        let mine = [shared, ride(-1)]
        let theirs = [shared, ride(-2)]
        let merged = RideStore.merge(mine, theirs)
        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(Set(merged.map(\.id)).count, 3)
        // Newest first, whichever device it came from.
        XCTAssertEqual(merged.map(\.started), merged.map(\.started).sorted(by: >))
        // Idempotent: merging again changes nothing.
        XCTAssertEqual(RideStore.merge(merged, theirs).count, 3)
    }

    func testTheMergeStopsAtTheCeiling() {
        let mine = (0..<RideStore.maxRides).map { ride(-$0) }
        let theirs = (RideStore.maxRides..<(RideStore.maxRides + 50)).map { ride(-$0) }
        let merged = RideStore.merge(mine, theirs)
        XCTAssertEqual(merged.count, RideStore.maxRides)
        // The oldest go, because the recent months are what the list is for.
        XCTAssertEqual(merged.first, mine.first)
    }

    // MARK: Colours

    func testTheLineIsCutWhereTheColourChanges() {
        // Long enough runs that the smoothing window sits inside them.
        let speeds = Array(repeating: 3.0, count: 8) + Array(repeating: 25.0, count: 8)
            + Array(repeating: 4.0, count: 8)
        let points = speeds.enumerated().map { i, kmh in
            RidePoint(lat: 52.5 + Double(i) / 10_000, lon: 13.4,
                      t: start.addingTimeInterval(Double(i)), v: kmh / 3.6)
        }
        let lines = RouteMapView.Coordinator.lines(of: points, from: 0)
        XCTAssertEqual(lines.first?.step, RideColors.index(3))
        XCTAssertEqual(lines.last?.step, RideColors.index(4))
        XCTAssertTrue(lines.contains { $0.step == RideColors.index(25) })
        // Ein Sprung von 3 auf 25 km/h *führt* durch 8–14 und 14–20: ein paar
        // Übergangsstücke sind richtig. Zwanzig wären es nicht.
        XCTAssertLessThanOrEqual(lines.count, 8)
        // The runs overlap by a point, so the line has no holes at a change.
        XCTAssertEqual(lines.reduce(0) { $0 + $1.pointCount } - (lines.count - 1), points.count)
    }

    /// The receiver reports 19,8 and 20,1 km/h in consecutive seconds. Without
    /// smoothing that is a new overlay every second or two, and a map that
    /// stutters under the thumb for reasons nobody can see.
    func testJitterAroundAColourBoundaryDoesNotShredTheLine() {
        let speeds = (0..<40).map { $0 % 2 == 0 ? 19.6 : 20.4 }
        let points = speeds.enumerated().map { i, kmh in
            RidePoint(lat: 52.5 + Double(i) / 10_000, lon: 13.4,
                      t: start.addingTimeInterval(Double(i)), v: kmh / 3.6)
        }
        let lines = RouteMapView.Coordinator.lines(of: points, from: 0)
        XCTAssertEqual(lines.count, 1, "eine Linie, nicht zwanzig")
    }

    /// The bug that made the whole app feel busy: the radar dropped nineteen
    /// tile overlays and hung them straight back on, every single redraw.
    func testTheRadarSettlesInsteadOfChurning() {
        let frames = (0..<22).map { start.addingTimeInterval(Double($0) * 300) }
        let wanted = RouteMapView.Coordinator.window(around: frames[10], in: frames)
        XCTAssertEqual(wanted.count, 3)

        // Erster Durchlauf: die drei kommen dazu.
        var mounted = Set<Date>()
        var plan = RouteMapView.Coordinator.radarPlan(mounted: mounted, wanted: wanted)
        XCTAssertEqual(plan.add, wanted)
        XCTAssertTrue(plan.drop.isEmpty)
        mounted.formUnion(plan.add)

        // Zweiter Durchlauf, nichts geändert: **nichts** passiert.
        plan = RouteMapView.Coordinator.radarPlan(mounted: mounted, wanted: wanted)
        XCTAssertTrue(plan.add.isEmpty, "was hängt, bleibt hängen")
        XCTAssertTrue(plan.drop.isEmpty, "und wird nicht abgerissen")

        // Eine Minute weiter: genau einer geht, genau einer kommt.
        let next = RouteMapView.Coordinator.window(around: frames[11], in: frames)
        plan = RouteMapView.Coordinator.radarPlan(mounted: mounted, wanted: next)
        XCTAssertEqual(plan.add.count, 1)
        XCTAssertEqual(plan.drop.count, 1)
    }

    func testEverySpeedFindsAColour() {
        XCTAssertEqual(RideColors.index(0), 0)
        XCTAssertEqual(RideColors.index(7.9), 0)
        XCTAssertEqual(RideColors.index(8), 1)
        XCTAssertEqual(RideColors.index(1000), RideColors.steps.count - 1)
        XCTAssertEqual(RideColors.index(.infinity), RideColors.steps.count - 1)
        XCTAssertEqual(RideColors.titles.count, RideColors.steps.count)
    }

    // MARK: Wording

    func testTheStopwatchAndTheSpeedometer() {
        XCTAssertEqual(Fmt.clock(0), "0:00")
        XCTAssertEqual(Fmt.clock(65), "1:05")
        XCTAssertEqual(Fmt.clock(3599), "59:59")
        XCTAssertEqual(Fmt.clock(3600), "1:00:00")
        XCTAssertEqual(Fmt.clock(-5), "0:00")
        XCTAssertTrue(Fmt.kmh(21.34).hasSuffix("km/h"))
        XCTAssertEqual(Fmt.kmh(-1), "– km/h")
    }

    // MARK: What the watch gets

    func testTheWristGetsTheSameNumbers() {
        let live = RideLive(origin: "A", destination: "B", mode: TravelMode.bike.rawValue,
                            symbol: "bicycle", colorHex: "#1FA847",
                            started: start, at: start.addingTimeInterval(600), running: true,
                            meters: 3000, movingSeconds: 500, currentKmh: 22,
                            signalStops: 4, otherStops: 1, signalWaitTotal: 100)
        XCTAssertEqual(live.seconds, 600, accuracy: 0.01)
        XCTAssertEqual(live.averageKmh, 18, accuracy: 0.1)
        XCTAssertEqual(live.movingKmh, 21.6, accuracy: 0.1)
        XCTAssertEqual(live.signalWaitAverage, 25, accuracy: 0.01)
        XCTAssertEqual(live.standingSeconds, 100, accuracy: 0.01)
        let back = try? JSONDecoder().decode(RideLive.self, from: JSONEncoder().encode(live))
        XCTAssertEqual(back, live)
    }
}
