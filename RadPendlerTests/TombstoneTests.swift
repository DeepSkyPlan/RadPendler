import XCTest
@testable import RadPendler

/// Dass Löschen mit zwei Geräten wirklich löscht.
///
/// Der Fall, der es vorher nicht tat: Gerät A löscht eine Fahrt und schiebt
/// die gekürzte Liste in die Wolke, Gerät B kennt sie noch, vereinigt — und
/// schreibt sie zurück. Beim nächsten Abgleich hatte A sie wieder. Dasselbe
/// für benutzte Adressen und gelernte Ampeln, alle drei werden vereinigt statt
/// ersetzt, und das aus gutem Grund (siehe `Tombstones`).
final class TombstoneTests: XCTestCase {
    private let noon = Date(timeIntervalSince1970: 1_780_000_000)

    private func ride(_ id: UUID, _ dayOffset: Int) -> Ride {
        Ride(id: id, started: noon.addingTimeInterval(Double(dayOffset) * 86_400),
             ended: noon.addingTimeInterval(Double(dayOffset) * 86_400 + 1800),
             origin: "A", destination: "B", mode: TravelMode.bike.rawValue,
             meters: 10_000, movingSeconds: 1700, maxKmh: 30,
             signalStops: 3, otherStops: 1, signalWaitTotal: 90)
    }

    /// Ohne Grabstein kommt die gelöschte Fahrt vom zweiten Gerät zurück —
    /// das ist der alte Zustand, festgehalten, damit er nicht zurückkehrt.
    func testWithoutATombstoneTheMergeBringsItBack() {
        let gone = UUID()
        let mine = [ride(UUID(), 0)]
        let theirs = [ride(UUID(), 0), ride(gone, -1)]
        XCTAssertTrue(RideStore.merge(mine, theirs).contains { $0.id == gone })
    }

    func testATombstoneKeepsTheDeletedRideOut() throws {
        let gone = UUID()
        let kept = UUID()
        let mine = [ride(kept, 0)]
        let theirs = [ride(kept, 0), ride(gone, -1)]

        var graves = Tombstones()
        graves.add(Tombstones.key(ride: gone))
        let merged = try XCTUnwrap(CloudStore.merged(CloudStore.ridesKey,
                                                     local: XCTUnwrap(RideStore.encode(mine)),
                                                     cloud: XCTUnwrap(RideStore.encode(theirs)),
                                                     graves: graves))
        let list = try XCTUnwrap(RideStore.decode(merged))
        XCTAssertEqual(list.map { $0.id }, [kept], "die gelöschte Fahrt darf nicht zurückkommen")
    }

    /// Wer eine Adresse löscht und sie danach wieder benutzt, hat sie wieder.
    func testUsingSomethingAgainOutlivesItsTombstone() {
        var graves = Tombstones()
        graves.add("place:Beispielweg", at: noon)
        XCTAssertTrue(graves.buried("place:Beispielweg", newerThan: noon.addingTimeInterval(-60)))
        XCTAssertFalse(graves.buried("place:Beispielweg", newerThan: noon.addingTimeInterval(60)),
                       "danach wieder benutzt heißt: wieder da")
    }

    /// Beide Seiten vereinigt, und Altes fällt heraus — sonst wüchse die Liste
    /// ewig und teilte sich den einen Megabyte-Speicher mit allem anderen.
    func testTombstonesMergeAndAgeOut() {
        var mine = Tombstones()
        mine.add("ride:a", at: noon)
        var theirs = Tombstones()
        theirs.add("ride:b", at: noon.addingTimeInterval(-Tombstones.lifetime - 60))
        let merged = mine.merging(theirs, now: noon)
        XCTAssertTrue(merged.has("ride:a"))
        XCTAssertFalse(merged.has("ride:b"), "älter als die Aufbewahrungszeit")
    }

    /// Das Löschen einer Fahrt hinterlässt seinen Grabstein in den
    /// UserDefaults — dort holt ihn der Abgleich ab.
    @MainActor func testDeletingARideBuriesIt() throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let folder = URL.temporaryDirectory.appending(path: suite)
        let store = RideStore(folder: folder, defaults: defaults)
        let one = ride(UUID(), 0)
        store.add(one, track: RideTrack(id: one.id))
        store.delete(one)
        XCTAssertTrue(Tombstones.load(defaults).has(Tombstones.key(ride: one.id)))
        XCTAssertTrue(store.rides.isEmpty)
    }

    /// Und das Vergessen der gelernten Ampeln ebenso — alle auf einmal.
    @MainActor func testForgettingLearnedSignalsBuriesThem() throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let signal = LearnedSignal(lat: 52.5, lon: 13.4, stops: 4, totalWait: 120, lastSeen: noon)
        settings.learnedSignals = [signal]
        settings.forgetLearnedSignals()
        XCTAssertTrue(settings.learnedSignals.isEmpty)
        XCTAssertTrue(settings.tombstones.has(Tombstones.key(signal: signal.id)))
    }
}
