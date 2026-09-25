import UserNotifications
import XCTest
@testable import RadPendler

/// The warnings that have to reach the phone while the app is closed: the right
/// number of them, at the right moments, saying the right thing.
final class AlarmTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    /// Leaves in 20 minutes, 5 minutes of getting ready: the moment to get
    /// going is 15 minutes away.
    private func trip() -> TripOption {
        TripOption(mode: .bikeTransit,
                   legs: [Leg(kind: .bike, fromName: "Beispielweg", toName: "S Beispielstadt",
                              departure: now.addingTimeInterval(1200),
                              arrival: now.addingTimeInterval(1800)),
                          Leg(kind: .transit(line: "S7", product: .suburban),
                              fromName: "S Beispielstadt", toName: "S Hauptbahnhof",
                              departure: now.addingTimeInterval(1900),
                              arrival: now.addingTimeInterval(3000))],
                   prep: 300)
    }

    func testOnePerArmedMinutePlusTheMomentItself() {
        let requests = Alarm.requests(for: trip(), alerts: [10, 5, 1], now: now)
        XCTAssertEqual(requests.map(\.identifier),
                       ["radpendler.alarm.10", "radpendler.alarm.5", "radpendler.alarm.1", "radpendler.alarm.0"])
        let delays = requests.compactMap { ($0.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval }
        // Getting ready is 900 s away, so the warnings land 300, 600, 840 and 900 s from now.
        XCTAssertEqual(delays, [300, 600, 840, 900])
        // Gegen `L(…)`, nicht gegen den deutschen Wortlaut: steht die App auf
        // Englisch, ist „Leave in 10 min" genauso richtig.
        XCTAssertEqual(requests.first?.content.title, L("In %d min los", 10))
        XCTAssertEqual(requests.last?.content.title, L("Jetzt los"))
    }

    func testMinutesAlreadyGoneAreSkipped() {
        // Only 6 minutes left before getting ready: the 10-minute warning is past.
        let late = now.addingTimeInterval(540)
        let requests = Alarm.requests(for: trip(), alerts: [10, 5, 1], now: late)
        XCTAssertEqual(requests.map(\.identifier),
                       ["radpendler.alarm.5", "radpendler.alarm.1", "radpendler.alarm.0"])
    }

    func testNothingLeftOnceTheTripHasLeft() {
        XCTAssertTrue(Alarm.requests(for: trip(), alerts: [10, 5, 1], now: now.addingTimeInterval(4000)).isEmpty)
    }

    func testBodyNamesModeTimesAndTheTrain() {
        XCTAssertEqual(Alarm.body(trip()),
                       "\(TravelMode.bikeTransit.title) \(Fmt.time(now.addingTimeInterval(1200))) → \(Fmt.time(now.addingTimeInterval(3000)))"
                       + " · S7 ab S Beispielstadt \(Fmt.time(now.addingTimeInterval(1900)))")
    }

    func testBodyWithoutATrainStaysShort() {
        let bike = TripOption(mode: .bike,
                              legs: [Leg(kind: .bike, fromName: "a", toName: "b",
                                         departure: now, arrival: now.addingTimeInterval(3540))],
                              prep: 300)
        XCTAssertEqual(Alarm.body(bike),
                       "\(TravelMode.bike.title) \(Fmt.time(now)) → \(Fmt.time(now.addingTimeInterval(3540)))")
    }
}
