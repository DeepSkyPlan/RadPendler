import CoreLocation
import XCTest
@testable import RadPendler

/// The three pieces that were added after the first test ride, and that all
/// look plausible while being wrong: an arrow that points the other way, a
/// junction remembered in the wrong place, and a commute that runs backwards
/// at 18:59.
final class GuideTests: XCTestCase {
    private let base = CLLocationCoordinate2D(latitude: 52.5000, longitude: 13.4000)

    private func east(_ m: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: base.latitude,
                               longitude: base.longitude + m / (111_320 * cos(base.latitude * .pi / 180)))
    }

    private func north(_ m: Double, from c: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: c.latitude + m / 111_320, longitude: c.longitude)
    }

    // MARK: Abbiegen

    func testBearingsAndDifferences() {
        XCTAssertEqual(TurnGuide.bearing(from: base, to: north(100, from: base)), 0, accuracy: 0.5)
        XCTAssertEqual(TurnGuide.bearing(from: base, to: east(100)), 90, accuracy: 0.5)
        XCTAssertEqual(TurnGuide.signedDifference(from: 350, to: 10), 20, accuracy: 0.01,
                       "über Norm hinweg, nicht −340")
        XCTAssertEqual(TurnGuide.signedDifference(from: 10, to: 350), -20, accuracy: 0.01)
        XCTAssertEqual(TurnGuide.Turn.from(-75), .left)
        XCTAssertEqual(TurnGuide.Turn.from(75), .right)
        XCTAssertEqual(TurnGuide.Turn.from(5), .straight)
    }

    /// Ein Weg nach Osten, dann nach Norden: genau eine Linkskurve.
    func testAnLShapedRouteHasExactlyOneTurn() {
        var route: [CLLocationCoordinate2D] = []
        for m in stride(from: 0.0, through: 200, by: 10) { route.append(east(m)) }
        let corner = east(200)
        for m in stride(from: 10.0, through: 200, by: 10) { route.append(north(m, from: corner)) }
        let steps = TurnGuide.steps(on: route)
        let turns = steps.filter { $0.turn != .arrive }
        XCTAssertEqual(turns.count, 1, "eine Ecke, ein Hinweis — nicht drei")
        XCTAssertEqual(turns.first?.turn, .left)
        XCTAssertEqual(turns.first?.distance ?? 0, 200, accuracy: 30)
        XCTAssertEqual(steps.last?.turn, .arrive)
    }

    func testAStraightRouteOnlyArrives() {
        let route = stride(from: 0.0, through: 300, by: 10).map { east($0) }
        XCTAssertEqual(TurnGuide.steps(on: route).map(\.turn), [.arrive])
    }

    func testTheNextTurnCountsDownAsOneRides() {
        var route: [CLLocationCoordinate2D] = []
        for m in stride(from: 0.0, through: 200, by: 10) { route.append(east(m)) }
        let corner = east(200)
        for m in stride(from: 10.0, through: 200, by: 10) { route.append(north(m, from: corner)) }
        let steps = TurnGuide.steps(on: route)
        guard let far = TurnGuide.next(after: east(20), on: route, steps: steps),
              let near = TurnGuide.next(after: east(150), on: route, steps: steps) else {
            return XCTFail("kein Hinweis")
        }
        XCTAssertEqual(far.step.turn, .left)
        XCTAssertEqual(near.step.turn, .left)
        XCTAssertLessThan(near.meters, far.meters, "näher dran heißt weniger Meter")
        XCTAssertEqual(near.meters, 50, accuracy: 25)
        // Hinter der Ecke bleibt nur noch das Ziel.
        let after = TurnGuide.next(after: north(150, from: corner), on: route, steps: steps)
        XCTAssertEqual(after?.step.turn, .arrive)
    }

    func testAShortRouteStillArrives() {
        XCTAssertEqual(TurnGuide.steps(on: []).count, 0)
        XCTAssertEqual(TurnGuide.steps(on: [base]).map(\.turn), [.arrive])
        XCTAssertNil(TurnGuide.next(after: base, on: [base], steps: []))
    }

    // MARK: Der Pfeil

    /// Ohne Kurs vom Empfänger muss die Richtung aus der gefahrenen Linie
    /// kommen, sonst zeigt der Pfeil beim Stehen nach Norden.
    func testTheCourseFallsBackToTheRiddenLine() {
        let t = Date(timeIntervalSince1970: 1_780_000_000)
        let points = [RidePoint(lat: base.latitude, lon: base.longitude, t: t, v: 5),
                      RidePoint(lat: east(50).latitude, lon: east(50).longitude, t: t.addingTimeInterval(10), v: 5)]
        XCTAssertEqual(RideTracker.courseFromTrack(points) ?? -1, 90, accuracy: 1)
        XCTAssertNil(RideTracker.courseFromTrack([points[0]]))
    }

    // MARK: Gelernte Ampeln

    func testTheSameJunctionIsLearnedOnce() {
        var list: [LearnedSignal] = []
        list = LearnedSignal.recording(list, at: base, waited: 30)
        // Zwanzig Meter weiter ist dieselbe Kreuzung.
        list = LearnedSignal.recording(list, at: east(20), waited: 50)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].stops, 2)
        XCTAssertEqual(list[0].totalWait, 80)
        XCTAssertEqual(list[0].averageWait, 40)
        // Zweihundert Meter weiter ist eine andere.
        list = LearnedSignal.recording(list, at: east(200), waited: 20)
        XCTAssertEqual(list.count, 2)
    }

    func testTwoDevicesLearnTheSameJunctionWithoutDoubling() {
        let mine = LearnedSignal.recording([], at: base, waited: 30)
        let theirs = LearnedSignal.recording(LearnedSignal.recording([], at: east(15), waited: 40),
                                             at: east(15), waited: 20)
        let merged = LearnedSignal.merging(mine, theirs)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].stops, 3, "einmal hier, zweimal dort")
        XCTAssertEqual(merged[0].totalWait, 90)
        // Nichts geht verloren, was nur eine Seite kannte.
        let far = LearnedSignal.recording([], at: east(500), waited: 25)
        XCTAssertEqual(LearnedSignal.merging(mine, far).count, 2)
    }

    func testTheLearnedListHasACeiling() {
        var list: [LearnedSignal] = []
        for i in 0..<(LearnedSignal.limit + 20) {
            list = LearnedSignal.recording(list, at: east(Double(i) * 200), waited: 20)
        }
        XCTAssertEqual(list.count, LearnedSignal.limit)
    }

    /// Ein halbminütiger Stillstand ist eine Ampel, auch wenn keine Karte dort
    /// eine kennt — das war der Befund der ersten Testfahrt.
    func testALongStopIsARedLightWithoutAnyMap() {
        var m = RideMeter()
        m.signals = []
        m.signalSeconds = 30
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        func fix(_ meters: Double, _ s: Double, _ v: Double) -> RideMeter.Fix {
            RideMeter.Fix(coordinate: east(meters), time: start.addingTimeInterval(s), speed: v, accuracy: 5)
        }
        for i in 0...9 { m.add(fix(Double(i) * 5, Double(i), 5)) }
        for i in 10...50 { m.add(fix(45, Double(i), 0.1)) }     // 40 s Stillstand
        m.finish(at: start.addingTimeInterval(50))
        XCTAssertEqual(m.signalStops, 1)
        XCTAssertEqual(m.otherStops, 0)

        // Zehn Sekunden sind weiterhin nur ein Halt.
        var short = RideMeter()
        short.signalSeconds = 30
        for i in 0...9 { short.add(fix(Double(i) * 5, Double(i), 5)) }
        for i in 10...20 { short.add(fix(45, Double(i), 0.1)) }
        short.finish(at: start.addingTimeInterval(20))
        XCTAssertEqual(short.signalStops, 0)
        XCTAssertEqual(short.otherStops, 1)
    }

    // MARK: Der Doppeltipp

    func testTheCommuteKnowsWhichWayRound() {
        let home = Place(name: "Zuhause", latitude: 52.5, longitude: 13.4)
        let work = Place(name: "Büro", latitude: 52.6, longitude: 13.5)
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let morning = c.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 7, minute: 30))!
        let evening = c.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 18, minute: 30))!

        // Am Ort entscheidet der Ort, nicht die Uhr.
        XCTAssertEqual(AppSettings.commuteDestination(from: home.coordinate, home: home, work: work,
                                                      now: evening, calendar: c)?.name, work.name)
        XCTAssertEqual(AppSettings.commuteDestination(from: work.coordinate, home: home, work: work,
                                                      now: morning, calendar: c)?.name, home.name)
        // Irgendwo sonst entscheidet die Uhr.
        let elsewhere = CLLocationCoordinate2D(latitude: 52.4, longitude: 13.2)
        XCTAssertEqual(AppSettings.commuteDestination(from: elsewhere, home: home, work: work,
                                                      now: morning, calendar: c)?.name, work.name)
        XCTAssertEqual(AppSettings.commuteDestination(from: elsewhere, home: home, work: work,
                                                      now: evening, calendar: c)?.name, home.name)
        // Ohne Ort und ohne Arbeitsadresse bleibt nur Zuhause.
        XCTAssertEqual(AppSettings.commuteDestination(from: nil, home: home, work: nil,
                                                      now: morning, calendar: c)?.name, home.name)
        XCTAssertNil(AppSettings.commuteDestination(from: nil, home: nil, work: nil, now: morning, calendar: c))
    }

    // MARK: Verkehrsarm

    func testTheLowTrafficVariantIsOfferedAndSurvivesAnOldStoredOrder() {
        XCTAssertTrue(BikeVariant.defaultOrder.contains(.lowTraffic))
        XCTAssertEqual(BikeVariant.lowTraffic.title, "verkehrsarm")
        // Ein Gerät, das die Liste vor dieser Version geschrieben hat, darf die
        // neue Variante nicht verschlucken.
        let old = ["balanced", "fastest", "quiet", "shortest"]
        let order: [BikeVariant] = storedOrder(old, fallback: BikeVariant.defaultOrder)
        XCTAssertEqual(order.count, BikeVariant.allCases.count)
        XCTAssertTrue(order.contains(.lowTraffic))
        XCTAssertEqual(order.first, .balanced, "die bekannte Reihenfolge bleibt vorn")
        XCTAssertEqual(BRouterClient.Profile.lowTraffic.rawValue, "fastbike-lowtraffic")
    }
}
