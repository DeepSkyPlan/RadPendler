import CloudKit
import XCTest
@testable import RadPendler

/// CloudKit ohne Konto: eine Datenbank im Speicher, die genau das kann, was
/// `TrackCloud` von der echten will. Geprüft wird nicht Apple, sondern was die
/// App mit Apples Antworten macht — und das war bis 1.16 gar nicht geprüft.
final class TrackCloudTests: XCTestCase {
    private final class FakeDatabase: TrackDatabase, @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [CKRecord.ID: Data] = [:]
        private var _failure: Error?
        private var _calls = 0

        var failure: Error? {
            get { lock.withLock { _failure } }
            set { lock.withLock { _failure = newValue } }
        }
        var calls: Int { lock.withLock { _calls } }
        var count: Int { lock.withLock { stored.count } }

        private func begin() throws {
            try lock.withLock {
                _calls += 1
                if let _failure { throw _failure }
            }
        }

        func put(_ record: CKRecord) async throws {
            try begin()
            // Wie der Server: die Datei wird **jetzt** gelesen. `TrackCloud`
            // räumt sie direkt nach dem Aufruf weg.
            guard let asset = record["track"] as? CKAsset, let url = asset.fileURL else {
                throw CKError(.assetFileNotFound)
            }
            let data = try Data(contentsOf: url)
            lock.withLock { stored[record.recordID] = data }
        }

        func get(_ id: CKRecord.ID) async throws -> CKRecord {
            try begin()
            guard let data = lock.withLock({ stored[id] }) else { throw CKError(.unknownItem) }
            let url = URL.temporaryDirectory.appending(path: "fake-\(UUID().uuidString).json")
            try data.write(to: url)
            let record = CKRecord(recordType: TrackCloud.recordType, recordID: id)
            record["track"] = CKAsset(fileURL: url)
            return record
        }

        func remove(_ id: CKRecord.ID) async throws {
            try begin()
            guard lock.withLock({ stored.removeValue(forKey: id) }) != nil else { throw CKError(.unknownItem) }
        }
    }

    private func track(points: Int = 50) -> RideTrack {
        let t0 = Date(timeIntervalSince1970: 1_780_000_000)
        return RideTrack(id: UUID(), points: (0..<points).map {
            RidePoint(lat: 52.5, lon: 13.4 + Double($0) * 1e-5, t: t0.addingTimeInterval(Double($0)), v: 5)
        })
    }

    override func setUp() { Log.clear() }

    func testALineTravelsUpAndComesBackTheSame() async {
        let db = FakeDatabase()
        let cloud = TrackCloud(database: db)
        let line = track()
        await cloud.upload(line)
        let failure = await cloud.lastFailure
        XCTAssertNil(failure)
        XCTAssertEqual(db.count, 1)
        let back = await cloud.download(line.id)
        XCTAssertEqual(back, line)
    }

    /// Dieselbe Fahrt zweimal abzulegen ist kein Konflikt.
    func testUploadingTheSameRideTwiceKeepsOneRecord() async {
        let db = FakeDatabase()
        let cloud = TrackCloud(database: db)
        let line = track()
        await cloud.upload(line)
        await cloud.upload(line)
        XCTAssertEqual(db.count, 1)
    }

    /// Der Normalfall für eine Fahrt, deren Linie nie gereist ist: kein
    /// Fehler, kein Eintrag im Protokoll, und beim nächsten Mal wird wieder
    /// gefragt.
    func testALineThatNeverTravelledIsSimplyNotThere() async {
        let cloud = TrackCloud(database: FakeDatabase())
        let back = await cloud.download(UUID())
        XCTAssertNil(back)
        let off = await cloud.isUnavailable
        XCTAssertFalse(off)
        XCTAssertTrue(Log.recent.isEmpty, "„gibt es nicht“ ist keine Störung")
    }

    /// Keine Apple-ID: einmal gefragt reicht. Die Fahrtenliste sagt, woran es
    /// liegt, und danach geht nichts mehr hinaus.
    func testWithoutAnAccountItAsksOnceAndSaysWhy() async {
        let db = FakeDatabase()
        db.failure = CKError(.notAuthenticated)
        let cloud = TrackCloud(database: db)
        await cloud.upload(track())
        let failure = await cloud.lastFailure
        XCTAssertNotNil(failure)
        let off = await cloud.isUnavailable
        XCTAssertTrue(off)
        XCTAssertEqual(db.calls, 1)
        await cloud.upload(track())
        _ = await cloud.download(UUID())
        await cloud.delete(UUID())
        XCTAssertEqual(db.calls, 1, "dieselbe Absage kostet sonst bei jeder Fahrt Zeit und Strom")
        XCTAssertEqual(Log.recent.map(\.what), ["Linie nach iCloud"])
    }

    /// Ein Funkloch ist kein Grund aufzugeben: die nächste Fahrt versucht es
    /// wieder, und gelingt es, verschwindet der Hinweis.
    func testANetworkFailureIsReportedAndTheNextRideTriesAgain() async {
        let db = FakeDatabase()
        db.failure = CKError(.networkUnavailable)
        let cloud = TrackCloud(database: db)
        await cloud.upload(track())
        var failure = await cloud.lastFailure
        XCTAssertEqual(failure, TrackCloud.reason(CKError(.networkUnavailable)))
        let off = await cloud.isUnavailable
        XCTAssertFalse(off)
        db.failure = nil
        await cloud.upload(track())
        failure = await cloud.lastFailure
        XCTAssertNil(failure)
        XCTAssertEqual(db.count, 1)
    }

    /// So ging der erste Versuch unter: in Production legt CloudKit keinen
    /// Datensatztyp von selbst an, der Server wies ab, niemand sah es.
    func testARejectedRecordTypeIsNamedAsSuch() async {
        let db = FakeDatabase()
        db.failure = CKError(.serverRejectedRequest)
        let cloud = TrackCloud(database: db)
        await cloud.upload(track())
        let failure = await cloud.lastFailure
        XCTAssertEqual(failure, TrackCloud.reason(CKError(.serverRejectedRequest)))
        XCTAssertNotEqual(failure, TrackCloud.reason(CKError(.networkUnavailable)))
    }

    func testEveryKindOfFailureHasASentenceOfItsOwn() {
        let codes: [CKError.Code] = [.notAuthenticated, .quotaExceeded, .networkUnavailable, .serverRejectedRequest]
        let sentences = Set(codes.map { TrackCloud.reason(CKError($0)) })
        XCTAssertEqual(sentences.count, codes.count)
        XCTAssertFalse(TrackCloud.reason(URLError(.timedOut)).isEmpty, "auch für das, was kein CloudKit-Fehler ist")
    }

    func testDeletingWhatIsAlreadyGoneIsQuiet() async {
        let db = FakeDatabase()
        let cloud = TrackCloud(database: db)
        let line = track()
        await cloud.upload(line)
        await cloud.delete(line.id)
        XCTAssertEqual(db.count, 0)
        await cloud.delete(line.id)
        XCTAssertTrue(Log.recent.isEmpty)
        let off = await cloud.isUnavailable
        XCTAssertFalse(off)
    }

    /// Die Ablage, aus der hochgeladen wird, bleibt nicht liegen — sie enthält
    /// den gefahrenen Weg.
    func testNoCopyOfTheLineStaysInTheTemporaryFolder() async {
        let cloud = TrackCloud(database: FakeDatabase())
        let line = track()
        await cloud.upload(line)
        let scratch = URL.temporaryDirectory.appending(path: "upload-\(line.id.uuidString).json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.path))
    }
}
