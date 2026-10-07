import XCTest
@testable import RadPendler

/// `try?` mit Gedächtnis — und was dabei nicht ins Gedächtnis darf.
final class LogTests: XCTestCase {
    private struct Boom: Error {}

    override func setUp() { Log.clear() }

    func testAFailureIsRememberedAndTheCallerGetsNil() {
        let value: Int? = Log.attempt("probe") { throw Boom() }
        XCTAssertNil(value)
        XCTAssertEqual(Log.recent.map(\.what), ["probe"])
        XCTAssertEqual(Log.attempt("probe") { 7 }, 7)
        XCTAssertEqual(Log.recent.count, 1, "was gelingt, hinterlässt nichts")
    }

    /// Die Liste geht mit „Fahrt teilen" aus dem Haus. Der Text eines Fehlers
    /// kann Pfade und Adressen enthalten; hinein dürfen nur Art und Nummer.
    func testOnlyKindAndNumberAreKeptNeverTheText() {
        let secret = "/var/mobile/Musterstraße 1/track.json"
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError,
                            userInfo: [NSLocalizedDescriptionKey: secret, NSFilePathErrorKey: secret])
        Log.note("Linie schreiben", error)
        let entry = Log.recent[0]
        XCTAssertEqual(entry.error, "NSCocoaErrorDomain \(NSFileWriteNoPermissionError)")
        let json = String(decoding: try! JSONEncoder().encode(Log.recent), as: UTF8.self)
        XCTAssertFalse(json.contains("Musterstraße"))
    }

    func testAMissingFileIsOnlyQuietWhereItMayBeMissing() {
        let nowhere = URL.temporaryDirectory.appending(path: "gibt-es-nicht-\(UUID().uuidString)")
        XCTAssertNil(Log.attempt("lesen", missingIsFine: true) { try Data(contentsOf: nowhere) })
        XCTAssertTrue(Log.recent.isEmpty)
        XCTAssertNil(Log.attempt("lesen") { try Data(contentsOf: nowhere) })
        XCTAssertEqual(Log.recent.count, 1)
        // Und nur das Fehlen ist still — alles andere bleibt ein Fehler.
        XCTAssertNil(Log.attempt("auspacken", missingIsFine: true) {
            try JSONDecoder().decode([Int].self, from: Data("kein JSON".utf8))
        })
        XCTAssertEqual(Log.recent.count, 2)
    }

    /// Wer auf das Adressfeld tippt, bricht die Planung ab. Das ist kein Fehler.
    func testACancelledPlanIsNotAFailure() async {
        await Log.attemptAsync("planen") { throw CancellationError() }
        await Log.attemptAsync("planen") { throw URLError(.cancelled) }
        XCTAssertTrue(Log.recent.isEmpty)
        await Log.attemptAsync("planen") { throw URLError(.timedOut) }
        XCTAssertEqual(Log.recent.count, 1)
    }

    func testALoopOfFailuresCannotGrowWithoutBound() {
        for i in 0..<(Log.limit * 3) { Log.note("schleife \(i)", Boom()) }
        XCTAssertEqual(Log.recent.count, Log.limit)
        XCTAssertEqual(Log.recent.last?.what, "schleife \(Log.limit * 3 - 1)", "die jüngsten bleiben")
    }

    /// Der Fall, der den Anlass gab: eine Linie, die sich nicht schreiben
    /// lässt, war bis 1.16 spurlos.
    @MainActor func testALineThatCannotBeWrittenLeavesATrace() {
        // Eine Datei dort, wo der Ordner hingehört: nichts darunter lässt sich anlegen.
        let blocker = URL.temporaryDirectory.appending(path: "LogTests-\(UUID().uuidString)")
        try! Data().write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let store = RideStore(folder: blocker, defaults: UserDefaults(suiteName: "log-\(UUID().uuidString)")!)
        let ride = Ride(started: .now.addingTimeInterval(-600), ended: .now, origin: "A", destination: "B",
                        mode: TravelMode.bike.rawValue, meters: 3_000, movingSeconds: 600, maxKmh: 25,
                        signalStops: 0, otherStops: 0, signalWaitTotal: 0)
        Log.clear()
        store.add(ride, track: RideTrack(id: ride.id))
        XCTAssertTrue(Log.recent.contains { $0.what == "Linie schreiben" })
        XCTAssertEqual(store.rides.count, 1, "die Zahlen bleiben trotzdem")
    }
}
