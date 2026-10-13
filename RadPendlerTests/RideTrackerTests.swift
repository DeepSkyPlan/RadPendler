import CoreLocation
import MapKit
import XCTest
@testable import RadPendler

/// Die Aufzeichnung als Ganzes, vom Start bis zur abgelegten Fahrt — bis 1.16
/// waren nur ihre Rechenteile geprüft (`RideMeter`, die statischen Helfer).
/// Was hier steht, ist das, was auf dem Gerät von Hand geprüft wurde und
/// stumm kaputtgehen kann: Erlaubnis, Hintergrund-Ortung nur während der
/// Fahrt, alte Ortungen, Ablegen.
///
/// Ohne Empfänger: die Erlaubnis ist austauschbar (`authorization`), und die
/// Ortungen kommen über `accept` herein.
@MainActor
final class RideTrackerTests: XCTestCase {
    private let base = CLLocationCoordinate2D(latitude: 52.5000, longitude: 13.4000)
    private var folder: URL!
    private var store: RideStore!
    private var tracker: RideTracker!
    private var soundsWereOn = true

    override func setUp() async throws {
        folder = URL.temporaryDirectory.appending(path: "RideTrackerTests-\(UUID().uuidString)")
        store = RideStore(folder: folder, defaults: UserDefaults(suiteName: "tracker-\(UUID().uuidString)")!)
        tracker = RideTracker(store: store)
        soundsWereOn = RideSounds.shared.enabled
        RideSounds.shared.enabled = false
    }

    override func tearDown() async throws {
        if tracker.isRecording { tracker.stop() }
        RideSounds.shared.enabled = soundsWereOn
        try? FileManager.default.removeItem(at: folder)
    }

    private func east(_ meters: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: base.latitude,
                               longitude: base.longitude + meters / (111_320 * cos(base.latitude * .pi / 180)))
    }

    private var plan: RidePlan {
        RidePlan(subject: .init(origin: "A", destination: "B", mode: TravelMode.bike.rawValue),
                 signals: [], route: [east(0), east(2_000)])
    }

    /// Der Sprung vom Empfänger auf den Hauptfaden ist ein `Task`; so lange
    /// warten, bis er gelaufen ist.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(50))
    }

    // MARK: Erlaubnis

    func testWithoutPermissionNothingIsRecordedAndTheReasonIsSaid() {
        tracker.authorization = { .denied }
        tracker.start(plan)
        XCTAssertFalse(tracker.isRecording)
        XCTAssertNotNil(tracker.failure, "wer nichts sieht, muss wenigstens lesen können, warum")
        XCTAssertFalse(tracker.followsInBackground)
    }

    func testARestrictedDeviceIsTreatedLikeARefusal() {
        tracker.authorization = { .restricted }
        tracker.start(plan)
        XCTAssertFalse(tracker.isRecording)
        XCTAssertNotNil(tracker.failure)
    }

    /// Die Antwort auf das Erlaubnisfenster kommt später und woanders an —
    /// die Fahrt, die darauf wartet, muss dann von selbst beginnen.
    func testTheRideWaitingForPermissionStartsOnceItIsGiven() async {
        tracker.authorization = { .notDetermined }
        tracker.start(plan)
        XCTAssertFalse(tracker.isRecording)
        XCTAssertNil(tracker.failure)
        tracker.authorization = { .authorizedWhenInUse }
        tracker.locationManagerDidChangeAuthorization(CLLocationManager())
        await settle()
        XCTAssertTrue(tracker.isRecording)
    }

    func testARefusalInThePermissionSheetLeavesNoRideBehind() async {
        tracker.authorization = { .notDetermined }
        tracker.start(plan)
        tracker.authorization = { .denied }
        tracker.locationManagerDidChangeAuthorization(CLLocationManager())
        await settle()
        XCTAssertFalse(tracker.isRecording)
        XCTAssertNotNil(tracker.failure)
        // Und eine spätere Erlaubnis startet nicht nachträglich die alte Fahrt.
        tracker.authorization = { .authorizedWhenInUse }
        tracker.locationManagerDidChangeAuthorization(CLLocationManager())
        await settle()
        XCTAssertFalse(tracker.isRecording)
    }

    /// Mitten in der Fahrt in den iOS-Einstellungen entzogen.
    func testPermissionWithdrawnWhileRidingEndsTheRide() async {
        tracker.authorization = { .authorizedWhenInUse }
        tracker.start(plan)
        XCTAssertTrue(tracker.isRecording)
        tracker.locationManager(CLLocationManager(), didFailWithError: CLError(.denied))
        await settle()
        XCTAssertFalse(tracker.isRecording)
        XCTAssertNotNil(tracker.failure)
        XCTAssertFalse(tracker.followsInBackground)
    }

    /// Ein einzelner Aussetzer — Tunnel, Unterführung — ist kein Ende.
    func testASingleFailedFixDoesNotEndTheRide() async {
        tracker.authorization = { .authorizedWhenInUse }
        tracker.start(plan)
        tracker.locationManager(CLLocationManager(), didFailWithError: CLError(.locationUnknown))
        await settle()
        XCTAssertTrue(tracker.isRecording)
    }

    // MARK: Hintergrund

    /// Das Versprechen aus der Datenschutzerklärung und der Begründung für den
    /// Hintergrundmodus: geortet wird nur zwischen Start und Ende.
    func testTheAppFollowsInTheBackgroundOnlyWhileARideRuns() {
        tracker.authorization = { .authorizedWhenInUse }
        XCTAssertFalse(tracker.followsInBackground, "vor der Fahrt")
        tracker.start(plan)
        XCTAssertTrue(tracker.followsInBackground, "während der Fahrt, auch mit gesperrtem Bildschirm")
        tracker.pause()
        XCTAssertFalse(tracker.followsInBackground, "von Hand angehalten: die Ortung ist ganz aus")
        tracker.resume()
        XCTAssertTrue(tracker.followsInBackground)
        tracker.stop()
        XCTAssertFalse(tracker.followsInBackground, "nach der Fahrt")
        XCTAssertEqual(tracker.receiver, .full, "und der Empfänger steht für die nächste wieder voll")
    }

    // MARK: Ortungen

    /// `startUpdatingLocation` liefert als Erstes gern die letzte bekannte
    /// Position. Sie darf die Fahrt nicht vor dem Losfahren beginnen lassen.
    func testFixesFromTheReceiversCacheAreDropped() async {
        tracker.authorization = { .authorizedWhenInUse }
        tracker.start(plan)
        let stale = CLLocation(coordinate: east(0), altitude: 40, horizontalAccuracy: 5, verticalAccuracy: 5,
                               course: 90, speed: 5, timestamp: .now.addingTimeInterval(-120))
        tracker.locationManager(CLLocationManager(), didUpdateLocations: [stale])
        await settle()
        XCTAssertTrue(tracker.meter.points.isEmpty, "zwei Minuten alt: gehört nicht zu dieser Fahrt")
        let fresh = CLLocation(coordinate: east(0), altitude: 40, horizontalAccuracy: 5, verticalAccuracy: 5,
                               course: 90, speed: 5, timestamp: .now)
        tracker.locationManager(CLLocationManager(), didUpdateLocations: [fresh])
        await settle()
        XCTAssertEqual(tracker.meter.points.count, 1)
        XCTAssertNotNil(tracker.here)
    }

    func testNothingIsMeasuredBeforeTheRideStarts() {
        tracker.accept([RideMeter.Fix(coordinate: east(0), time: .now, speed: 5)], [90])
        XCTAssertTrue(tracker.meter.points.isEmpty)
        XCTAssertNil(tracker.here)
    }

    // MARK: Gegen die Linie

    /// Fahrt 11.10.2026: die Aufzeichnung begann unterwegs, weit vom Ziel der
    /// Linie, und die Fahrt lief auf ihr zurück. Nach zwanzig Ortungen gegen
    /// die Linie dreht sich die Fahrt um — einmal, und nicht wieder zurück.
    func testDrivingAlongTheLineAgainstItTurnsTheRideAround() {
        let tracker = RideTracker(store: store, replanner: Replanner(router: DeadRouter(), signalsAlong: { _ in [] }))
        tracker.authorization = { .authorizedWhenInUse }
        tracker.start(RidePlan(subject: .init(origin: "A", destination: "B", mode: TravelMode.car.rawValue),
                               signals: [], route: [east(0), east(5_000)]))
        let t0 = Date.now.addingTimeInterval(-60)
        func drive(_ seconds: ClosedRange<Int>) {
            for second in seconds {
                tracker.accept([RideMeter.Fix(coordinate: east(3_000 - Double(second) * 15),
                                              time: t0.addingTimeInterval(Double(second)), speed: 15)], [270])
            }
        }
        drive(0...18)
        XCTAssertEqual(tracker.subject?.destination, "B", "eine Wende auf der Straße dauert kürzer")
        drive(19...40)
        XCTAssertEqual(tracker.subject?.destination, "A")
        XCTAssertEqual(tracker.plannedRoute.first?.longitude, east(5_000).longitude)
        XCTAssertEqual(tracker.plannedRoute.last?.longitude, east(0).longitude)
        tracker.stop()
    }

    func testDrivingWithTheLineTurnsNothing() {
        let tracker = RideTracker(store: store, replanner: Replanner(router: DeadRouter(), signalsAlong: { _ in [] }))
        tracker.authorization = { .authorizedWhenInUse }
        tracker.start(RidePlan(subject: .init(origin: "A", destination: "B", mode: TravelMode.car.rawValue),
                               signals: [], route: [east(0), east(5_000)]))
        let t0 = Date.now.addingTimeInterval(-60)
        for second in 0...40 {
            tracker.accept([RideMeter.Fix(coordinate: east(1_000 + Double(second) * 15),
                                          time: t0.addingTimeInterval(Double(second)), speed: 15)], [90])
        }
        XCTAssertEqual(tracker.subject?.destination, "B")
        tracker.stop()
    }

    /// Gegen die Linie heißt: kein Stück in Reichweite zeigt mit dem Kurs.
    func testAgainstTheLineIsNotACrossingOrTheWayBackOnASpur() {
        let line = [east(0), east(2_000)]
        XCTAssertTrue(OffRoute.against(course: 270, at: east(1_000), on: line))
        XCTAssertFalse(OffRoute.against(course: 90, at: east(1_000), on: line))
        XCTAssertFalse(OffRoute.against(course: 0, at: east(1_000), on: line), "eine Querstraße")
        XCTAssertFalse(OffRoute.against(course: -1, at: east(1_000), on: line), "kein Kurs, keine Auskunft")
        XCTAssertFalse(OffRoute.against(course: 270, at: east(1_000), on: line + [east(0)]),
                       "hin und zurück auf derselben Straße")
        let north = CLLocationCoordinate2D(latitude: base.latitude + 0.002, longitude: east(1_000).longitude)
        XCTAssertFalse(OffRoute.against(course: 270, at: north, on: line), "220 m daneben ist nicht auf der Linie")
    }

    /// Fahrt 11.10.2026: Richtung getauscht, „Fahrt“ getippt, bevor der neue
    /// Plan da war — die Linie der Gegenrichtung fuhr mit.
    func testSwappedEndsAreAnotherTripAndTheSamePlaceRelocatedIsNot() {
        let a = Place(name: "A", latitude: 52.5210, longitude: 13.4130)
        let b = Place(name: "B", latitude: 52.4213, longitude: 13.1794)
        let nearA = Place(name: "Mein Standort", latitude: 52.5212, longitude: 13.4133)
        func request(_ from: Place, _ to: Place) -> PlanRequest {
            PlanRequest(origin: from, destination: to, target: .departAfter(.now), settings: PlanSettings())
        }
        XCTAssertTrue(PlanModel.isAnotherTrip(request(a, b), request(b, a)))
        XCTAssertFalse(PlanModel.isAnotherTrip(request(a, b), request(a, b)))
        XCTAssertFalse(PlanModel.isAnotherTrip(request(a, b), request(nearA, b)))
    }

    /// Der Tipp auf „Fahrt“ woanders als am Start: nur wer auch nicht auf
    /// der Linie steht, bekommt einen neuen Start.
    func testStartingAwayFromStartAndLineIsElsewhere() {
        let line = [east(0), east(5_000)]
        let off = CLLocationCoordinate2D(latitude: base.latitude + 0.01, longitude: east(2_000).longitude)
        XCTAssertFalse(RideTracker.startsElsewhere(east(100), origin: east(0), route: line), "am Start")
        XCTAssertFalse(RideTracker.startsElsewhere(east(2_000), origin: east(0), route: line), "unterwegs auf der Linie")
        XCTAssertTrue(RideTracker.startsElsewhere(off, origin: east(0), route: line), "1,1 km neben der Linie")
        XCTAssertTrue(RideTracker.startsElsewhere(off, origin: east(0), route: []), "ohne Linie zählt der Start")
    }

    /// Die Übersichtskarte zeigt die ganze Linie mit Rand, und eine kurze
    /// nicht als Hauswand.
    func testTheOverviewFramesTheWholeLine() throws {
        let rect = try XCTUnwrap(RideOverview.rect(around: [east(0), east(5_000)]))
        XCTAssertTrue(rect.contains(MKMapPoint(east(0))))
        XCTAssertTrue(rect.contains(MKMapPoint(east(5_000))))
        let metres = MKMapPointsPerMeterAtLatitude(base.latitude)
        XCTAssertGreaterThan(rect.height / metres, 300, "eine Linie ohne Höhe bekommt trotzdem ein Bild")
        let tiny = try XCTUnwrap(RideOverview.rect(around: [east(0)]))
        XCTAssertGreaterThan(tiny.width / metres, 300)
        XCTAssertNil(RideOverview.rect(around: []))
    }

    // MARK: Heatmap

    private func track(_ points: [CLLocationCoordinate2D], stops: [RideStop] = []) -> RideTrack {
        RideTrack(id: UUID(), points: points.enumerated().map { i, c in
            RidePoint(lat: c.latitude, lon: c.longitude, t: Date(timeIntervalSince1970: Double(i)), v: 5)
        }, stops: stops)
    }

    /// Drei Fahrten über dieselbe Straße, eine davon biegt ab: auf der Straße
    /// liegen drei Fahrten je Punkt, auf dem Abzweig eine — gezählt je Fahrt,
    /// nicht je Ortung, und hin und zurück ist dieselbe Straße.
    func testTheCloudCountsRidesPerPlace() throws {
        let street = stride(from: 0.0, through: 1_000, by: 10).map { east($0) }
        let branch = stride(from: 0.0, through: 500, by: 10).map {
            CLLocationCoordinate2D(latitude: base.latitude + $0 / 111_320, longitude: east(1_000).longitude)
        }
        let heat = RideHeat.build([track(street), track(street.reversed()), track(street + branch)])
        XCTAssertEqual(heat.rides, 3)
        let fine = try XCTUnwrap(heat.layers.first)
        XCTAssertEqual(fine.most, 3)
        let onStreet = fine.dots.filter { abs($0.coordinate.latitude - base.latitude) < 0.00002 && $0.coordinate.longitude < east(950).longitude }
        XCTAssertGreaterThan(onStreet.count, 60, "ein Punkt je Zelle, die ganze Straße entlang")
        XCTAssertTrue(onStreet.allSatisfy { $0.rides == 3 })
        let onBranch = fine.dots.filter { $0.coordinate.latitude > base.latitude + 0.0005 }
        XCTAssertFalse(onBranch.isEmpty)
        XCTAssertTrue(onBranch.allSatisfy { $0.rides == 1 })
        // Von weitem dieselbe Wolke mit weniger Punkten.
        XCTAssertEqual(heat.layers.map(\.meters), RideHeat.layerMeters)
        XCTAssertLessThan(heat.layers[1].dots.count, fine.dots.count)
    }

    /// Im Auto liegt ein Punkt je Sekunde vierzig Meter vom nächsten: zwei
    /// Fahrten über dieselbe Straße müssen sich trotzdem treffen. Und über
    /// eine Lücke von Kilometern wird nichts gezählt.
    func testFastRidesStillShareTheirStreetAndGapsStayOpen() throws {
        let fast = stride(from: 0.0, through: 2_000, by: 40).map { east($0) }
        let offset = stride(from: 17.0, through: 2_000, by: 37).map { east($0) }
        let fine = try XCTUnwrap(RideHeat.build([track(fast), track(offset)]).layers.first)
        let shared = fine.dots.filter { $0.rides == 2 }.count
        XCTAssertGreaterThan(Double(shared) / Double(fine.dots.count), 0.95)
        let torn = RideHeat.resampled([east(0), east(300), east(5_000), east(5_300)])
        XCTAssertEqual(torn.count, 2, "vor und hinter dem Tunnel")
        XCTAssertLessThan(torn[0].last!.distance(to: east(300)), RideHeat.stepMeters + 1)
    }

    /// Rad und Auto über dieselbe Straße sind zwei Wolken: jede zählt ihre
    /// eigenen Fahrten und trägt ihr Verkehrsmittel.
    func testEachModeHasItsOwnCloud() throws {
        let street = stride(from: 0.0, through: 600, by: 10).map { east($0) }
        let (a, b, c) = (track(street), track(street), track(street))
        let heat = RideHeat.build([a, b, c], modes: [a.id: "bike", b.id: "bike", c.id: "car"])
        let fine = try XCTUnwrap(heat.layers.first)
        XCTAssertEqual(Set(fine.dots.map(\.mode)), ["bike", "car"])
        XCTAssertTrue(fine.dots.filter { $0.mode == "bike" }.allSatisfy { $0.rides == 2 })
        XCTAssertTrue(fine.dots.filter { $0.mode == "car" }.allSatisfy { $0.rides == 1 })
        XCTAssertEqual(fine.most, 2)
    }

    /// Das Tempo eines Orts ist das Mittel aller Fahrten dort — im Rollen.
    func testTheCloudKnowsHowFastAPlaceIsRidden() throws {
        func ride(_ speed: Double) -> RideTrack {
            RideTrack(id: UUID(), points: stride(from: 0.0, through: 600, by: 10).enumerated().map { i, m in
                RidePoint(lat: east(m).latitude, lon: east(m).longitude, t: Date(timeIntervalSince1970: Double(i)), v: speed)
            })
        }
        let fine = try XCTUnwrap(RideHeat.build([ride(4), ride(6)]).layers.first)
        XCTAssertFalse(fine.dots.isEmpty)
        for dot in fine.dots { XCTAssertEqual(dot.kmh, 18, accuracy: 0.5, "4 und 6 m/s sind im Mittel 18 km/h") }
    }

    /// Stufenlos, und gemessen am dichtesten Punkt: eine Fahrt bleibt
    /// sichtbar, die meisten sind voll, dazwischen steigt es.
    func testStrengthRisesWithRidesAndIsRelativeToTheBusiest() {
        XCTAssertEqual(RideHeat.strength(0, most: 10), 0)
        XCTAssertEqual(RideHeat.strength(1, most: 10), RideHeat.faintest, accuracy: 0.001)
        XCTAssertEqual(RideHeat.strength(10, most: 10), 1, accuracy: 0.001)
        XCTAssertEqual(RideHeat.strength(1, most: 1), 1, "eine einzige Fahrt ist die ganze Karte")
        let steps = (1...10).map { RideHeat.strength($0, most: 10) }
        XCTAssertEqual(steps, steps.sorted())
        XCTAssertEqual(Set(steps).count, 10, "zehn Fahrten, zehn Stufen")
        XCTAssertTrue(RideHeat.build([]).layers.isEmpty)
    }

    /// Die Summe, die auf der Platte liegt: eine Fahrt nach der anderen dazu
    /// ergibt dasselbe wie alle auf einmal, sie übersteht das Wegschreiben,
    /// und dieselbe Fahrt zweimal ändert nichts.
    func testTheStoredSumGrowsRideByRide() throws {
        let street = stride(from: 0.0, through: 600, by: 10).map { east($0) }
        func stop(_ metres: Double) -> RideStop {
            RideStop(lat: east(metres).latitude, lon: east(metres).longitude, start: .now, seconds: 30, atSignal: true)
        }
        let (a, b, c) = (track(street, stops: [stop(100)]), track(street, stops: [stop(110)]), track(street.reversed()))
        let modes = [a.id: "bike", b.id: "bike", c.id: "car"]
        let whole = RideHeat.build([a, b, c], modes: modes)

        var sum = RideHeat.Sum()
        sum.add(a, mode: "bike")
        sum.add(b, mode: "bike")
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        var stored = try PropertyListDecoder().decode(RideHeat.Sum.self, from: encoder.encode(sum))
        stored.add(c, mode: "car")
        stored.add(a, mode: "bike")
        let grown = stored.heat()
        XCTAssertEqual(grown.rides, 3)
        func key(_ heat: RideHeat) -> [String] {
            heat.layers[0].dots.map { "\($0.mode)|\($0.rides)|\(Int($0.coordinate.longitude * 1e6))|\(Int($0.kmh))" }.sorted()
        }
        XCTAssertEqual(key(grown), key(whole))
        XCTAssertEqual(grown.signals.map(\.stops), whole.signals.map(\.stops))
        XCTAssertEqual(grown.signals.first?.total, 60)

        // Je Verkehrsmittel: nur dessen Wolke und dessen Halte.
        let cars = stored.heat(only: "car")
        XCTAssertEqual(cars.rides, 1)
        XCTAssertEqual(Set(cars.layers[0].dots.map(\.mode)), ["car"])
        XCTAssertTrue(cars.signals.isEmpty)

        // Eine gelöschte Fahrt oder ein anderes Verkehrsmittel: neu rechnen.
        XCTAssertTrue(stored.fits(modes))
        XCTAssertTrue(stored.fits(modes.merging([UUID(): "bike"]) { x, _ in x }), "eine neue Fahrt kommt nur dazu")
        XCTAssertFalse(stored.fits([a.id: "bike", b.id: "bike"]))
        XCTAssertFalse(stored.fits([a.id: "bike", b.id: "car", c.id: "car"]))
    }

    /// Zwischen zwei Ortungen gleiten Pfeil und Karte: auf halbem Weg in der
    /// Mitte, und die Richtung auf dem kurzen Weg um den Kreis.
    func testTheGlideTakesTheShortWayRound() {
        typealias Cam = RouteMapView.Coordinator.Cam
        let a = Cam(center: east(0), distance: 700, heading: 350)
        let b = Cam(center: east(30), distance: 900, heading: 10)
        let half = RouteMapView.Coordinator.between(a, b, 0.5)
        XCTAssertEqual(half.center.distance(to: east(15)), 0, accuracy: 0.5)
        XCTAssertEqual(half.distance, 800, accuracy: 0.1)
        XCTAssertEqual(half.heading, 0, accuracy: 0.001, "über Norden, nicht über Süden")
        XCTAssertEqual(RouteMapView.Coordinator.between(a, b, 1).heading, 10, accuracy: 0.001)
        XCTAssertEqual(RouteMapView.Coordinator.between(b, a, 0.25).heading, 5, accuracy: 0.001)
        XCTAssertTrue(Cam.same(a, a))
        XCTAssertFalse(Cam.same(a, b))
        XCTAssertFalse(Cam.same(a, nil))
        // Neben der Route: beides im Bild, die Mitte dazwischen.
        let both = RouteMapView.Coordinator.both(east(0), east(400), heading: 90)
        XCTAssertEqual(both.center.distance(to: east(200)), 0, accuracy: 0.5)
        XCTAssertEqual(both.distance, 1_000, accuracy: 5)
    }

    /// Der nahe Ausschnitt der Übersichtskarte: halbe Kantenlänge, der Fahrer
    /// in der Mitte.
    func testTheNearOverviewIsHalfTheSizeAroundTheRider() throws {
        let rect = try XCTUnwrap(RideOverview.rect(around: [east(0), east(5_000)]))
        let near = RideOverview.zoomed(rect, on: east(4_000))
        XCTAssertEqual(near.width, rect.width / 2, accuracy: 1)
        XCTAssertEqual(near.height, rect.height / 2, accuracy: 1)
        XCTAssertEqual(MKMapPoint(x: near.midX, y: near.midY).coordinate.distance(to: east(4_000)), 0, accuracy: 1)
        let blind = RideOverview.zoomed(rect, on: nil)
        XCTAssertEqual(blind.midX, rect.midX, accuracy: 1)
        // Nach einer Neuplanung beginnt die gültige Linie beim Fahrer — ins
        // Bild gehört trotzdem die ganze Fahrt, vom ursprünglichen Start an.
        let replanned = RideOverview.whole(original: [east(0), east(5_000)], planned: [east(3_000), east(5_000)],
                                           ridden: east(0), here: east(3_000))
        let all = try XCTUnwrap(RideOverview.rect(around: replanned))
        XCTAssertTrue(all.contains(MKMapPoint(east(0))))
        XCTAssertTrue(all.contains(MKMapPoint(east(5_000))))
        // Und die gefahrene Linie bleibt klein, mit ihrem letzten Punkt.
        let long = (0..<2_000).map { RidePoint(lat: east(Double($0)).latitude, lon: east(Double($0)).longitude, t: .now, v: 5) }
        let sparse = RideOverview.sparse(long)
        XCTAssertLessThanOrEqual(sparse.count, 152)
        XCTAssertEqual(sparse.last?.longitude, long.last?.lon)
        XCTAssertEqual(RideOverview.Mode.route.next, .near)
        XCTAssertEqual(RideOverview.Mode.near.next, .off)
        XCTAssertEqual(RideOverview.Mode.off.next, .route)
    }

    /// Halte an derselben Kreuzung gehören zusammen, auch von der anderen
    /// Seite; ein Halt ohne Ampel zählt nicht. Sortiert nach der Zeit, die
    /// dort liegen blieb.
    func testStopsAtTheSameLightAreOneSignal() {
        func stop(_ metres: Double, _ seconds: TimeInterval, signal: Bool = true) -> RideStop {
            RideStop(lat: east(metres).latitude, lon: east(metres).longitude, start: .now, seconds: seconds, atSignal: signal)
        }
        let signals = RideHeat.waits(in: [track([], stops: [stop(0, 20), stop(600, 90)]),
                                            track([], stops: [stop(25, 40), stop(300, 500, signal: false)])])
        XCTAssertEqual(signals.count, 2)
        XCTAssertEqual(signals.first?.total, 90, "die meiste Wartezeit zuerst")
        let crossing = signals[1]
        XCTAssertEqual(crossing.stops, 2)
        XCTAssertEqual(crossing.total, 60)
        XCTAssertEqual(crossing.longest, 40)
        XCTAssertEqual(crossing.mean, 30)
    }

    // MARK: Von Anfang bis Ende

    /// Drei Minuten mit 5 m/s nach Osten: die Fahrt liegt danach in der Liste,
    /// ihre Linie auf der Platte, und der Zwischenstand ist weg.
    func testAWholeRideEndsUpInTheStoreWithItsLine() async throws {
        tracker.authorization = { .authorizedWhenInUse }
        tracker.start(plan)
        let t0 = Date.now.addingTimeInterval(-180)
        for second in 0...180 {
            tracker.accept([RideMeter.Fix(coordinate: east(Double(second) * 5),
                                          time: t0.addingTimeInterval(Double(second)), speed: 5)], [90])
        }
        let ride = try XCTUnwrap(tracker.stop(at: t0.addingTimeInterval(180)))
        XCTAssertEqual(ride.meters, 900, accuracy: 15)
        XCTAssertEqual(ride.seconds, 180, accuracy: 2)
        XCTAssertEqual(store.rides.map(\.id), [ride.id])
        XCTAssertFalse(tracker.isRecording)
        XCTAssertEqual(tracker.finished?.id, ride.id, "für das Blatt mit der Zusammenfassung")
        let file = folder.appending(path: "tracks").appending(path: "\(ride.id.uuidString).json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "die Linie liegt auf der Platte")
        let track = try JSONDecoder().decode(RideTrack.self, from: Data(contentsOf: file))
        XCTAssertGreaterThan(track.points.count, 100)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appending(path: "current.json").path))
    }

    /// Ein Tipp auf den falschen Knopf ist keine Pendelfahrt.
    func testARideOfAFewSecondsIsNotKept() {
        tracker.authorization = { .authorizedWhenInUse }
        tracker.start(plan)
        let t0 = Date.now.addingTimeInterval(-20)
        for second in 0...20 {
            tracker.accept([RideMeter.Fix(coordinate: east(Double(second) * 5),
                                          time: t0.addingTimeInterval(Double(second)), speed: 5)], [90])
        }
        XCTAssertNil(tracker.stop(at: t0.addingTimeInterval(20)))
        XCTAssertTrue(store.rides.isEmpty)
    }

    /// Von Hand angehalten wird nichts gemessen, auch wenn noch eine Ortung
    /// nachkommt.
    func testNothingIsAddedWhilePausedByHand() {
        tracker.authorization = { .authorizedWhenInUse }
        tracker.start(plan)
        let t0 = Date.now.addingTimeInterval(-30)
        for second in 0...10 {
            tracker.accept([RideMeter.Fix(coordinate: east(Double(second) * 5),
                                          time: t0.addingTimeInterval(Double(second)), speed: 5)], [90])
        }
        tracker.pause()
        let before = tracker.meter.meters
        tracker.accept([RideMeter.Fix(coordinate: east(500), time: t0.addingTimeInterval(20), speed: 5)], [90])
        XCTAssertEqual(tracker.meter.meters, before)
        XCTAssertTrue(tracker.meter.isPaused, "eine Pause per Knopf endet nur per Knopf")
    }
}
