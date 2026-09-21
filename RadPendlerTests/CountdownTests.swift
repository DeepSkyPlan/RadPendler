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
        XCTAssertEqual(LastRunPill.ago(0), "gerade eben")
        XCTAssertEqual(LastRunPill.ago(59), "gerade eben")
        XCTAssertEqual(LastRunPill.ago(60), "vor 1 min")
        XCTAssertEqual(LastRunPill.ago(59 * 60), "vor 59 min")
        XCTAssertEqual(LastRunPill.ago(3600), "vor 1 h")
        XCTAssertEqual(LastRunPill.ago(3600 + 7 * 60), "vor 1:07 h")
        XCTAssertEqual(LastRunPill.ago(-5), "gerade eben", "a clock that jumped back is not a future plan")
    }
}
