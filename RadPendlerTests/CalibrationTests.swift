import CoreLocation
import XCTest
@testable import RadPendler

/// Was die App aus den eigenen Fahrten lernt: wie schnell dieser Fahrer
/// wirklich ist, was seine Ampeln wirklich kosten, und wie weit es auf einer
/// laufenden Fahrt noch ist.
final class CalibrationTests: XCTestCase {
    private let base = CLLocationCoordinate2D(latitude: 52.5, longitude: 13.4)
    private let noon = Date(timeIntervalSince1970: 1_780_000_000)

    private func east(_ meters: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: base.latitude,
                               longitude: base.longitude + meters / (111_320 * cos(base.latitude * .pi / 180)))
    }

    private func settings() -> AppSettings {
        AppSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    /// `movingSeconds` und `seconds` ergeben die beiden Schnitte: rollend und
    /// Tür zu Tür.
    private func ride(_ index: Int, km: Double, movingKmh: Double, standing: TimeInterval) -> Ride {
        let meters = km * 1000
        let moving = meters / (movingKmh / 3.6)
        let start = noon.addingTimeInterval(Double(index) * 86_400)
        return Ride(started: start, ended: start.addingTimeInterval(moving + standing),
                    origin: "A", destination: "B", mode: TravelMode.bike.rawValue,
                    meters: meters, movingSeconds: moving, maxKmh: 40,
                    signalStops: 8, otherStops: 1, signalWaitTotal: standing)
    }

    // MARK: Tempo

    func testOneRideIsWeatherAndDoesNotMoveTheSetting() {
        let s = settings()
        s.calibrate(from: [ride(0, km: 20, movingKmh: 24, standing: 600)])
        XCTAssertEqual(s.bikeSpeedKmh, AppSettings.defaultBikeSpeedKmh)
        XCTAssertEqual(s.measuredRides, 0)
        XCTAssertNil(s.measuredOverallKmh)
    }

    func testTheMeasuredRollingSpeedBecomesTheSetting() {
        let s = settings()
        // Drei Fahrten: 23, 24, 25 km/h rollend — der Median ist 24.
        s.calibrate(from: [ride(0, km: 20, movingKmh: 23, standing: 600),
                           ride(1, km: 20, movingKmh: 25, standing: 600),
                           ride(2, km: 20, movingKmh: 24, standing: 600)])
        XCTAssertEqual(s.measuredRides, 3)
        XCTAssertEqual(s.bikeSpeedKmh, 24, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(s.measuredMovingKmh), 24, accuracy: 0.01)
        // Tür zu Tür: 20 km in 50 min + 10 min Stehen = 20 km/h.
        XCTAssertEqual(try XCTUnwrap(s.measuredOverallKmh), 20, accuracy: 0.5)
    }

    func testAWalkAroundTheBlockIsNotACommute() {
        let s = settings()
        let short = Ride(started: noon, ended: noon.addingTimeInterval(300), origin: "A", destination: "B",
                         mode: TravelMode.bike.rawValue, meters: 900, movingSeconds: 280, maxKmh: 20,
                         signalStops: 0, otherStops: 0, signalWaitTotal: 0)
        s.calibrate(from: [short, short, short, short])
        XCTAssertEqual(s.measuredRides, 0, "unter zwei Kilometern zählt nichts")
    }

    // MARK: Die Gegenprobe beim Planen

    func testTheMeasuredAverageWins() {
        var s = PlanSettings(bikeSpeedKmh: 29)
        s.signalWaitSeconds = 20
        let route = StreetRoute(distance: 20_000, expectedTravelTime: 0, coordinates: [])
        let c = BikeCandidate(source: .brouter(.trekking), route: route,
                              stats: BikeRouteStats(signals: 10, crossings: [], mainRoadMeters: 0))
        // Gerechnet: 20 km bei 29 km/h + 10 Ampeln = 41,4 + 3,3 min ≈ 45 min.
        let computed = c.computedTime(s)
        XCTAssertEqual(computed, 20_000 / (29 / 3.6) + 200, accuracy: 1)
        XCTAssertEqual(c.time(s), computed, accuracy: 1, "ohne Messung bleibt es bei der Rechnung")
        // Gemessen fährt dieser Mensch 20 km/h Tür zu Tür — also eine Stunde.
        s.measuredOverallKmh = 20
        XCTAssertEqual(c.time(s), 3_600, accuracy: 1)
        XCTAssertTrue(c.measuredWins(s))
    }

    /// In beide Richtungen: wer schneller ist, als die Rechnung glaubt, soll
    /// keine Ankunft angesagt bekommen, die zehn Minuten zu spät ist.
    func testTheMeasuredAverageAlsoWinsWhenItIsFaster() {
        var s = PlanSettings(bikeSpeedKmh: 15)
        s.signalWaitSeconds = 60
        s.measuredOverallKmh = 25
        let c = BikeCandidate(source: .brouter(.quiet),
                              route: StreetRoute(distance: 10_000, expectedTravelTime: 0, coordinates: []),
                              stats: BikeRouteStats(signals: 20, crossings: [], mainRoadMeters: 0))
        XCTAssertGreaterThan(c.computedTime(s), c.time(s))
        XCTAssertEqual(c.time(s), 10_000 / (25 / 3.6), accuracy: 1)
        XCTAssertTrue(c.measuredWins(s))
    }

    /// Die Zubringer zum Bahnhof rechneten bis 1.3 ohne die Messung: die
    /// ganze Radstrecke wurde realistisch verlängert, der Weg zum Bahnsteig
    /// nicht — und Rad + Bahn gewann dadurch mit einem Puffer, den es nicht
    /// gab.
    func testTheStationLegIsNeverFasterThanTheMeasuredAverage() {
        var s = PlanSettings(bikeSpeedKmh: 29)
        s.signalWaitSeconds = 20
        let leg = StreetRoute(distance: 3_000, expectedTravelTime: 0, coordinates: [], signals: 6)
        let computed = s.bikeTime(3_000) + s.signalWait(signals: 6)
        XCTAssertEqual(s.rideTime(leg), computed, accuracy: 1, "ohne Messung bleibt es bei der Rechnung")
        // Gemessen 13 km/h Tür zu Tür: die Rechnung ist zu optimistisch.
        s.measuredOverallKmh = 13
        XCTAssertEqual(s.rideTime(leg), 3_000 / (13 / 3.6), accuracy: 1)
        // Und in die andere Richtung gilt sie hier **nicht**: wer den Zug
        // verpasst, wartet zwanzig Minuten.
        s.measuredOverallKmh = 40
        XCTAssertEqual(s.rideTime(leg), computed, accuracy: 1)
    }

    /// Ein Zeitmodell für alles: die Zubringer von Transitous fahren mit
    /// derselben Rechnung wie die von HAFAS — und ohne Straßendaten, also
    /// ohne Ampeln, mit Transitous' eigener Schätzung.
    func testTransitousFeedersRideOnTheOwnTimeModel() {
        let s = PlanSettings(bikeSpeedKmh: 29)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let a = CLLocationCoordinate2D(latitude: 52.50, longitude: 13.40)
        let b = CLLocationCoordinate2D(latitude: 52.52, longitude: 13.40)
        let ride1 = Leg(kind: .bike, fromName: "A", toName: "S1", departure: t0, arrival: t0.addingTimeInterval(900),
                        distance: 3_000, coordinates: [a, b])
        let train = Leg(kind: .transit(line: "S1", product: .suburban), fromName: "S1", toName: "S2",
                        departure: t0.addingTimeInterval(1_000), arrival: t0.addingTimeInterval(2_000))
        let ride2 = Leg(kind: .bike, fromName: "S2", toName: "B", departure: t0.addingTimeInterval(2_100),
                        arrival: t0.addingTimeInterval(3_000), distance: 3_000, coordinates: [b, a])
        let legs = [ride1, train, ride2]
        let own = s.rideTime(StreetRoute(distance: 3_000, expectedTravelTime: 0, coordinates: [a, b]))
        let timed = TripPlanner.retimed(legs, roads: RoadData(signals: [], roads: []), settings: s)
        XCTAssertEqual(timed[0].arrival, ride1.arrival, "am Bahnhof wie geplant")
        XCTAssertEqual(timed[0].duration, own, accuracy: 1)
        XCTAssertEqual(timed[1].departure, train.departure)
        XCTAssertEqual(timed[2].departure, ride2.departure)
        XCTAssertEqual(timed[2].duration, own, accuracy: 1)
        let untouched = TripPlanner.retimed(legs, roads: nil, settings: s)
        XCTAssertEqual(untouched.map(\.duration), legs.map(\.duration))
    }

    /// Die ganze Radroute und der Zubringer rechnen mit derselben Formel;
    /// nur die Gegenprobe am gemessenen Schnitt gilt verschieden.
    func testWholeRouteAndFeederShareTheModel() {
        var s = PlanSettings(bikeSpeedKmh: 29)
        let route = StreetRoute(distance: 5_000, expectedTravelTime: 0, coordinates: [], signals: 4, ascent: 30)
        let c = BikeCandidate(source: .brouter(.trekking), route: route, stats: nil, ascent: 30)
        XCTAssertEqual(c.computedTime(s), s.rideTime(route), accuracy: 1)
        s.measuredOverallKmh = 40
        XCTAssertLessThan(c.time(s), s.rideTime(route), "die ganze Route glaubt dem schnelleren Schnitt, der Zubringer nicht")
    }

    /// Der Schnitt sagt, wie lange es dauert — nicht, wo es langgeht. Sonst
    /// wäre „schnellst" immer dieselbe Linie wie „kürzest".
    func testTheRolesAreStillDecidedByTheCalculation() {
        var s = PlanSettings(bikeSpeedKmh: 25)
        s.signalWaitSeconds = 30
        s.measuredOverallKmh = 18
        s.optionsPerMode = 5
        // Kurz mit vielen Ampeln gegen etwas länger mit fast keinen.
        let short = BikeCandidate(source: .brouter(.fastbike),
                                  route: StreetRoute(distance: 10_000, expectedTravelTime: 0, coordinates: []),
                                  stats: BikeRouteStats(signals: 30, crossings: [], mainRoadMeters: 8_000))
        let round = BikeCandidate(source: .brouter(.trekking),
                                  route: StreetRoute(distance: 11_000, expectedTravelTime: 0, coordinates: []),
                                  stats: BikeRouteStats(signals: 2, crossings: [], mainRoadMeters: 500))
        XCTAssertEqual(short.time(s), 10_000 / (18 / 3.6), accuracy: 1, "angezeigt wird die Messung")
        let picked = BikeCandidate.pick([short, round], settings: s)
        let fastest = picked.first { $0.1.contains(.fastest) }
        XCTAssertEqual(fastest?.0.source, .brouter(.trekking), "dreißig Ampeln sind fünfzehn Minuten")
        let shortest = picked.first { $0.1.contains(.shortest) }
        XCTAssertEqual(shortest?.0.source, .brouter(.fastbike))
    }

    // MARK: Ampeln in Zahlen

    func testTheSignalMeasurementIsTakenOverAllPasses() {
        let s = settings()
        // Zwanzig Kreuzungen, an jeder fünfmal vorbei, an jeder zweimal
        // gehalten, je 30 s.
        s.learnedSignals = (0..<20).map { i in
            LearnedSignal(lat: 52.5 + Double(i) / 1000, lon: 13.4, stops: 2,
                          totalWait: 60, lastSeen: noon, passes: 5)
        }
        let m = try? XCTUnwrap(s.signalMeasurement)
        XCTAssertEqual(m?.passes, 100)
        XCTAssertEqual(m?.stops, 40)
        XCTAssertEqual(m?.wait, 1_200)
        // 1 200 s auf 100 Vorbeifahrten sind 12 s je Ampel — gerundet auf den
        // Stepper: 10.
        s.calibrate(from: [ride(0, km: 20, movingKmh: 24, standing: 600),
                           ride(1, km: 20, movingKmh: 24, standing: 600),
                           ride(2, km: 20, movingKmh: 24, standing: 600)])
        XCTAssertEqual(s.signalWaitSeconds, 10)
    }

    func testTooFewPassesLeaveTheSettingAlone() {
        let s = settings()
        s.learnedSignals = [LearnedSignal(lat: 52.5, lon: 13.4, stops: 3, totalWait: 300,
                                          lastSeen: noon, passes: 4)]
        s.calibrate(from: [ride(0, km: 20, movingKmh: 24, standing: 600),
                           ride(1, km: 20, movingKmh: 24, standing: 600),
                           ride(2, km: 20, movingKmh: 24, standing: 600)])
        XCTAssertEqual(s.signalWaitSeconds, 20, "vier Vorbeifahrten sind keine Messung")
    }

    // MARK: Was noch kommt

    /// Eine gerade Straße hat oft nur an den Enden einen Stützpunkt. Die
    /// Ampel in der Mitte liegt trotzdem auf ihr.
    func testALightHalfwayAlongAStraightStretchCounts() {
        let route = [east(0), east(1000)]
        let cum = TurnGuide.cumulative(route)
        let stations = RideTracker.stations(of: [east(500), east(510)], on: route, cum: cum)
        XCTAssertEqual(stations.count, 1, "zwei Knoten einer Kreuzung sind eine Ampel")
        XCTAssertEqual(stations.first ?? 0, 500, accuracy: 5)
    }

    /// Nach einer Neuplanung zählt die Anzeige die ganze Fahrt weiter.
    func testProgressKeepsTheLightsBehindAReplan() {
        let route = stride(from: 0.0, through: 1000, by: 50).map { east($0) }
        let cum = TurnGuide.cumulative(route)
        let p = RideTracker.progress(travelled: 0, cum: cum, stations: [300, 700], behind: 5)
        XCTAssertEqual(p.plannedSignals, 7)
        XCTAssertEqual(p.signalsPassed, 5)
        XCTAssertEqual(p.signalsLeft, 2)
    }

    func testStationsAndProgressAlongTheRoute() {
        let route = stride(from: 0.0, through: 1000, by: 50).map { east($0) }
        let cum = TurnGuide.cumulative(route)
        // Drei Ampeln auf der Linie, eine hundert Meter daneben.
        let signals = [east(200), east(500), east(900),
                       CLLocationCoordinate2D(latitude: base.latitude + 0.002, longitude: base.longitude)]
        let stations = RideTracker.stations(of: signals, on: route, cum: cum)
        XCTAssertEqual(stations.count, 3, "was nicht auf der Route liegt, kommt auch nicht auf ihr")
        XCTAssertEqual(stations[0], 200, accuracy: 30)
        let start = RideTracker.progress(travelled: 0, cum: cum, stations: stations)
        XCTAssertEqual(start.signalsLeft, 3)
        XCTAssertEqual(start.metersLeft, 1000, accuracy: 5)
        let half = RideTracker.progress(travelled: 550, cum: cum, stations: stations)
        XCTAssertEqual(half.signalsPassed, 2)
        XCTAssertEqual(half.signalsLeft, 1)
        XCTAssertEqual(half.metersLeft, 450, accuracy: 5)
    }

    func testTheRemainingTimeFallsBackToSpeedAndLights() throws {
        let s = settings()
        s.calibratedBikeSpeedKmh = 20
        s.calibratedSignalWaitSeconds = 30
        let p = RideTracker.Progress(metersLeft: 5_000, signalsLeft: 4, signalsPassed: 2,
                                     plannedSignals: 6, plannedMeters: 10_000)
        // Ohne laufende Fahrt und ohne Plan: Rolltempo plus Ampeln.
        func left(_ s: AppSettings) throws -> RideRemaining {
            try XCTUnwrap(RideRemaining.from(progress: p, ridden: 0, rideKmh: 0,
                                             plannedKmh: nil, settings: s))
        }
        XCTAssertEqual(try left(s).seconds, 900 + 120, accuracy: 1)
        XCTAssertEqual(try left(s).signals, 4)
        // Und auch hier gewinnt die Messung — langsamer …
        s.calibratedBikeOverallKmh = 12
        XCTAssertEqual(try left(s).seconds, 5_000 / (12 / 3.6), accuracy: 1)
        // … wie schneller.
        s.calibratedBikeOverallKmh = 30
        XCTAssertEqual(try left(s).seconds, 5_000 / (30 / 3.6), accuracy: 1)
    }

    /// Der Fall, der auf der Autofahrt anderthalb Stunden für dreißig
    /// Kilometer Landstraße ansagte: die Restzeit rechnete mit dem Rolltempo
    /// des **Fahrrads**, weil sie nie erfahren hat, was gerade gefahren wird.
    /// Jetzt zählt der Schnitt, den der Plan dieser Fahrt versprochen hat.
    func testTheRemainingTimeFollowsThePlannedAverageOfThisRide() throws {
        let s = settings()
        s.calibratedBikeSpeedKmh = 20
        let p = RideTracker.Progress(metersLeft: 30_900, signalsLeft: 4, signalsPassed: 3,
                                     plannedSignals: 7, plannedMeters: 32_000)
        // 32 km in 32 min: eine Autofahrt mit 60 km/h Schnitt, gerade erst los.
        let left = try XCTUnwrap(RideRemaining.from(progress: p, ridden: 1_800, rideKmh: 25.6,
                                                    plannedKmh: 60, settings: s))
        XCTAssertEqual(left.seconds, 30_900 / (60 / 3.6), accuracy: 30, "30,9 km bei 60 km/h sind gut 31 min")
        XCTAssertLessThan(left.seconds, 2_400, "und ganz sicher keine anderthalb Stunden")
    }

    /// Ist genug gefahren, zählt der Schnitt **dieser** Fahrt — der kennt den
    /// Stau, den der Plan nicht kannte.
    func testOnceEnoughIsRiddenTheRideItselfDecides() throws {
        let p = RideTracker.Progress(metersLeft: 20_000, signalsLeft: 2, signalsPassed: 4,
                                     plannedSignals: 6, plannedMeters: 32_000)
        let left = try XCTUnwrap(RideRemaining.from(progress: p, ridden: 12_000, rideKmh: 40,
                                                    plannedKmh: 60, settings: settings()))
        XCTAssertEqual(left.seconds, 20_000 / (40 / 3.6), accuracy: 30)
    }

    func testNothingLeftWhenNothingWasPlanned() {
        XCTAssertNil(RideRemaining.from(progress: nil, ridden: 0, rideKmh: 0,
                                        plannedKmh: nil, settings: settings()))
        let done = RideTracker.Progress(metersLeft: 0, signalsLeft: 0, signalsPassed: 6,
                                        plannedSignals: 6, plannedMeters: 10_000)
        XCTAssertNil(RideRemaining.from(progress: done, ridden: 0, rideKmh: 0,
                                        plannedKmh: nil, settings: settings()))
    }

    // MARK: Höhenprofil

    func testTheElevationProfileSmoothsTheReceiversNoise() throws {
        // Eine Ebene, auf der der Empfänger um ±8 m springt: ohne Glättung
        // ergäbe das hunderte Höhenmeter.
        let points: [RidePoint] = (0..<200).map { i in
            let c = east(Double(i) * 10)
            let wobble: Double = i % 2 == 0 ? 8 : -8
            return RidePoint(lat: c.latitude, lon: c.longitude,
                             t: noon.addingTimeInterval(Double(i)), v: 5, h: 35 + wobble)
        }
        let flat = try XCTUnwrap(ElevationProfile.from(points))
        XCTAssertLessThan(flat.ascent, 20, "eine Ebene bleibt eine Ebene")
        XCTAssertEqual(flat.distances.last ?? 0, 1990, accuracy: 50)

        // Und ein echter Anstieg bleibt einer.
        let hill: [RidePoint] = (0..<200).map { i in
            let c = east(Double(i) * 10)
            return RidePoint(lat: c.latitude, lon: c.longitude,
                             t: noon.addingTimeInterval(Double(i)), v: 5, h: 35 + Double(i) * 0.5)
        }
        let up = try XCTUnwrap(ElevationProfile.from(hill))
        // Knapp unter den echten 99,5 m: die Schwelle, die das Rauschen
        // wegnimmt, nimmt auch das letzte angefangene Stück mit.
        XCTAssertGreaterThan(up.ascent, 90)
        XCTAssertLessThanOrEqual(up.ascent, 99.5)
        XCTAssertEqual(up.highest - up.lowest, 99.5, accuracy: 5)
    }

    func testWithoutHeightsThereIsNoProfile() {
        let points: [RidePoint] = (0..<50).map { i in
            RidePoint(lat: base.latitude, lon: base.longitude,
                      t: noon.addingTimeInterval(Double(i)), v: 5, h: nil)
        }
        XCTAssertNil(ElevationProfile.from(points))
    }

    /// Bis 1.12 ließ sich jeder gemessene Wert „von Hand" überstimmen. Die
    /// Regler sind weg: was jemand gestellt hatte, gilt nicht mehr und wird
    /// beim Laden gelöscht, damit es nicht über iCloud zurückkommt.
    func testAnOldManualValueNoLongerCounts() {
        let d = UserDefaults(suiteName: UUID().uuidString)!
        d.set(26.0, forKey: "bikeMovingSpeedKmh")
        d.set(25, forKey: "signalWaitSeconds")
        d.set(22.0, forKey: "bikeSpeedOverride")
        d.set(35, forKey: "signalWaitOverride")
        d.set(17.0, forKey: "bikeOverallOverride")
        d.set(33.0, forKey: "carOverallOverride")
        d.set(1, forKey: "optionsPerMode")
        let s = AppSettings(defaults: d)
        XCTAssertEqual(s.snapshot.bikeSpeedKmh, 26)
        XCTAssertEqual(s.snapshot.signalWaitSeconds, 25)
        XCTAssertNil(s.snapshot.measuredOverallKmh)
        XCTAssertEqual(s.snapshot.optionsPerMode, PlanSettings().optionsPerMode)
        for key in AppSettings.retiredKeys { XCTAssertNil(d.object(forKey: key), key) }
    }

    /// Wer von 1.9.1 kommt, hat seine Werte unter den alten Schlüsseln — sie
    /// gelten als gemessen, nichts ist von Hand gestellt.
    func testOldValuesCountAsMeasured() {
        let d = UserDefaults(suiteName: UUID().uuidString)!
        d.set(26.0, forKey: "bikeMovingSpeedKmh")
        d.set(25, forKey: "signalWaitSeconds")
        d.set(19.5, forKey: "bikeOverallKmh")
        d.set(38.0, forKey: "carOverallKmh")
        let s = AppSettings(defaults: d)
        XCTAssertEqual(s.calibratedBikeSpeedKmh, 26)
        XCTAssertEqual(s.calibratedSignalWaitSeconds, 25)
        XCTAssertEqual(s.calibratedBikeOverallKmh, 19.5)
        XCTAssertEqual(s.calibratedCarOverallKmh, 38)
        XCTAssertEqual(s.bikeSpeedKmh, 26)
    }

    /// Rad und Auto haben je ihren eigenen Schnitt: Autofahrten schieben den
    /// Rad-Schnitt nicht, und der Auto-Schnitt wird erst mit drei Fahrten.
    func testCarAndBikeAveragesAreSeparate() {
        let s = settings()
        func ride(_ mode: TravelMode, km: Double, minutes: Double, day: Double) -> Ride {
            Ride(started: Date(timeIntervalSince1970: 1_780_000_000 + day * 86_400),
                 ended: Date(timeIntervalSince1970: 1_780_000_000 + day * 86_400 + minutes * 60),
                 origin: "A", destination: "B", mode: mode.rawValue, meters: km * 1000,
                 movingSeconds: minutes * 50, maxKmh: 60, signalStops: 0, otherStops: 0,
                 signalWaitTotal: 0, plannedSeconds: nil)
        }
        let cars = (0..<3).map { ride(.car, km: 20, minutes: 30, day: Double($0)) }   // 40 km/h
        s.calibrate(from: cars)
        s.calibrateCar(from: cars)
        XCTAssertEqual(s.bikeOverallKmh, 0, "Autofahrten sind kein Rad-Schnitt")
        XCTAssertEqual(s.carOverallKmh, 40, accuracy: 0.5)
        XCTAssertEqual(s.snapshot.carOverallKmh ?? 0, 40, accuracy: 0.5)
        let bikes = (0..<3).map { ride(.bike, km: 10, minutes: 30, day: Double($0) + 10) }  // 20 km/h
        s.calibrate(from: cars + bikes)
        XCTAssertEqual(s.bikeOverallKmh, 20, accuracy: 0.5)
        XCTAssertEqual(s.carOverallKmh, 40, accuracy: 0.5, "und umgekehrt")
    }
}
