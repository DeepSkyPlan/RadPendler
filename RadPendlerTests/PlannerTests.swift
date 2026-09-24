import CoreLocation
import XCTest
@testable import RadPendler

final class PlannerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_003_700)   // Mon 2026-09-21 17:15 CEST
    /// 21 km/h keeps the hand-computed times below round.
    private let settings = PlanSettings(bikeSpeedKmh: 21)

    private let from = Place(name: "Start", latitude: 52.50, longitude: 13.35)
    private let to = Place(name: "Ziel", latitude: 52.42, longitude: 13.24)

    private func line(_ meters: Double) -> StreetRoute {
        // ~meters due south of the start
        let a = from.coordinate
        let b = CLLocationCoordinate2D(latitude: a.latitude - meters / 111_320, longitude: a.longitude)
        return StreetRoute(distance: meters, expectedTravelTime: 0, coordinates: [a, b])
    }

    private func train(_ name: String, dep: TimeInterval, arr: TimeInterval,
                       bike: BikeCarriage = .yes,
                       product: TransitProduct = .suburban) -> Leg {
        Leg(kind: .transit(line: name, product: product), fromName: "A", toName: "B",
            departure: t0.addingTimeInterval(dep), arrival: t0.addingTimeInterval(arr),
            coordinates: [from.coordinate, to.coordinate], bikeCarriage: bike)
    }

    func testDefaultRollingSpeedAndLightsGiveTheMeasured21KmhAverage() {
        let d = UserDefaults(suiteName: UUID().uuidString)!
        d.set(21.0, forKey: "bikeSpeedKmh")   // 0.1.x all-in average must not be read as rolling speed
        XCTAssertEqual(AppSettings(defaults: d).bikeSpeedKmh, 29)
        let defaults = PlanSettings()
        XCTAssertEqual(defaults.bikeTime(29_000), 3600, accuracy: 1)
        // Commute check: 20 km with ~50 lit junctions at 20 s ≈ 21 km/h door to door.
        var r = StreetRoute(distance: 20_000, expectedTravelTime: 0, coordinates: [])
        r.signals = 50
        XCTAssertEqual(20.0 / (defaults.rideTime(r) / 3600), 21, accuracy: 1)
    }

    func testShipsWithoutAddressesAndKeepsWhatIsPicked() {
        let suite = UUID().uuidString
        let s = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertNil(s.origin, "no address is built into the app")
        XCTAssertNil(s.destination)
        XCTAssertFalse(s.isReady)
        XCTAssertEqual(s.prepMinutes, 5)

        s.origin = from
        s.destination = to
        s.swapDirection()
        XCTAssertEqual(s.origin, to)
        XCTAssertTrue(s.isReady)
        // Kept for the next launch, cleared on request.
        XCTAssertEqual(AppSettings(defaults: UserDefaults(suiteName: suite)!).origin, to)
        s.clearPlaces()
        XCTAssertNil(AppSettings(defaults: UserDefaults(suiteName: suite)!).origin)
    }

    func testComposeLeavesAsLateAsCatchesTheTrain() throws {
        // 2 100 m at 21 km/h = 6 min, +3 min buffer → leave 9 min before the train.
        let journey = [train("S7", dep: 30 * 60, arr: 55 * 60)]
        let option = try XCTUnwrap(BikeTransitComposer.compose(
            origin: from, destination: to, station1: "Hbf", ride1: line(2100), journey: journey,
            station2: "Bahnhof B", ride2: line(3500), settings: settings, earliestLeave: t0.addingTimeInterval(300)))
        XCTAssertEqual(option.leave, t0.addingTimeInterval(21 * 60))
        XCTAssertEqual(option.getReady, t0.addingTimeInterval(16 * 60))
        // arrive 55 min + 3 min buffer + 10 min ride (3 500 m)
        XCTAssertEqual(option.arrival, t0.addingTimeInterval(68 * 60))
        XCTAssertEqual(option.legs.map(\.kind), [.bike, .transit(line: "S7", product: .suburban), .bike])
        XCTAssertEqual(option.bikeDistance, 5600)
    }

    func testATrainNobodyHasJudgedIsOfferedWithAWarning() {
        // No FK remark is not a "no" — it is a question for the user, and the
        // trip is worth showing while it is open.
        let journey = [train("S7", dep: 30 * 60, arr: 40 * 60),
                       train("RE1", dep: 45 * 60, arr: 55 * 60, bike: .unknown)]
        let option = BikeTransitComposer.compose(
            origin: from, destination: to, station1: "A", ride1: line(1000), journey: journey,
            station2: "B", ride2: line(1000), settings: settings, earliestLeave: t0)
        XCTAssertNotNil(option)
        XCTAssertTrue(option?.bikeCarriageUnclear ?? false)
        XCTAssertEqual(option?.transitLegs.filter { $0.bikeCarriage == .unknown }.compactMap(\.lineName), ["RE1"])
    }

    func testALineTheUserRuledOutIsGone() {
        var s = settings
        s.bikeLineStatus = ["RE1": false]
        let journey = [train("S7", dep: 30 * 60, arr: 40 * 60),
                       train("RE1", dep: 45 * 60, arr: 55 * 60, bike: .unknown)]
        XCTAssertNil(BikeTransitComposer.compose(
            origin: from, destination: to, station1: "A", ride1: line(1000), journey: journey,
            station2: "B", ride2: line(1000), settings: s, earliestLeave: t0))
    }

    func testTheUsersWordBeatsTheTimetable() {
        var s = settings
        s.bikeLineStatus = ["RE1": true]
        let journey = [train("RE1", dep: 30 * 60, arr: 55 * 60, bike: .unknown)]
        let option = BikeTransitComposer.compose(
            origin: from, destination: to, station1: "A", ride1: line(1000), journey: journey,
            station2: "B", ride2: line(1000), settings: s, earliestLeave: t0)
        XCTAssertEqual(option?.transitLegs.first?.bikeCarriage, .yes)
        XCTAssertFalse(option?.bikeCarriageUnclear ?? true, "decided is decided — no warning")
    }

    func testTheLineListFillsItselfAndKeepsWhatWasDecided() {
        let t = t0
        var lines: [BikeLine] = []
        lines = lines.noting([("S7", .yes), ("M11", .unknown)], now: t)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines.first { $0.name == "S7" }?.allowed, true, "what the timetable vouches for is pre-filled")
        XCTAssertNil(lines.first { $0.name == "M11" }?.allowed, "the rest stays open")

        lines = lines.map { $0.name == "M11" ? BikeLine(name: "M11", allowed: false, lastSeen: t) : $0 }
        lines = lines.noting([("M11", .yes), ("RE1", .unknown)], now: t.addingTimeInterval(60))
        XCTAssertEqual(lines.first { $0.name == "M11" }?.allowed, false,
                       "a decision the user made is never overwritten by the timetable")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines.status, ["S7": true, "M11": false])
        XCTAssertEqual(lines.sortedForList.map(\.name), ["S7", "M11", "RE1"],
                       "decided first, the open ones last — they are the list's job")
    }

    func testComposeRejectsTrainThatCannotBeReachedAfterPrep() {
        // Train in 10 min, but ride (6 min) + buffer (3) + prep (5) = 14 min.
        let journey = [train("S7", dep: 10 * 60, arr: 30 * 60)]
        XCTAssertNil(BikeTransitComposer.compose(
            origin: from, destination: to, station1: "A", ride1: line(2100), journey: journey,
            station2: "B", ride2: line(1000), settings: settings, earliestLeave: t0.addingTimeInterval(300)))
    }

    func testBestDropsDuplicateTrainsKeepingLatestLeave() throws {
        let journey = [train("S1", dep: 30 * 60, arr: 55 * 60)]
        let near = try XCTUnwrap(BikeTransitComposer.compose(
            origin: from, destination: to, station1: "near", ride1: line(1000), journey: journey,
            station2: "B", ride2: line(2000), settings: settings, earliestLeave: t0))
        let far = try XCTUnwrap(BikeTransitComposer.compose(
            origin: from, destination: to, station1: "far", ride1: line(4000), journey: journey,
            station2: "B", ride2: line(2000), settings: settings, earliestLeave: t0))
        let best = BikeTransitComposer.best([far, near], count: 3)
        XCTAssertEqual(best.count, 1)
        XCTAssertEqual(best.first?.legs.first?.toName, "near")
    }

    // MARK: Recommendation

    private func option(_ mode: TravelMode, arrive minutes: Double, rainMm: Double? = nil) -> TripOption {
        let kind: LegKind = mode == .car ? .car : (mode == .transit ? .transit(line: "S1", product: .suburban) : .bike)
        var o = TripOption(mode: mode, legs: [Leg(kind: kind, fromName: "a", toName: "b", departure: t0,
                                                  arrival: t0.addingTimeInterval(minutes * 60))], prep: 300)
        if let rainMm {
            o.rain = RainAssessment(readings: [RainReading(sample: RainSample(coordinate: to.coordinate, time: t0),
                                                           millimetres: rainMm, probability: rainMm > 0 ? 90 : 0)])
        }
        return o
    }

    func testDryWeatherRecommendsBikeEvenIfCarIsFaster() {
        let bike = option(.bike, arrive: 60, rainMm: 0)
        let options = [option(.car, arrive: 40), bike, option(.transit, arrive: 55), option(.bikeTransit, arrive: 62, rainMm: 0)]
        XCTAssertEqual(TripPlanner.recommend(options)?.optionID, bike.id)
    }

    func testRainRecommendsBikeInTrain() {
        let bt = option(.bikeTransit, arrive: 62, rainMm: 0)
        let options = [option(.car, arrive: 40), option(.bike, arrive: 60, rainMm: 1.2), option(.transit, arrive: 55), bt]
        XCTAssertEqual(TripPlanner.recommend(options)?.optionID, bt.id)
    }

    // MARK: S-Bahn first, U-Bahn only as alternative

    private func bikeTrain(_ legs: [Leg]) throws -> TripOption {
        try XCTUnwrap(BikeTransitComposer.compose(
            origin: from, destination: to, station1: "A", ride1: line(1000), journey: legs,
            station2: "B", ride2: line(1000), settings: settings, earliestLeave: t0))
    }

    func testUBahnMakesAnAlternativeRegionalDoesNot() throws {
        XCTAssertFalse(try bikeTrain([train("S1", dep: 1800, arr: 3000)]).isAlternative)
        XCTAssertFalse(try bikeTrain([train("RE3", dep: 1800, arr: 2400, product: .regional),
                                      train("S26", dep: 2600, arr: 3000)]).isAlternative)
        XCTAssertTrue(try bikeTrain([train("U9", dep: 1800, arr: 2400, product: .subway),
                                     train("S1", dep: 2600, arr: 3000)]).isAlternative)
    }

    func testRecommendationTakesSBahnEvenIfUBahnIsFaster() throws {
        var viaU = try bikeTrain([train("U9", dep: 1800, arr: 2400, product: .subway), train("S1", dep: 2500, arr: 2900)])
        var viaS = try bikeTrain([train("S7", dep: 1800, arr: 3300)])
        let dry = RainAssessment(readings: [])
        viaU.rain = dry; viaS.rain = dry
        var bike = option(.bike, arrive: 90, rainMm: 1.5)
        bike.rain = RainAssessment(readings: [RainReading(sample: RainSample(coordinate: to.coordinate, time: t0),
                                                          millimetres: 1.5, probability: 90)])
        XCTAssertEqual(TripPlanner.recommend([viaU, viaS, bike])?.optionID, viaS.id)
        // Without any S-Bahn connection the U-Bahn one is recommended.
        XCTAssertEqual(TripPlanner.recommend([viaU, bike])?.optionID, viaU.id)
    }

    func testRankKeepsOneAlternativeUnlessNoSBahnExists() throws {
        let s1 = try bikeTrain([train("S1", dep: 1800, arr: 3300)])
        let s7 = try bikeTrain([train("S7", dep: 2400, arr: 3900)])
        let u1 = try bikeTrain([train("U9", dep: 1800, arr: 2400, product: .subway)])
        let u2 = try bikeTrain([train("U6", dep: 1900, arr: 2500, product: .subway)])
        let ranked = BikeTransitComposer.rank([u1, s7, u2, s1], preferred: 3, alternatives: 1)
        XCTAssertEqual(ranked.map(\.id), [s1.id, s7.id, u1.id])
        XCTAssertEqual(BikeTransitComposer.rank([u1, u2], preferred: 3, alternatives: 1).count, 2)
    }

    func testDirectTrainBeatsSlightlyFasterConnectionWithChange() throws {
        let change = try bikeTrain([train("RE3", dep: 1800, arr: 2400, product: .regional), train("S26", dep: 2500, arr: 2900)])
        let direct = try bikeTrain([train("S1", dep: 1800, arr: 3300)])   // 6.7 min later, 0 changes
        XCTAssertEqual(BikeTransitComposer.best([change, direct], count: 3).map(\.id), [direct.id, change.id])
        XCTAssertEqual(BikeTransitComposer.best([change, direct], count: 3, penalty: 0).map(\.id), [change.id, direct.id])
        XCTAssertEqual(TripPlanner.recommend([change, direct])?.optionID, direct.id)
        // 15 min earlier with one change is worth it at a 10-min penalty.
        let early = try bikeTrain([train("RE3", dep: 1800, arr: 2000, product: .regional), train("S26", dep: 2100, arr: 2300)])
        XCTAssertEqual(TripPlanner.recommend([early, direct])?.optionID, early.id)
    }

    func testRankingPrefersActiveModeWithinThreeMinutes() {
        let bike = option(.bike, arrive: 61)
        let car = option(.car, arrive: 60)
        XCTAssertTrue(TripPlanner.ranking(bike, car))
        XCTAssertFalse(TripPlanner.ranking(option(.bike, arrive: 70), car))
    }

    // MARK: Addresses that have been used before

    private func place(_ name: String, _ lat: Double, _ lon: Double,
                       plz: String? = nil, ort: String? = nil) -> Place {
        Place(name: name, latitude: lat, longitude: lon, postalCode: plz, locality: ort)
    }

    func testHistoryRanksByUseThenRecency() {
        let a = place("Musterstraße 1, 10557 Berlin", 52.5333, 13.3667, plz: "10557", ort: "Berlin")
        let b = place("Beispielweg 2, 14000 Musterort", 52.4086, 13.2261, plz: "14000", ort: "Musterort")
        let c = place("Bergstraße 1, 12169 Berlin", 52.4500, 13.3400, plz: "12169", ort: "Berlin")
        var history: [PlaceUse] = []
        history = history.recording(a, now: t0)
        history = history.recording(b, now: t0.addingTimeInterval(60))
        history = history.recording(a, now: t0.addingTimeInterval(120))
        history = history.recording(c, now: t0.addingTimeInterval(180))
        XCTAssertEqual(history.ranked.map(\.place.shortName),
                       ["Musterstraße 1", "Bergstraße 1", "Beispielweg 2"],
                       "twice used first, then the more recent of the two singles")
        XCTAssertEqual(history.ranked.first?.count, 2)
    }

    func testHistoryMergesTheSameAddressAndSearchesUmlautBlind() {
        let a = place("Musterstraße 1, 10557 Berlin", 52.53331, 13.36671)
        let again = place("Musterstraße 1, 10557 Berlin", 52.53334, 13.36674)   // ~4 m apart
        let history = [PlaceUse]().recording(a, now: t0).recording(again, now: t0.addingTimeInterval(60))
        XCTAssertEqual(history.count, 1, "the same address picked twice is one entry")
        XCTAssertEqual(history[0].count, 2)
        XCTAssertEqual(history.matching("musterstrasse").count, 1)
        XCTAssertEqual(history.matching("14000").count, 0)
    }

    func testHistoryDropsTheLeastUsedWhenItIsFull() {
        var history: [PlaceUse] = []
        for i in 0..<5 {
            history = history.recording(place("Straße \(i)", 52.0 + Double(i) / 100, 13.0),
                                        now: t0.addingTimeInterval(Double(i)), limit: 3)
        }
        XCTAssertEqual(history.count, 3)
        XCTAssertEqual(history.ranked.map(\.place.shortName), ["Straße 4", "Straße 3", "Straße 2"])
    }

    func testPostalCodeIsShownAndSurvivesOlderAddresses() {
        let withFields = place("Musterstraße 1, 10557 Berlin", 52.53, 13.36, plz: "10557", ort: "Berlin")
        XCTAssertEqual(withFields.areaLine, "10557 Berlin")
        XCTAssertEqual(withFields.withArea, "Musterstraße 1, 10557 Berlin")
        // Saved before 0.9: no fields, the area has to come out of the name.
        let older = place("Beispielweg 2, 14000 Musterort, Deutschland", 52.40, 13.22)
        XCTAssertEqual(older.areaLine, "14000 Musterort")
        let bare = place("Irgendwo", 52.0, 13.0)
        XCTAssertNil(bare.areaLine)
        XCTAssertEqual(bare.withArea, "Irgendwo")
    }

    func testHistoryMergeKeepsWhatEitherDeviceKnew() {
        let a = place("Musterstraße 1", 52.5333, 13.3667)
        let b = place("Beispielweg 2", 52.4086, 13.2261)
        let c = place("Potsdamer Platz 1", 52.5096, 13.3760)
        let phone = [PlaceUse(place: a, count: 5, lastUsed: t0),
                     PlaceUse(place: b, count: 2, lastUsed: t0)]
        let pad = [PlaceUse(place: a, count: 3, lastUsed: t0.addingTimeInterval(600)),
                   PlaceUse(place: c, count: 1, lastUsed: t0)]
        let merged = phone.merging(pad)
        XCTAssertEqual(merged.map(\.place.shortName), ["Musterstraße 1", "Beispielweg 2", "Potsdamer Platz 1"],
                       "nothing either side knew may fall out")
        XCTAssertEqual(merged[0].count, 5, "the higher count wins")
        XCTAssertEqual(merged[0].lastUsed, t0.addingTimeInterval(600), "the later use wins")
    }

    func testAMergeFallsBackWhenOneSideIsUnreadable() {
        let good = try! JSONEncoder().encode([PlaceUse(place: place("A", 52, 13), count: 1, lastUsed: t0)])
        let key = "placeHistory"
        XCTAssertNil(CloudStore.merged(key, local: nil, cloud: good), "nothing local: take what came in")
        XCTAssertNil(CloudStore.merged(key, local: Data("kaputt".utf8), cloud: good))
        XCTAssertNotNil(CloudStore.merged(key, local: good, cloud: good))
    }

    /// The rides go through the same gate, with their own merge behind it.
    func testTheRidesUseTheirOwnMerge() {
        let t = Date(timeIntervalSince1970: 1_780_000_000)
        func ride(_ n: Int) -> Ride {
            Ride(started: t.addingTimeInterval(Double(n) * 86_400), ended: t.addingTimeInterval(Double(n) * 86_400 + 1200),
                 origin: "A", destination: "B", mode: TravelMode.bike.rawValue, meters: 8000,
                 movingSeconds: 1100, maxKmh: 30, signalStops: 3, otherStops: 0,
                 signalWaitTotal: 60, plannedSeconds: nil)
        }
        let shared = ride(0)
        let mine = RideStore.encode([shared, ride(-1)])!
        let theirs = RideStore.encode([shared, ride(-2)])!
        guard let out = CloudStore.merged(CloudStore.ridesKey, local: mine, cloud: theirs) else {
            return XCTFail("nicht zusammengeführt")
        }
        XCTAssertEqual(RideStore.decode(out)?.count, 3)
        XCTAssertNil(CloudStore.merged(CloudStore.ridesKey, local: nil, cloud: theirs))
        XCTAssertNil(CloudStore.merged(CloudStore.ridesKey, local: Data("kaputt".utf8), cloud: theirs))
    }

    // MARK: Long trips

    @MainActor func testBikeAloneGoesLastBeyondTheThreshold() {
        // A planner whose clients point nowhere: the test is about the order of
        // the boxes, not about the timetable, and a unit test may not call
        // BRouter, Overpass, VBB, Open-Meteo and MapKit on every run.
        let model = PlanModel(planner: .offline)
        let suite = UUID().uuidString
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        // Musterstraße → Beispielweg: 23 km, the commute.
        settings.origin = Place(name: "Musterstraße 1", latitude: 52.5333, longitude: 13.3667)
        settings.destination = Place(name: "Beispielweg 2", latitude: 52.4086, longitude: 13.2261)
        model.refresh(settings: settings)
        XCTAssertFalse(model.isLongTrip)
        XCTAssertEqual(model.modeOrder, [.bike, .bikeTransit, .car, .transit])

        // Berlin → Hamburg: 255 km.
        settings.destination = Place(name: "Hamburg Hbf", latitude: 53.5528, longitude: 10.0067)
        model.refresh(settings: settings)
        XCTAssertTrue(model.isLongTrip)
        XCTAssertEqual(model.modeOrder, [.bikeTransit, .car, .transit, .bike],
                       "the whole way by bike goes last, the rest keeps its order")
        XCTAssertEqual(model.directKm, 255, accuracy: 5)
    }

    func testOverpassIsNotAskedForACorridorItCannotAnswer() {
        let commute = RoadDataStore.Box(around: [CLLocationCoordinate2D(latitude: 52.5333, longitude: 13.3667),
                                                 CLLocationCoordinate2D(latitude: 52.4086, longitude: 13.2261)])
        XCTAssertFalse(commute.isTooLarge)
        let toHamburg = RoadDataStore.Box(around: [CLLocationCoordinate2D(latitude: 52.5333, longitude: 13.3667),
                                                   CLLocationCoordinate2D(latitude: 53.5528, longitude: 10.0067)])
        XCTAssertTrue(toHamburg.isTooLarge, "hundreds of megabytes is not a query, it is a hang")
    }

    func testTheNoteSaysWhyTheLightsAreMissing() {
        let s = PlanSettings()
        XCTAssertTrue(TripPlanner.noRoadDataNote(km: 23, settings: s).contains("nicht erreichbar"))
        XCTAssertTrue(TripPlanner.noRoadDataNote(km: 255, settings: s).contains("nicht gezählt"))
    }

    // MARK: Priorities

    func testModeOrderDecidesTheTieAndTheRecommendation() {
        // Two trips three minutes apart: the tie-break, not the clock, decides.
        let bike = option(.bike, arrive: 60)
        let car = option(.car, arrive: 61)
        XCTAssertTrue(TripPlanner.ranking(bike, car), "ships with Rad before Auto")
        XCTAssertTrue(TripPlanner.ranking(car, bike, order: [.car, .transit, .bike, .bikeTransit]),
                      "the user put Auto first")
    }

    func testRainLevelAtWhichTheBikeGoesIntoTheTrain() {
        // Drizzle on the bike route; the bike+rail trip arrives later.
        let drizzle = option(.bike, arrive: 55, rainMm: 0.3)
        let bikeTrain = option(.bikeTransit, arrive: 70, rainMm: 0)
        let options = [drizzle, bikeTrain]
        let bikeWins = TripPlanner.recommend(options, rainSwitch: .rain)
        XCTAssertEqual(bikeWins?.optionID, drizzle.id, "a shower is not enough to give up the ride")
        let trainWins = TripPlanner.recommend(options, rainSwitch: .possible)
        XCTAssertEqual(trainWins?.optionID, bikeTrain.id, "this user gives up at the first drop")
    }

    func testVariantOrderDecidesWhichRouteIsSuggested() {
        let quick = BikeCandidate(source: "fastbike",
                                  route: StreetRoute(distance: 22_000, expectedTravelTime: 0, coordinates: []),
                                  stats: BikeRouteStats(signals: 40, crossings: ["B 1"], mainRoadMeters: 4000))
        let calm = BikeCandidate(source: "safety",
                                 route: StreetRoute(distance: 24_000, expectedTravelTime: 0, coordinates: []),
                                 stats: BikeRouteStats(signals: 12, crossings: [], mainRoadMeters: 200))
        var s = PlanSettings(bikeSpeedKmh: 21)
        s.bikeVariantOrder = [.quiet, .balanced, .fastest, .shortest]
        let picked = BikeCandidate.pick([quick, calm], settings: s)
        XCTAssertEqual(picked.first?.1.first, .quiet, "the user asked for the quiet one first")
        XCTAssertEqual(picked.first?.0.route.distance, 24_000)

        s.bikeVariantOrder = [.shortest, .fastest, .balanced, .quiet]
        XCTAssertEqual(BikeCandidate.pick([quick, calm], settings: s).first?.1.first, .shortest)
    }

    func testCarVariantOrderAndAStoredOrderThatIsMissingAValue() {
        let motorway = CarCandidate(route: StreetRoute(distance: 30_000, expectedTravelTime: 28 * 60, coordinates: []),
                                    stats: BikeRouteStats(signals: 12, crossings: [], mainRoadMeters: 0))
        let town = CarCandidate(route: StreetRoute(distance: 21_000, expectedTravelTime: 35 * 60, coordinates: []),
                                stats: BikeRouteStats(signals: 41, crossings: [], mainRoadMeters: 0))
        XCTAssertEqual(CarCandidate.pick([motorway, town], order: [.fewSignals, .shortest, .fastest]).first?.1.first,
                       .fewSignals)
        // A list written before a variant existed must not drop it.
        let partial: [TravelMode] = storedOrder(["car", "bike"], fallback: TravelMode.defaultOrder)
        XCTAssertEqual(partial, [.car, .bike, .bikeTransit, .transit])
        XCTAssertEqual(storedOrder(nil, fallback: BikeVariant.defaultOrder), BikeVariant.defaultOrder)
    }

    func testPrioritiesSurviveALaunchAndCanBeReset() {
        let suite = UUID().uuidString
        let s = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(s.modeOrder, TravelMode.defaultOrder, "the shipped setup is the default")
        XCTAssertEqual(s.rainSwitchLevel, .light)
        s.modeOrder = [.transit, .car, .bike, .bikeTransit]
        s.bikeVariantOrder = [.quiet, .fastest, .balanced, .shortest]
        s.rainSwitchLevel = .rain
        let again = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(again.modeOrder, [.transit, .car, .bike, .bikeTransit])
        XCTAssertEqual(again.bikeVariantOrder.first, .quiet)
        XCTAssertEqual(again.rainSwitchLevel, .rain)
        again.resetPriorities()
        XCTAssertEqual(again.modeOrder, TravelMode.defaultOrder)
        XCTAssertEqual(again.rainSwitchLevel, .light)
    }

    func testCloudOnlyWritesWhatActuallyChanged() {
        XCTAssertTrue(CloudStore.same(nil, nil))
        XCTAssertFalse(CloudStore.same(5, nil))
        XCTAssertTrue(CloudStore.same(5, 5))
        XCTAssertTrue(CloudStore.same([10, 5, 1], [10, 5, 1]), "arrays compare by content")
        XCTAssertFalse(CloudStore.same([10, 5, 1], [10, 5]))
        let data = Data("Musterstraße".utf8)
        XCTAssertTrue(CloudStore.same(data, Data("Musterstraße".utf8)), "and so does the encoded history")
        XCTAssertFalse(CloudStore.same(data, Data("Beispielweg".utf8)))
    }

    func testEverySettingTheAppSavesAlsoTravelsThroughICloud() {
        // Building AppSettings writes every key it owns, because `load()`
        // assigns each property and every property saves itself. The suite's
        // own domain is therefore the complete list — no hand-kept second one.
        let suite = UUID().uuidString
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        // The four addresses are nil by default and then erase their key
        // instead of writing it; give them a value so they show up.
        settings.origin = from
        settings.destination = to
        settings.workPlace = to
        settings.homePlace = from
        let saved = Set((UserDefaults.standard.persistentDomain(forName: suite) ?? [:]).keys)
        XCTAssertFalse(saved.isEmpty, "the settings must write something, or this test proves nothing")
        // `settingsKeys`, not `keys`: the rides travel in the same store but
        // belong to RideStore, and AppSettings never writes them.
        let carried = Set(CloudStore.settingsKeys)
        XCTAssertTrue(saved.subtracting(carried).isEmpty,
                      "these settings never reach the other devices: \(saved.subtracting(carried).sorted())")
        XCTAssertTrue(carried.subtracting(saved).isEmpty,
                      "these keys are carried but nobody writes them: \(carried.subtracting(saved).sorted())")
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }

    /// Hält fest, warum `CloudStore` seinen Vergleichsstand erst **nach**
    /// `onPull` nimmt. `storedOrder` normalisiert beim Lesen, und zwei
    /// Fassungen normalisieren gegenläufig: die neuere hängt an, was die
    /// ältere nicht kennt, die ältere wirft es wieder weg. Ginge diese
    /// Normalisierung als vermeintliche Änderung zurück in die Wolke, schöben
    /// sich zwei Geräte den Wert endlos hin und her — und jede Runde kostet
    /// auf beiden Seiten ein vollständiges `load()`.
    func testTheOrderNormalisationDoesNotConvergeBetweenVersions() {
        let stored = ["fastest", "shortest", "balanced", "quiet"]
        let newer = storedOrder(stored, fallback: BikeVariant.allCases)
        XCTAssertEqual(newer, BikeVariant.allCases, "die neuere Fassung hängt an, was fehlt")
        let backAgain = storedOrder(newer.map(\.rawValue).filter { $0 != "lowTraffic" },
                                    fallback: BikeVariant.allCases)
        XCTAssertEqual(backAgain, newer, "und tut es beim nächsten Mal wieder")
        XCTAssertNotEqual(newer.map(\.rawValue), stored,
                          "die normalisierte Fassung ist nicht die gespeicherte — genau darum darf sie nicht hinaus")
    }

    // MARK: Wenn der Radrouter nicht antwortet

    /// Der öffentliche BRouter antwortet auf acht gleichzeitige Anfragen mit
    /// `403 Please, retry later!`. Höchstens drei auf einmal — und die
    /// Reihenfolge muss die der Liste bleiben, denn sie entscheidet bei
    /// Gleichstand, welche Route welche Rolle bekommt.
    func testTheRouterIsAskedInSmallHelpingsAndKeepsItsOrder() async {
        let counter = Counter()
        let items: [(String, Int, Int)] = (0..<9).map { ("r\($0)", $0, 0) }
        let got = await TripPlanner.gathered(items, atOnce: 3) { name, _, _ in
            await counter.enter()
            try? await Task.sleep(for: .milliseconds(20))
            await counter.leave()
            return StreetRoute(distance: 1000, expectedTravelTime: 300,
                               coordinates: [CLLocationCoordinate2D(latitude: 52.5, longitude: 13.4),
                                             CLLocationCoordinate2D(latitude: 52.51, longitude: 13.41)])
        }
        let peak = await counter.peak
        XCTAssertLessThanOrEqual(peak, 3, "nie mehr als drei gleichzeitig")
        XCTAssertEqual(got.map(\.0), items.map(\.0), "und am Ende wieder in der Reihenfolge der Liste")
    }

    /// Ohne BRouter bleibt eine einzige Linie von Apple übrig — eine Variante
    /// statt fünf. Das darf nicht stillschweigend passieren.
    func testMissingBikeRoutesAreSaidOutLoud() {
        let s = PlanSettings()
        XCTAssertEqual(TripPlanner.bikeNote(roadData: nil, brouterMissing: true, km: 8, settings: s),
                       "Nur die Route von Apple Karten — BRouter antwortet gerade nicht")
        XCTAssertEqual(TripPlanner.bikeNote(roadData: RoadData(signals: [], roads: []),
                                            brouterMissing: true, km: 8, settings: s),
                       "Nur die Route von Apple Karten — BRouter antwortet gerade nicht",
                       "die fehlende Route wiegt schwerer als die fehlende Ampelzahl")
        XCTAssertNotNil(TripPlanner.bikeNote(roadData: nil, brouterMissing: false, km: 8, settings: s))
        XCTAssertNil(TripPlanner.bikeNote(roadData: RoadData(signals: [], roads: []),
                                          brouterMissing: false, km: 8, settings: s))
    }
}

/// Zählt, wie viele Aufgaben gleichzeitig laufen.
private actor Counter {
    private var now = 0
    private(set) var peak = 0
    func enter() { now += 1; peak = Swift.max(peak, now) }
    func leave() { now -= 1 }
}
