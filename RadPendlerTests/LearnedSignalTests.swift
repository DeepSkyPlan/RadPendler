import CoreLocation
import XCTest
@testable import RadPendler

/// Was eine Ampel kostet, ist die zweite Hälfte jeder Radzeit — die erste ist
/// Strecke ÷ Tempo. Solange jede Kreuzung pauschal zählte, wuchs die geplante
/// Fahrzeit mit jeder aufgezeichneten Fahrt, weil jede Fahrt neue Ampeln lernte
/// und keine je billiger wurde.
final class LearnedSignalTests: XCTestCase {
    private let base = CLLocationCoordinate2D(latitude: 52.5, longitude: 13.4)
    private let noon = Date(timeIntervalSince1970: 1_780_000_000)

    /// Metres east of `base`.
    private func east(_ meters: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: base.latitude,
                               longitude: base.longitude + meters / (111_320 * cos(base.latitude * .pi / 180)))
    }

    // MARK: Was eine gemessene Kreuzung kostet

    func testTheAverageIsTakenOverThePassesNotOverTheStops() {
        // Zehn Vorbeifahrten, fünfmal rot, zusammen 100 Sekunden.
        let light = LearnedSignal(lat: base.latitude, lon: base.longitude, stops: 5,
                                  totalWait: 100, lastSeen: noon, passes: 10)
        XCTAssertEqual(light.averageWait, 20, accuracy: 0.01, "wenn man steht, steht man 20 s")
        // … aber die Kreuzung kostet nur die Hälfte davon, plus den Anteil,
        // den der Prior noch hält: (100 + 3 × 20) / (10 + 3).
        XCTAssertEqual(light.expectedWait(default: 20), 160.0 / 13, accuracy: 0.01)
        XCTAssertLessThan(light.expectedWait(default: 20), 20, "gemessen billiger als der Pauschalwert")
    }

    func testTheFirstObservationDoesNotDecideEverything() {
        // Einmal neunzig Sekunden an einer Schranke: ohne Prior kostete diese
        // Stelle von da an neunzig Sekunden je Fahrt.
        let once = LearnedSignal.recording([], at: base, waited: 90, now: noon)[0]
        XCTAssertEqual(once.expectedWait(default: 20), (90 + 60) / 4, accuracy: 0.01)
        XCTAssertLessThan(once.expectedWait(default: 20), 90)
    }

    func testEveryGreenPassMakesTheJunctionCheaper() {
        var list = LearnedSignal.recording([], at: base, waited: 60, now: noon)
        let first = list[0].expectedWait(default: 20)
        for _ in 0..<9 { list = LearnedSignal.passing(list, at: east(10), now: noon) }
        XCTAssertEqual(list.count, 1, "zehn Meter weiter ist dieselbe Kreuzung")
        XCTAssertEqual(list[0].stops, 1)
        XCTAssertEqual(list[0].passCount, 10)
        XCTAssertLessThan(list[0].expectedWait(default: 20), first)
        XCTAssertEqual(list[0].expectedWait(default: 20), (60 + 60) / 13.0, accuracy: 0.01)
    }

    func testAPassDoesNotMoveTheJunction() {
        var list = LearnedSignal.recording([], at: base, waited: 30, now: noon)
        list = LearnedSignal.passing(list, at: east(40), now: noon)
        XCTAssertEqual(list[0].coordinate.longitude, base.longitude, accuracy: 1e-9,
                       "eine Durchfahrt weiß nicht besser, wo die Ampel steht")
    }

    /// Die Fassung vor den Vorbeifahrten hat nur Halte gezählt. Für die zählt
    /// jede Vorbeifahrt als Halt — genau das, was die App damals annahm.
    func testEntriesFromBeforeThePassesKeepTheirOldAverage() throws {
        let json = Data(#"{"lat":52.5,"lon":13.4,"stops":4,"totalWait":80,"lastSeen":760000000}"#.utf8)
        let old = try JSONDecoder().decode(LearnedSignal.self, from: json)
        XCTAssertNil(old.passes)
        XCTAssertEqual(old.passCount, 4, "nie weniger Vorbeifahrten als Halte")
        XCTAssertEqual(old.expectedWait(default: 20), (80 + 60) / 7.0, accuracy: 0.01)
    }

    func testMergingTwoDevicesAddsTheirPasses() {
        let mine = LearnedSignal(lat: base.latitude, lon: base.longitude, stops: 2,
                                 totalWait: 40, lastSeen: noon, passes: 8)
        let theirs = LearnedSignal(lat: east(20).latitude, lon: east(20).longitude, stops: 3,
                                   totalWait: 60, lastSeen: noon, passes: 12)
        let merged = LearnedSignal.merging([mine], [theirs])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].stops, 5)
        XCTAssertEqual(merged[0].passCount, 20)
        XCTAssertEqual(merged[0].totalWait, 100)
    }

    // MARK: Was eine Route an Ampelzeit kostet

    func testMeasuredJunctionsPayTheirOwnWayAndTheRestThePlannedAverage() {
        let s = PlanSettings()      // 20 s je Ampel
        let cheap = LearnedSignal(lat: base.latitude, lon: base.longitude, stops: 1,
                                  totalWait: 20, lastSeen: noon, passes: 17)
        // Zwanzig Kreuzungen, eine davon gemessen: die kostet 4 s statt 20.
        XCTAssertEqual(cheap.expectedWait(default: 20), 80.0 / 20, accuracy: 0.01)
        XCTAssertEqual(s.signalWait(signals: 20, learned: [cheap]), 19 * 20 + 4, accuracy: 0.01)
        XCTAssertEqual(s.signalWait(signals: 20), 400, "ohne Gemessenes wie bisher")
    }

    func testAJourneyThroughOnlyKnownJunctionsIsWhatWasMeasured() {
        var s = PlanSettings()
        s.signalWaitSeconds = 20
        // Eine Strecke, auf der jede Ampel zwanzigmal gesehen wurde und im
        // Mittel fünf Sekunden gekostet hat.
        let known = (0..<10).map { i in
            LearnedSignal(lat: base.latitude, lon: base.longitude + Double(i), stops: 4,
                          totalWait: 100, lastSeen: noon, passes: 20)
        }
        let flat = TimeInterval(s.signalWaitSeconds)
        XCTAssertEqual(s.signalWait(signals: 10, learned: known),
                       10 * (100 + 3 * flat) / 23, accuracy: 0.01)
        XCTAssertLessThan(s.signalWait(signals: 10, learned: known), 10 * flat / 2 + 60)
    }

    // MARK: Was eine Fahrt lernt

    func testARideLearnsBothItsWaitsAndItsGreenLights() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let light = east(500)
        // Die Linie führt an der Ampel vorbei.
        let track = stride(from: 0.0, through: 1000, by: 25).map {
            RidePoint(lat: east($0).latitude, lon: east($0).longitude, t: noon, v: 5)
        }
        // Erste Fahrt: rot, 40 s.
        settings.learn(stops: [RideStop(lat: east(490).latitude, lon: east(490).longitude,
                                        start: noon, seconds: 40, atSignal: true)],
                       track: track, junctions: [light])
        XCTAssertEqual(settings.learnedSignals.count, 1, "der Halt und die Kreuzung sind dieselbe Stelle")
        XCTAssertEqual(settings.learnedSignals[0].stops, 1)
        XCTAssertEqual(settings.learnedSignals[0].passCount, 1)
        // Zweite und dritte Fahrt: grün.
        settings.learn(stops: [], track: track, junctions: [light])
        settings.learn(stops: [], track: track, junctions: [light])
        XCTAssertEqual(settings.learnedSignals.count, 1)
        XCTAssertEqual(settings.learnedSignals[0].stops, 1)
        XCTAssertEqual(settings.learnedSignals[0].passCount, 3)
        XCTAssertEqual(settings.learnedSignals[0].expectedWait(default: 20), (40 + 60) / 6.0, accuracy: 0.01)
    }

    /// Die Kreuzungsliste einer Fahrt kommt aus zwei Quellen — den Ampeln der
    /// geplanten Route und den schon gelernten. Dieselbe Kreuzung steht
    /// deshalb oft zweimal darin.
    func testTheSameJunctionTwiceInTheListIsStillOnePass() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let light = east(500)
        let track = stride(from: 0.0, through: 1000, by: 25).map {
            RidePoint(lat: east($0).latitude, lon: east($0).longitude, t: noon, v: 5)
        }
        settings.learn(stops: [], track: track, junctions: [light, east(520)])
        XCTAssertEqual(settings.learnedSignals.count, 1)
        XCTAssertEqual(settings.learnedSignals[0].passCount, 1)
    }

    func testAJunctionTheRideNeverCameNearIsNotLearned() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let track = [RidePoint(lat: base.latitude, lon: base.longitude, t: noon, v: 5)]
        settings.learn(stops: [], track: track, junctions: [east(5000)])
        XCTAssertTrue(settings.learnedSignals.isEmpty)
    }
}
