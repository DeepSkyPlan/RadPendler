import CoreLocation
import XCTest
@testable import Pendel

final class PlannerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_003_700)   // Mon 2026-09-21 17:15 CEST
    private let settings = PlanSettings()

    private func line(_ meters: Double) -> StreetRoute {
        // ~meters due south of the office
        let a = Place.office.coordinate
        let b = CLLocationCoordinate2D(latitude: a.latitude - meters / 111_320, longitude: a.longitude)
        return StreetRoute(distance: meters, expectedTravelTime: 0, coordinates: [a, b])
    }

    private func train(_ name: String, dep: TimeInterval, arr: TimeInterval, bike: Bool = true) -> Leg {
        Leg(kind: .transit(line: name, product: .suburban), fromName: "A", toName: "B",
            departure: t0.addingTimeInterval(dep), arrival: t0.addingTimeInterval(arr),
            coordinates: [Place.office.coordinate, Place.home.coordinate], bikeCarriage: bike)
    }

    func testDefaultBikeSpeedIs21() {
        XCTAssertEqual(AppSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!).bikeSpeedKmh, 21)
        // 21 km at 21 km/h = one hour
        XCTAssertEqual(settings.bikeTime(21_000), 3600, accuracy: 1)
    }

    func testDefaultsAreOfficeToHomeWithFiveMinutesPrep() {
        let s = AppSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        XCTAssertEqual(s.origin, .office)
        XCTAssertEqual(s.destination, .home)
        XCTAssertEqual(s.prepMinutes, 5)
        s.swapDirection()
        XCTAssertEqual(s.origin, .home)
    }

    func testComposeLeavesAsLateAsCatchesTheTrain() throws {
        // 2 100 m at 21 km/h = 6 min, +3 min buffer → leave 9 min before the train.
        let journey = [train("S7", dep: 30 * 60, arr: 55 * 60)]
        let option = try XCTUnwrap(BikeTransitComposer.compose(
            origin: .office, destination: .home, station1: "Hbf", ride1: line(2100), journey: journey,
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
            origin: .office, destination: .home, station1: "A", ride1: line(1000), journey: journey,
            station2: "B", ride2: line(1000), settings: settings, earliestLeave: t0))
    }

    func testComposeRejectsTrainThatCannotBeReachedAfterPrep() {
        // Train in 10 min, but ride (6 min) + buffer (3) + prep (5) = 14 min.
        let journey = [train("S7", dep: 10 * 60, arr: 30 * 60)]
        XCTAssertNil(BikeTransitComposer.compose(
            origin: .office, destination: .home, station1: "A", ride1: line(2100), journey: journey,
            station2: "B", ride2: line(1000), settings: settings, earliestLeave: t0.addingTimeInterval(300)))
    }

    func testBestDropsDuplicateTrainsKeepingLatestLeave() throws {
        let journey = [train("S1", dep: 30 * 60, arr: 55 * 60)]
        let near = try XCTUnwrap(BikeTransitComposer.compose(
            origin: .office, destination: .home, station1: "near", ride1: line(1000), journey: journey,
            station2: "B", ride2: line(2000), settings: settings, earliestLeave: t0))
        let far = try XCTUnwrap(BikeTransitComposer.compose(
            origin: .office, destination: .home, station1: "far", ride1: line(4000), journey: journey,
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
            o.rain = RainAssessment(readings: [RainReading(sample: RainSample(coordinate: Place.home.coordinate, time: t0),
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

    func testRankingPrefersActiveModeWithinThreeMinutes() {
        let bike = option(.bike, arrive: 61)
        let car = option(.car, arrive: 60)
        XCTAssertTrue(TripPlanner.ranking(bike, car))
        XCTAssertFalse(TripPlanner.ranking(option(.bike, arrive: 70), car))
    }
}
