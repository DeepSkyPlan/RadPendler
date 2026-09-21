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

    private func train(_ name: String, dep: TimeInterval, arr: TimeInterval, bike: Bool = true,
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
            station2: "Beispielplatz", ride2: line(3500), settings: settings, earliestLeave: t0.addingTimeInterval(300)))
        XCTAssertEqual(option.leave, t0.addingTimeInterval(21 * 60))
        XCTAssertEqual(option.getReady, t0.addingTimeInterval(16 * 60))
        // arrive 55 min + 3 min buffer + 10 min ride (3 500 m)
        XCTAssertEqual(option.arrival, t0.addingTimeInterval(68 * 60))
        XCTAssertEqual(option.legs.map(\.kind), [.bike, .transit(line: "S7", product: .suburban), .bike])
        XCTAssertEqual(option.bikeDistance, 5600)
    }

    func testComposeRejectsTrainWithoutBikeCarriage() {
        let journey = [train("S7", dep: 30 * 60, arr: 40 * 60), train("RE1", dep: 45 * 60, arr: 55 * 60, bike: false)]
        XCTAssertNil(BikeTransitComposer.compose(
            origin: from, destination: to, station1: "A", ride1: line(1000), journey: journey,
            station2: "B", ride2: line(1000), settings: settings, earliestLeave: t0))
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

    func testHistoryMergeFallsBackWhenOneSideIsUnreadable() {
        let good = try! JSONEncoder().encode([PlaceUse(place: place("A", 52, 13), count: 1, lastUsed: t0)])
        XCTAssertNil(CloudStore.mergedHistory(local: nil, cloud: good), "nothing local: take what came in")
        XCTAssertNil(CloudStore.mergedHistory(local: Data("kaputt".utf8), cloud: good))
        XCTAssertNotNil(CloudStore.mergedHistory(local: good, cloud: good))
    }
}
