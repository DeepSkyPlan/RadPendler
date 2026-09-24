import XCTest
@testable import RadPendler

final class CountdownTests: XCTestCase {
    func testWordingBySize() {
        XCTAssertEqual(CountdownBox.text(-5), "jetzt")
        XCTAssertEqual(CountdownBox.text(0), "0:00")
        XCTAssertEqual(CountdownBox.text(95), "1:35")
        XCTAssertEqual(CountdownBox.text(599), "9:59")
        XCTAssertEqual(CountdownBox.text(600), "10 min")
        XCTAssertEqual(CountdownBox.text(3600 + 300), "1:05 h")
    }

    func testClockPresetRollsOverToTomorrow() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let morning = c.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 7, minute: 30))!
        XCTAssertEqual(DeparturePreset.clock(9, 0).date(from: morning, calendar: c),
                       c.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 9)))
        // 8 o'clock has passed at 09:30, so it means tomorrow.
        let late = c.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 9, minute: 30))!
        XCTAssertEqual(DeparturePreset.clock(8, 0).date(from: late, calendar: c),
                       c.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 8)))
        XCTAssertEqual(DeparturePreset.relative(15).date(from: late), late.addingTimeInterval(900))
    }

    func testPresetTitlesAndStorage() {
        XCTAssertEqual(DeparturePreset.relative(15).title, "in 15 min")
        XCTAssertEqual(DeparturePreset.relative(60).title, "in 1 h")
        XCTAssertEqual(DeparturePreset.clock(8, 0).title, "um 8 Uhr")
        XCTAssertEqual(DeparturePreset.clock(18, 30).title, "um 18:30")
        for p in DeparturePreset.choices {
            XCTAssertEqual(DeparturePreset(stored: p.stored), p)
        }
    }

    func testAgeOfThePlanOnTheMap() {
        XCTAssertEqual(Fmt.age(0), "gerade eben")
        XCTAssertEqual(Fmt.age(59), "gerade eben")
        XCTAssertEqual(Fmt.age(60), "vor 1 min")
        XCTAssertEqual(Fmt.age(59 * 60), "vor 59 min")
        XCTAssertEqual(Fmt.age(3600), "vor 1 h")
        XCTAssertEqual(Fmt.age(3600 + 7 * 60), "vor 1:07 h")
        XCTAssertEqual(Fmt.age(-5), "gerade eben", "a clock that jumped back is not a future plan")
    }

    func testCountdownColourStepsFollowTheAlertMinutes() {
        let step = { (minutes: Double) in Countdown.urgency(minutes * 60) }
        XCTAssertEqual(step(45), .plenty)
        XCTAssertEqual(step(31), .plenty)
        XCTAssertEqual(step(30), .soon, "half an hour is already the amber half")
        XCTAssertEqual(step(11), .soon)
        XCTAssertEqual(step(10), .wrapUp, "the first warning turns it orange")
        XCTAssertEqual(step(6), .wrapUp)
        XCTAssertEqual(step(5), .go, "the last warning turns it red")
        XCTAssertEqual(step(-3), .go, "overdue stays red until the trip is gone")
        XCTAssertEqual(Countdown.urgency(nil), .idle)
        XCTAssertEqual(Countdown.urgency(600, gone: true), .gone)
    }

    // MARK: Was die geweckte App nachstellt

    private func trip(_ mode: TravelMode, _ kind: LegKind, leave: Date) -> TripOption {
        TripOption(mode: mode, legs: [Leg(kind: kind, fromName: "a", toName: "b", departure: leave,
                                          arrival: leave.addingTimeInterval(900))], prep: 300)
    }

    /// Die im Hintergrund geweckte App muss dieselbe Frage stellen wie der
    /// Bildschirm: dieselbe Kategorie, die beste Möglichkeit darin, die
    /// Alternative zuletzt. Sucht sie sich selbst eine Verbindung, warnt sie
    /// zuverlässig vor dem falschen Zug.
    func testTheWokenAppPicksTheSameTripTheScreenShowed() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        // Rad + Bahn über die Tram ist die Alternative, die über die S-Bahn nicht.
        let viaTram = trip(.bikeTransit, .transit(line: "M10", product: .tram), leave: now.addingTimeInterval(300))
        let viaSBahn = trip(.bikeTransit, .transit(line: "S7", product: .suburban), leave: now.addingTimeInterval(600))
        XCTAssertTrue(viaTram.isAlternative)
        XCTAssertFalse(viaSBahn.isAlternative)
        let byBike = trip(.bike, .bike, leave: now)

        let q = BackgroundReplan.Question(mode: TravelMode.bikeTransit.rawValue, date: nil, isArrival: false)
        XCTAssertEqual(BackgroundReplan.option(for: q, in: [viaTram, byBike, viaSBahn])?.id, viaSBahn.id,
                       "die Alternative kommt zuletzt, auch wenn sie früher fährt")
        XCTAssertNil(BackgroundReplan.option(for: q, in: [byBike]), "keine Verbindung dieser Kategorie")

        let byBikeNow = BackgroundReplan.Question(mode: TravelMode.bike.rawValue, date: nil, isArrival: false)
        XCTAssertNil(BackgroundReplan.option(for: byBikeNow, in: [byBike]),
                     "Rad mit „jetzt los“ hat keine feste Abfahrt — da ist nichts nachzustellen")
        let byBikeThere = BackgroundReplan.Question(mode: TravelMode.bike.rawValue, date: now, isArrival: true)
        XCTAssertEqual(BackgroundReplan.option(for: byBikeThere, in: [byBike])?.id, byBike.id,
                       "mit gewünschter Ankunft dagegen schon")
    }

    /// Die Frage überlebt das Schließen der App — sie liegt in den UserDefaults,
    /// und nil löscht sie wieder.
    func testTheRememberedQuestionSurvivesAndClears() {
        let before = BackgroundReplan.remembered
        defer { BackgroundReplan.remember(before) }
        let q = BackgroundReplan.Question(mode: TravelMode.transit.rawValue,
                                          date: Date(timeIntervalSince1970: 1_800_000_000), isArrival: true)
        BackgroundReplan.remember(q)
        XCTAssertEqual(BackgroundReplan.remembered, q)
        BackgroundReplan.remember(nil)
        XCTAssertNil(BackgroundReplan.remembered)
    }
}
