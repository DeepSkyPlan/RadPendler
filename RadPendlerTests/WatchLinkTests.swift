import XCTest
@testable import RadPendler

/// Die Übersetzung Plan → Uhr. Sie hatte bis 1.4 keinen einzigen Test, obwohl
/// hier entschieden wird, was am Handgelenk steht — und **worauf der Countdown
/// dort zählt**: eine Warnung vor dem falschen Zug fällt niemandem auf, bis er
/// ihn verpasst.
final class WatchLinkTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private func leg(_ kind: LegKind, _ from: Double, _ to: Double, meters: Double = 1000) -> Leg {
        Leg(kind: kind, fromName: "A", toName: "B",
            departure: now.addingTimeInterval(from), arrival: now.addingTimeInterval(to),
            distance: meters)
    }

    private func bike() -> TripOption {
        TripOption(mode: .bike, legs: [leg(.bike, 0, 1800, meters: 9000)], prep: 300,
                   bikeRoute: BikeRouteInfo(variants: [.balanced], source: "safety"))
    }

    private func train() -> TripOption {
        TripOption(mode: .transit,
                   legs: [leg(.walk, 0, 300, meters: 200),
                          leg(.transit(line: "S7", product: .suburban), 400, 1500),
                          leg(.walk, 1500, 1700, meters: 90)],
                   prep: 300)
    }

    func testTheWatchGetsOriginDestinationAndEveryOption() {
        let snapshot = TripSnapshot(origin: "Zuhause", destination: "Arbeit",
                                    options: [bike(), train()],
                                    recommendedID: nil, countdownID: nil, computedAt: now,
                                    arrivalSearch: false, order: TravelMode.defaultOrder)
        XCTAssertEqual(snapshot.origin, "Zuhause")
        XCTAssertEqual(snapshot.options.count, 2)
        XCTAssertEqual(snapshot.modes, [TravelMode.bike.rawValue, TravelMode.transit.rawValue])
    }

    /// Rad mit „jetzt los" hat nichts, worauf sich zählen ließe; die Bahn schon.
    func testOnlyAFixedDepartureCountsDown() {
        let snapshot = TripSnapshot(origin: "A", destination: "B", options: [bike(), train()],
                                    recommendedID: nil, countdownID: nil, computedAt: now,
                                    arrivalSearch: false, order: TravelMode.defaultOrder)
        let byMode = Dictionary(uniqueKeysWithValues: snapshot.options.map { ($0.mode, $0.countsDown) })
        XCTAssertEqual(byMode[TravelMode.bike.rawValue], false)
        XCTAssertEqual(byMode[TravelMode.transit.rawValue], true)
    }

    /// Bei „um 9 da sein" zählt jede Fahrt — auch das Rad.
    func testAnArrivalSearchMakesEverythingCountDown() {
        let snapshot = TripSnapshot(origin: "A", destination: "B", options: [bike()],
                                    recommendedID: nil, countdownID: nil, computedAt: now,
                                    arrivalSearch: true, order: TravelMode.defaultOrder)
        XCTAssertEqual(snapshot.options.first?.countsDown, true)
    }

    /// Dieselbe Regel wie im `PlanModel` — sie steht seit 1.4 an einer Stelle.
    func testTheRuleIsTheSameOneThePhoneUses() {
        XCTAssertFalse(TripRules.countsDown(bike(), arrivalSearch: false))
        XCTAssertTrue(TripRules.countsDown(bike(), arrivalSearch: true))
        XCTAssertTrue(TripRules.countsDown(train(), arrivalSearch: false))
    }

    /// Kurze Fußwege zwischen zwei Zügen sind der Umstieg, kein Abschnitt.
    func testShortWalksDoNotBecomeLegsOnTheWrist() {
        let snapshot = TripSnapshot(origin: "A", destination: "B", options: [train()],
                                    recommendedID: nil, countdownID: nil, computedAt: now,
                                    arrivalSearch: false, order: TravelMode.defaultOrder)
        XCTAssertEqual(snapshot.options.first?.legs.count, 2, "der 90-m-Weg gehört zum Umstieg")
    }

    /// Die Zeile unter der Zeit ist dieselbe wie im Kasten auf dem Telefon.
    func testTheCaptionSaysWhatKindOfRouteItIs() {
        XCTAssertEqual(TripSnapshot.caption(bike()), BikeVariant.balanced.title)
        XCTAssertEqual(TripSnapshot.caption(train()), L("ab %@", Fmt.time(now.addingTimeInterval(0))))
    }

    /// Und die Sprache reist mit: die Uhr zeigt den Plan des Telefons, also
    /// auch in dessen Sprache.
    func testTheLanguageTravelsWithThePlan() {
        let before = AppLanguage.current
        defer { AppLanguage.current = before }
        AppLanguage.current = .en
        let snapshot = TripSnapshot(origin: "A", destination: "B", options: [bike()],
                                    recommendedID: nil, countdownID: nil, computedAt: now,
                                    arrivalSearch: false, order: TravelMode.defaultOrder)
        XCTAssertEqual(snapshot.language, "en")
    }
}
