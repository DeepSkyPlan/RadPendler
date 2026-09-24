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

    /// Die Suche darf nicht bei jedem Fix die ganze Route abklappern — sonst
    /// ruckelt die Karte. Mit vorberechneten Längen und einem Startindex muss
    /// dasselbe herauskommen wie ohne.
    func testTheCheapSearchFindsTheSameTurn() {
        var route: [CLLocationCoordinate2D] = []
        for m in stride(from: 0.0, through: 400, by: 5) { route.append(east(m)) }
        let corner = east(400)
        for m in stride(from: 5.0, through: 400, by: 5) { route.append(north(m, from: corner)) }
        let steps = TurnGuide.steps(on: route)
        let cum = TurnGuide.cumulative(route)
        var index = 0
        for m in stride(from: 0.0, through: 380, by: 20) {
            guard let plain = TurnGuide.next(after: east(m), on: route, steps: steps),
                  let cheap = TurnGuide.next(after: east(m), on: route, steps: steps,
                                             cum: cum, from: index) else {
                return XCTFail("kein Hinweis bei \(m) m")
            }
            XCTAssertEqual(cheap.step, plain.step)
            XCTAssertEqual(cheap.meters, plain.meters, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(cheap.index, index, "der Index läuft mit, nicht zurück")
            index = cheap.index
        }
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
        XCTAssertEqual(BikeVariant.lowTraffic.title, "wenig Halts")
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

/// Die Wegtypen kommen aus BRouters eigenen Segmentdaten — keine neue Quelle,
/// kein Schlüssel. Falsch zugeordnet sehen sie trotzdem völlig plausibel aus.
final class RoadMixTests: XCTestCase {
    func testTagsBecomeClasses() {
        XCTAssertEqual(RoadClass.from(wayTags: "highway=primary surface=asphalt"), .main)
        XCTAssertEqual(RoadClass.from(wayTags: "highway=residential oneway=yes"), .side)
        XCTAssertEqual(RoadClass.from(wayTags: "highway=cycleway"), .cycleway)
        XCTAssertEqual(RoadClass.from(wayTags: "highway=path surface=ground"), .path)
        XCTAssertEqual(RoadClass.from(wayTags: "highway=footway"), .footway)
        XCTAssertEqual(RoadClass.from(wayTags: "railway=rail"), .other, "ohne highway keine Klasse")
        XCTAssertEqual(RoadClass.from(wayTags: ""), .other)
    }

    /// Ein Fußweg mit `bicycle=designated` ist unter dem Rad ein Radweg, und
    /// eine Hauptstraße mit eigenem Radweg daneben auch.
    func testAWayThatRidesLikeABikePathCountsAsOne() {
        XCTAssertEqual(RoadClass.from(wayTags: "highway=footway bicycle=designated"), .cycleway)
        XCTAssertEqual(RoadClass.from(wayTags: "highway=residential bicycle=designated"), .cycleway)
        XCTAssertEqual(RoadClass.from(wayTags: "highway=primary cycleway:right=track"), .cycleway)
        // Eine Spur auf der Fahrbahn ist kein eigener Weg.
        XCTAssertEqual(RoadClass.from(wayTags: "highway=primary cycleway:right=lane"), .main)
    }

    /// Die Spalten werden über ihre Namen gelesen: BRouter hat ihre Reihenfolge
    /// zwischen Versionen schon geändert.
    func testTheSegmentTableIsReadByColumnName() {
        let messages = [
            ["Longitude", "Latitude", "Elevation", "Distance", "WayTags"],
            ["13396274", "52517532", "34", "100", "highway=primary surface=asphalt"],
            ["13396297", "52517422", "34", "300", "highway=residential"],
            ["13396305", "52517378", "34", "600", "highway=cycleway"],
            ["13396310", "52517353", "34", "kaputt", "highway=cycleway"],
        ]
        let roads = BRouterClient.roads(messages)
        XCTAssertEqual(roads.mix[.main], 100)
        XCTAssertEqual(roads.mix[.side], 300)
        XCTAssertEqual(roads.mix[.cycleway], 600)
        XCTAssertEqual(roads.mix.total, 1000, "die kaputte Zeile zählt nicht mit")
        XCTAssertEqual(roads.mix.share(.cycleway), 0.6, accuracy: 0.001)
        XCTAssertEqual(roads.mix.headline, "60 % Radweg")
        XCTAssertEqual(roads.mix.present, [.main, .side, .cycleway], "feste Reihenfolge")
        // Die Koordinaten kommen als ganze Mikrograd. Die kaputte Zeile fällt
        // ganz weg — halb gelesen ist schlechter als gar nicht.
        XCTAssertEqual(roads.points.count, 3)
        XCTAssertEqual(roads.points[0].lat, 52.517532, accuracy: 0.000001)
        XCTAssertEqual(roads.points[0].cls, .main)
        XCTAssertTrue(BRouterClient.roads(nil).mix.isEmpty)
        XCTAssertTrue(BRouterClient.roads([["was", "anderes"]]).mix.isEmpty)
    }

    /// Eine leere Mischung ist „nicht bekannt", nicht „alles Hauptstraße".
    func testAnEmptyMixSaysNothing() {
        let empty = RoadMix()
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(empty.share(.main), 0)
        XCTAssertNil(empty.headline)
        XCTAssertEqual(empty.present, [])
    }

    /// Die gefahrene Strecke wird der geplanten Linie zugeordnet — und was
    /// daneben liegt, heißt „sonstiges" und nicht einfach die letzte Klasse.
    func testARideIsAttributedToTheRouteItWasPlannedOn() {
        let base = CLLocationCoordinate2D(latitude: 52.5, longitude: 13.4)
        func east(_ m: Double) -> CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: base.latitude,
                                   longitude: base.longitude + m / (111_320 * cos(base.latitude * .pi / 180)))
        }
        // Erste 100 m Hauptstraße, dann Radweg.
        var points: [RoadPoint] = []
        for m in stride(from: 0.0, through: 100, by: 10) {
            points.append(RoadPoint(lat: east(m).latitude, lon: east(m).longitude, cls: .main))
        }
        for m in stride(from: 110.0, through: 300, by: 10) {
            points.append(RoadPoint(lat: east(m).latitude, lon: east(m).longitude, cls: .cycleway))
        }
        var m = RideMeter()
        m.roadPoints = points
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        for i in 0...30 {
            m.add(RideMeter.Fix(coordinate: east(Double(i) * 10), time: start.addingTimeInterval(Double(i) * 2),
                                speed: 5, accuracy: 5))
        }
        XCTAssertEqual(m.mix[.main], 100, accuracy: 15)
        XCTAssertEqual(m.mix[.cycleway], 200, accuracy: 20)
        XCTAssertEqual(m.mix.total, m.meters, accuracy: 1, "was gefahren wurde, ist auch zugeordnet")

        // Ohne Klassifizierung bleibt die Mischung leer statt geraten.
        var blind = RideMeter()
        for i in 0...10 {
            blind.add(RideMeter.Fix(coordinate: east(Double(i) * 10), time: start.addingTimeInterval(Double(i) * 2),
                                    speed: 5, accuracy: 5))
        }
        XCTAssertTrue(blind.mix.isEmpty)
    }

    func testAWideDetourIsNotCountedAsTheRoute() {
        let base = CLLocationCoordinate2D(latitude: 52.5, longitude: 13.4)
        let points = (0...10).map { i -> RoadPoint in
            RoadPoint(lat: base.latitude, lon: base.longitude + Double(i) * 0.0001, cls: .cycleway)
        }
        // Zweihundert Meter nördlich der geplanten Linie.
        let away = CLLocationCoordinate2D(latitude: base.latitude + 0.002, longitude: base.longitude)
        XCTAssertNil(RoadPoint.nearest(points, to: away, from: 0))
        XCTAssertEqual(RoadPoint.nearest(points, to: base, from: 0)?.cls, .cycleway)
    }

    // MARK: Neben der Route

    /// Der nächste Punkt liegt fast nie auf einer Ecke der Linie. BRouter setzt
    /// zwischen zwei Punkten gern hundert Meter gerade Straße; wer nur die
    /// Ecken misst, meldet eine Abweichung, die es nicht gibt.
    func testTheNearestPointIsOnTheSegmentNotOnItsCorners() {
        // Eine Ost-West-Strecke, 1 km lang, auf 52,5° Nord.
        let west = CLLocationCoordinate2D(latitude: 52.5, longitude: 13.400)
        let east = CLLocationCoordinate2D(latitude: 52.5, longitude: 13.4147)
        let route = [west, east]
        // Genau in der Mitte, 40 m nördlich davon.
        let mid = CLLocationCoordinate2D(latitude: 52.5 + 40 / 111_320.0, longitude: 13.4074)
        guard let fix = OffRoute.nearest(to: mid, on: route) else { return XCTFail("kein Punkt gefunden") }
        XCTAssertEqual(fix.meters, 40, accuracy: 3, "der Lotfußpunkt, nicht die 500 m bis zur Ecke")
        XCTAssertEqual(fix.bearing, 180, accuracy: 5, "die Route liegt südlich")
        XCTAssertEqual(fix.nearest.latitude, 52.5, accuracy: 0.0005)

        // Hinter dem Ende: dann ist die Ecke selbst der nächste Punkt.
        let beyond = CLLocationCoordinate2D(latitude: 52.5, longitude: 13.420)
        guard let past = OffRoute.nearest(to: beyond, on: route) else { return XCTFail("kein Punkt gefunden") }
        XCTAssertEqual(past.nearest.longitude, east.longitude, accuracy: 0.0002)
        XCTAssertEqual(past.bearing, 270, accuracy: 5, "die Route liegt westlich")
    }

    /// Ohne Hysterese flackert der Pfeil auf einem Radweg neben der gerouteten
    /// Fahrbahn: ein Fix mit fünfzehn Metern Ungenauigkeit springt über die
    /// Schwelle und wieder zurück.
    func testBeingOffTheRouteHasHysteresis() {
        XCTAssertFalse(OffRoute.isOff(50, was: false), "50 m reichen nicht, um abgewichen zu sein")
        XCTAssertTrue(OffRoute.isOff(70, was: false), "70 m schon")
        XCTAssertTrue(OffRoute.isOff(50, was: true), "und dann bleibt man es bei 50 m auch")
        XCTAssertFalse(OffRoute.isOff(30, was: true), "erst unter 35 m ist man wieder drauf")
        XCTAssertLessThan(OffRoute.backOnMeters, OffRoute.offMeters)
        XCTAssertGreaterThan(OffRoute.replanMeters, OffRoute.offMeters)
    }

    /// Eine leere Linie hat keinen nächsten Punkt — und darf nicht abstürzen.
    func testAnEmptyRouteHasNoNearestPoint() {
        XCTAssertNil(OffRoute.nearest(to: CLLocationCoordinate2D(latitude: 52.5, longitude: 13.4), on: []))
        let only = CLLocationCoordinate2D(latitude: 52.5, longitude: 13.4)
        let fix = OffRoute.nearest(to: CLLocationCoordinate2D(latitude: 52.5, longitude: 13.41), on: [only])
        XCTAssertNotNil(fix, "ein einzelner Punkt ist auch eine Antwort")
        XCTAssertEqual(fix?.bearing ?? 0, 270, accuracy: 5)
    }

    /// Neu geplant wird, **was zuerst eintritt**: die Entfernung oder die
    /// Zeit. Die Entfernung erst nach ein paar Sekunden am Stück — sonst löst
    /// jeder Bogen um eine Baustelle eine Neuplanung aus. Die Zeit ganz ohne
    /// Rücksicht auf die Entfernung: wer im Kreis um einen gesperrten Weg
    /// fährt, kommt nie weit genug weg und braucht trotzdem einen Vorschlag.
    func testReplanTriggersOnWhicheverComesFirst() {
        func should(_ m: Double, _ s: TimeInterval, meters: Double = 200, minutes: Double = 0) -> Bool {
            OffRoute.shouldReplan(meters: m, offFor: s, afterMeters: meters, afterMinutes: minutes)
        }
        XCTAssertFalse(should(150, 60), "nah genug an der Route")
        XCTAssertFalse(should(300, 5), "weit genug weg, aber erst seit fünf Sekunden")
        XCTAssertTrue(should(300, 20), "weit genug und lange genug")

        XCTAssertFalse(should(150, 60, minutes: 2), "eine Minute reicht für zwei nicht")
        XCTAssertTrue(should(150, 130, minutes: 2), "zwei Minuten daneben reichen, auch auf 150 m")
        XCTAssertTrue(should(300, 20, minutes: 2), "und die Entfernung greift trotzdem früher")

        XCTAssertFalse(should(5000, 600, meters: 0, minutes: 0), "beides aus heißt aus")
    }

    /// Auf der ersten Testfahrt war ein Kilometer zu spät: bis dahin ist man
    /// längst auf einer anderen Straße. 200 m, und erst nach einer Weile am
    /// Stück — ein kurzer Bogen um eine Baustelle ist kein neuer Weg.
    func testTheReplanThresholdIsCloseEnoughToHelp() {
        XCTAssertEqual(OffRoute.replanMeters, 200)
        XCTAssertGreaterThan(OffRoute.replanMeters, OffRoute.offMeters,
                             "erst abgewichen, dann neu berechnet")
        XCTAssertGreaterThanOrEqual(OffRoute.offFor, 10)
        XCTAssertEqual(AppSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
                        .replanOffRouteMeters, OffRoute.replanMeters,
                       "die Voreinstellung ist dieselbe Zahl, nicht eine zweite daneben")
    }
}
