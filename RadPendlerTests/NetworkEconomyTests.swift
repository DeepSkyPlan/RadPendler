import CoreLocation
import XCTest
@testable import RadPendler

/// Antwortet, was der Test vorgibt, und zählt mit.
final class StubProtocol: URLProtocol {
    struct Reply { var status = 200; var body = Data(); var delay: TimeInterval = 0 }

    private static let lock = NSLock()
    private static var replies: [Reply] = []
    private static var seen: [Data] = []

    /// Die Antworten der Reihe nach; die letzte gilt für alles Weitere.
    static func session(_ replies: [Reply]) -> URLSession {
        lock.lock(); self.replies = replies; seen = []; lock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
    }

    /// Die Rümpfe der Anfragen, in der Reihenfolge ihres Eingangs.
    static var bodies: [Data] { lock.lock(); defer { lock.unlock() }; return seen }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 16_384)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                body.append(buffer, count: n)
            }
            stream.close()
        }
        Self.lock.lock()
        Self.seen.append(body)
        let reply = Self.replies.count > 1 ? Self.replies.removeFirst() : (Self.replies.first ?? Reply())
        Self.lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay) { [weak self] in
            guard let self, let url = self.request.url,
                  let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: nil, headerFields: nil)
            else { return }
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: reply.body)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

/// Wie sparsam die Planung fragt. Gemessen am 09.10.2026 auf der eigenen
/// Strecke: die Radrouten standen nach 3,6 s, dann wartete der Plan neun
/// Sekunden auf ein `504` von Overpass — und beim nächsten Mal wieder sieben.
final class NetworkEconomyTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        folder = URL.temporaryDirectory.appending(path: "NetworkEconomyTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Eine Linie nach Norden, `east` Grad daneben.
    private func line(east: Double = 0) -> [CLLocationCoordinate2D] {
        (0...200).map { CLLocationCoordinate2D(latitude: 52.42 + Double($0) * 0.0005, longitude: 13.18 + east) }
    }

    private func overpass(signals: [(Double, Double)]) -> Data {
        let nodes = signals.enumerated().map { i, s in
            ["type": "node", "id": i + 1, "lat": s.0, "lon": s.1] as [String: Any]
        }
        return try! JSONSerialization.data(withJSONObject: ["elements": nodes])
    }

    // MARK: Straßendaten

    /// Eine neue Linie neben der alten: gefragt wird nur nach dem, was fehlt,
    /// und die Antwort kommt zu dem, was schon da ist. Bis 1.17 wurde der
    /// ganze Schlauch neu geholt, sobald eine Linie nicht ganz darin lag.
    func testTheCorridorGrowsInsteadOfBeingFetchedAgain() async throws {
        let first = overpass(signals: [(52.43, 13.18)])
        // Die zweite Antwort bringt eine neue Ampel — und die alte noch einmal.
        let second = overpass(signals: [(52.43, 13.21), (52.43, 13.18)])
        let session = StubProtocol.session([.init(body: first), .init(body: second)])
        var store = RoadDataStore(session: session, folder: folder)

        let alone = try await store.data(covering: line(), patience: nil)
        XCTAssertEqual(alone.signals.count, 1)
        XCTAssertEqual(StubProtocol.bodies.count, 1)

        // Ein neuer Start der App: dieselbe Linie kommt von der Platte.
        store = RoadDataStore(session: session, folder: folder)
        _ = try await store.data(covering: line(), patience: nil)
        XCTAssertEqual(StubProtocol.bodies.count, 1, "dieselbe Frage geht kein zweites Mal hinaus")

        // Eine zweite Linie, zwei Kilometer daneben, zusammen mit der ersten.
        let both = try await store.data(covering: line() + line(east: 0.03), patience: nil)
        XCTAssertEqual(StubProtocol.bodies.count, 2)
        XCTAssertEqual(both.signals.count, 2, "beide Antworten in einer, die doppelte Ampel nur einmal")
        XCTAssertLessThan(Double(StubProtocol.bodies[1].count), Double(StubProtocol.bodies[0].count) * 1.3,
                          "gefragt wird nach der neuen Linie, nicht nach beiden")

        // Und danach ist beides da — auch nach einem weiteren Neustart.
        store = RoadDataStore(session: session, folder: folder)
        _ = try await store.data(covering: line(east: 0.03), patience: nil)
        _ = try await store.data(covering: line() + line(east: 0.03), patience: nil)
        XCTAssertEqual(StubProtocol.bodies.count, 2)
    }

    /// Die Planung wartet nicht auf Overpass. Die Abfrage läuft weiter, und
    /// wer danach fragt, bekommt ihre Antwort — ohne eine zweite Abfrage.
    func testAPlanDoesNotWaitForSlowRoadData() async throws {
        let session = StubProtocol.session([.init(body: overpass(signals: [(52.43, 13.18)]), delay: 1.0)])
        let store = RoadDataStore(session: session, folder: folder)
        let began = Date()
        do {
            _ = try await store.data(covering: line(), patience: 0.2)
            XCTFail("so schnell kann die Antwort nicht da sein")
        } catch RoadData.OverpassError.stillFetching {
            XCTAssertLessThan(Date().timeIntervalSince(began), 0.8)
        }
        // Der nächste Plan, noch während die Abfrage läuft: er hängt sich an.
        let later = try await store.data(covering: line(), patience: nil)
        XCTAssertEqual(later.signals.count, 1)
        XCTAssertEqual(StubProtocol.bodies.count, 1, "eine Abfrage für beide")
    }

    /// Ein `504` ist bei Overpass Alltag. Die Abfrage versucht es einmal mit
    /// mehr Geduld — und nicht jede Planung von vorn.
    func testAFailedQueryIsRetriedOnce() async throws {
        let session = StubProtocol.session([.init(status: 504), .init(body: overpass(signals: [(52.43, 13.18)]))])
        let store = RoadDataStore(session: session, folder: folder)
        Log.clear()
        let data = try await store.data(covering: line(), patience: nil)
        XCTAssertEqual(data.signals.count, 1)
        XCTAssertEqual(StubProtocol.bodies.count, 2)
        XCTAssertTrue(Log.recent.contains { $0.what == "Straßendaten holen" }, "der Fehlschlag steht im Protokoll")
    }

    /// Lehnt Overpass auch den zweiten Versuch ab, ist für ein paar Minuten
    /// Ruhe: die nächste Planung fragt nicht wieder und wartet auf nichts.
    func testAfterTwoRefusalsThePlanStopsAsking() async {
        let session = StubProtocol.session([.init(status: 504)])
        let store = RoadDataStore(session: session, folder: folder)
        _ = try? await store.data(covering: line(), patience: nil)
        XCTAssertEqual(StubProtocol.bodies.count, 2, "einmal, und einmal mit Geduld")
        let began = Date()
        do {
            _ = try await store.data(covering: line(), patience: 4)
            XCTFail("ohne Daten gibt es nichts zurückzugeben")
        } catch RoadData.OverpassError.unavailable {
            XCTAssertLessThan(Date().timeIntervalSince(began), 0.5, "sofort, ohne zu warten")
        } catch {
            XCTFail("\(error)")
        }
        XCTAssertEqual(StubProtocol.bodies.count, 2)
    }

    /// Rad, Auto und Zubringer fragen gleichzeitig nach drei Schläuchen. Es
    /// geht eine Abfrage zur Zeit hinaus, und die späteren fragen nur noch
    /// nach dem, was die erste nicht gebracht hat.
    func testOverpassIsAskedOneQuestionAtATime() async throws {
        let session = StubProtocol.session([.init(body: overpass(signals: [(52.43, 13.18)]), delay: 0.3),
                                            .init(body: overpass(signals: [(52.43, 13.21)]), delay: 0.3)])
        let store = RoadDataStore(session: session, folder: folder)
        async let bike = store.data(covering: line(), patience: nil)
        async let car = store.data(covering: line() + line(east: 0.03), patience: nil)
        async let again = store.data(covering: line(), patience: nil)
        let (a, b, c) = try await (bike, car, again)
        XCTAssertEqual(StubProtocol.bodies.count, 2, "die Linie, die zweimal gefragt war, einmal — und einmal das Stück daneben")
        XCTAssertEqual([a.signals.count, c.signals.count].min(), 1)
        XCTAssertEqual(b.signals.count, 2)
    }

    // MARK: BRouter

    /// Drei Zubringer fragen im selben Augenblick nach demselben Profil. Es
    /// wird einmal hochgeladen, nicht dreimal.
    func testAProfileIsUploadedOnceHoweverManyAsk() async throws {
        let reply = try JSONSerialization.data(withJSONObject: ["profileid": "custom_123"])
        let session = StubProtocol.session([.init(body: reply, delay: 0.2)])
        let profiles = CustomProfile()
        let kind = CustomProfile.Kind(profile: .safety, withoutCobbles: true)
        async let a = profiles.id(kind, session: session)
        async let b = profiles.id(kind, session: session)
        async let c = profiles.id(kind, session: session)
        let ids = try await [a, b, c]
        XCTAssertEqual(ids, ["custom_123", "custom_123", "custom_123"])
        XCTAssertEqual(StubProtocol.bodies.count, 1)
        // Und danach gar nicht mehr, solange es gilt.
        _ = try await profiles.id(kind, session: session)
        XCTAssertEqual(StubProtocol.bodies.count, 1)
    }

    /// Ändert eine neue Fassung einen Faktor, ist es ein anderes Profil — das
    /// alte, gemerkte darf dann nicht mehr gelten.
    func testAChangedProfileIsADifferentOne() {
        let a = CustomProfile.fingerprint("assign costfactor 1")
        XCTAssertEqual(a, CustomProfile.fingerprint("assign costfactor 1"))
        XCTAssertNotEqual(a, CustomProfile.fingerprint("assign costfactor 2"))
    }

    /// Die Antwort von gestern liegt auf der Platte und gilt einen Tag.
    func testARouteFromDiskIsUsedForADay() {
        let key = "test-\(UUID().uuidString)"
        XCTAssertNil(RouteDisk.read(key))
        RouteDisk.write(Data("antwort".utf8), for: key)
        XCTAssertEqual(RouteDisk.read(key), Data("antwort".utf8))
        XCTAssertEqual(RouteDisk.lifetime, 24 * 3600)
    }
}
