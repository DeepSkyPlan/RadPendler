import CoreLocation
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
