import CoreLocation
import XCTest
@testable import RadPendler

/// **Routenregeln** — was der Planer nie vorschlagen darf, als Verzeichnis an
/// einer Stelle. Läuft mit `./dev rules` in Sekunden und ohne Netz, und vor
/// jedem `./dev testflight` als Erstes: ein Rückfall soll am Mac auffallen,
/// nicht nach Upload und Probefahrt (Nutzer, 11.10.2026: „Bei Fahrt mit Auto
/// wieder mehrfach Routenvorschläge als Geisterfahrer auf Autobahn/Landstraße“
/// — die zweite Woche in Folge).
///
/// 1. **Nie gegen die Fahrtrichtung** (Auto). Ursachen und Abhilfen im
///    CHANGELOG 1.19.
/// 2. **Nie Kopfstein** (Rad; Nutzer, 07.10.2026: „Nie Kopfstein, egal welche
///    Route“).
///
/// Geprüft wird dort, wo die Entscheidung fällt — Planer, Neuplanung,
/// Aufzeichnung —, mit erfundenen Routern und einem nachgestellten BRouter,
/// nicht an den Hilfsfunktionen allein. Einzelne Regeln stehen in anderer
/// Form auch in `ReplannerTests`, `RideTrackerTests` und `BikeRouteTests`;
/// hier steht, was am Ende herauskommt. Was die echte Karte daraus macht,
/// prüft `./dev routes` (Netz, rund eine Minute).
@MainActor
final class RouteRulesTests: XCTestCase {
    // Alexanderplatz und S Wannsee — die Testorte des Repositorys.
    private let alex = CLLocationCoordinate2D(latitude: 52.5210, longitude: 13.4130)
    private let wannsee = CLLocationCoordinate2D(latitude: 52.4213, longitude: 13.1794)

    private func east(_ meters: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: alex.latitude,
                               longitude: alex.longitude + meters / (111_320 * cos(alex.latitude * .pi / 180)))
    }

    private func north(_ meters: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: alex.latitude + meters / 111_320, longitude: alex.longitude)
    }

    private var folder: URL!
    private var store: RideStore!
    private var soundsWereOn = true

    override func setUp() async throws {
        folder = URL.temporaryDirectory.appending(path: "RouteRulesTests-\(UUID().uuidString)")
        store = RideStore(folder: folder, defaults: UserDefaults(suiteName: "rules-\(UUID().uuidString)")!)
        soundsWereOn = RideSounds.shared.enabled
        RideSounds.shared.enabled = false
        FakeBRouter.reset()
    }

    override func tearDown() async throws {
        RideSounds.shared.enabled = soundsWereOn
        try? FileManager.default.removeItem(at: folder)
    }

    /// Eine Autofahrt, die aufzeichnet — mit eigenem Router für die Neuplanung.
    private func carRide(_ router: StreetRouting, line: [CLLocationCoordinate2D])
        -> (RideTracker, Replanner, () -> [String]) {
        let replanner = Replanner(router: router, signalsAlong: { _ in [] })
        let tracker = RideTracker(store: store, replanner: replanner)
        tracker.authorization = { .authorizedWhenInUse }
        tracker.start(RidePlan(subject: .init(origin: "A", destination: "B", mode: TravelMode.car.rawValue),
                               signals: [], route: line))
        var kinds: [String] = []
        let log = replanner.log
        replanner.log = { kind, note, at in kinds.append(kind); log(kind, note, at) }
        return (tracker, replanner, { kinds })
    }

    /// Im Auto auf der Linie nach Westen, gegen sie: eine Ortung je Sekunde,
    /// 15 m/s.
    private func driveWest(_ tracker: RideTracker, from start: Double, seconds: ClosedRange<Int>) {
        let t0 = Date.now.addingTimeInterval(-120)
        for second in seconds {
            tracker.accept([RideMeter.Fix(coordinate: east(start - Double(second) * 15),
                                          time: t0.addingTimeInterval(Double(second)), speed: 15)], [270])
        }
    }

    private func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        TurnGuide.bearing(from: a, to: b)
    }

    /// Abweichung zweier Kurse in Grad, 0…180.
    private func angle(_ a: Double, _ b: Double) -> Double {
        abs((a - b + 540).truncatingRemainder(dividingBy: 360) - 180)
    }

    // MARK: - Regel 1: Nie gegen die Fahrtrichtung (Auto)

    /// Nutzer, 11.10.2026: „wieder mehrfach Routenvorschläge als Geisterfahrer
    /// auf Autobahn/Landstraße“. Ein Router kennt nur Punkte, keine
    /// Fahrtrichtung: die Neuplanung im Auto fragt deshalb **voraus**, in
    /// Kursrichtung, und gibt den Kurs an die Prüfung des Ergebnisses weiter.
    func testCarReplanStartsAheadInTheDirectionOfTravel() async throws {
        let router = ScriptedRouter(.straight)
        let (tracker, replanner, kinds) = carRide(router, line: (0...10).map { north(Double($0) * 300) })
        defer { tracker.stop() }
        let here = east(400)                                   // abgebogen, fährt nach Osten
        replanner.replan(from: here, course: 90)
        await replanner.settle()

        let call = try XCTUnwrap(router.calls.first)
        XCTAssertEqual(call.mode, .car)
        XCTAssertEqual(here.distance(to: call.from), Replanner.lookahead, accuracy: 2,
                       "gefragt wird ab einem Punkt voraus, nicht ab dem Fahrer")
        XCTAssertLessThan(angle(bearing(here, call.from), 90), 5, "voraus heißt: in Kursrichtung")
        XCTAssertEqual(kinds(), ["neuplanung", "übernommen"])
        XCTAssertEqual(tracker.plannedRoute.first?.longitude ?? 0, call.from.longitude, accuracy: 1e-9,
                       "die neue Linie beginnt vor dem Fahrer")
    }

    /// Nutzer, 11.10.2026 (Geisterfahrer). Liefert der Router trotzdem eine
    /// Linie, die als Erstes kehrtmacht — zurück, woher man kommt —, nimmt die
    /// Neuplanung im Auto sie nicht: der alte Weg bleibt stehen.
    func testCarReplanThatTurnsBackIsNotTaken() async throws {
        // Der Router schickt zurück: vom Punkt voraus 400 m gegen den Kurs, dann zum Ziel.
        let router = ScriptedRouter(.backFirst(course: 90, meters: 400))
        let line = (0...10).map { north(Double($0) * 300) }
        let (tracker, replanner, kinds) = carRide(router, line: line)
        defer { tracker.stop() }
        replanner.replan(from: east(400), course: 90)
        await replanner.settle()

        XCTAssertEqual(router.calls.count, 1)
        XCTAssertEqual(kinds(), ["neuplanung", "verworfen"])
        XCTAssertEqual(replanner.replans, 0)
        XCTAssertEqual(tracker.plannedRoute.count, line.count, "die Wende wird nicht geführt")
        XCTAssertEqual(tracker.plannedRoute.last?.latitude, line.last?.latitude)
    }

    /// Nutzer, 11.10.2026 (Geisterfahrer; CHANGELOG 1.19): nach „Richtung
    /// tauschen“ stand der alte Plan, bis der neue da war, und ein Tipp auf
    /// „Fahrt“ nahm die Linie der Gegenrichtung mit. Der alte Plan muss weg
    /// sein, **sobald** die neue Frage gestellt ist — und der neue beginnt am
    /// neuen Start.
    func testSwappedDirectionLeavesNoOldLineForTheRide() async throws {
        var planner = TripPlanner.offline
        planner.apple = ScriptedRouter(.straight)
        let model = PlanModel(planner: planner)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "rules-\(UUID().uuidString)")!)
        settings.origin = Place(name: "Alexanderplatz", latitude: alex.latitude, longitude: alex.longitude)
        settings.destination = Place(name: "S Wannsee", latitude: wannsee.latitude, longitude: wannsee.longitude)
        model.refresh(settings: settings)
        try await waitUntil { !model.isLoading }
        let there = try XCTUnwrap(model.options(for: .car).first, "der Hinweg hat eine Autolinie")
        XCTAssertLessThan(try XCTUnwrap(there.legs.first?.coordinates.first).distance(to: alex), 1)

        (settings.origin, settings.destination) = (settings.destination, settings.origin)
        model.refresh(settings: settings)
        // Die Lücke, in der „Fahrt“ getippt wurde: der neue Plan ist noch nicht da.
        XCTAssertTrue(model.isLoading)
        XCTAssertNil(model.selected, "nichts zum Mitnehmen, solange der neue Plan fehlt")
        XCTAssertTrue(RidePlan.route(of: model.options, selected: nil).isEmpty)

        try await waitUntil { !model.isLoading }
        for mode in [TravelMode.car, .bike] {
            let start = try XCTUnwrap(model.options(for: mode).first?.legs.first?.coordinates.first, "\(mode)")
            XCTAssertLessThan(start.distance(to: wannsee), 1, "\(mode): die Linie beginnt am neuen Start")
        }
    }

    /// Fahrt 11.10.2026 (Geisterfahrer; CHANGELOG 1.19): die Aufzeichnung
    /// begann hinter dem Ziel der Linie, die Fahrt lief 13 Minuten auf ihr
    /// zurück. Wer zwanzig Ortungen am Stück gegen die Linie fährt, dreht
    /// sie um — und bekommt sofort einen Weg in **seine** Richtung geplant,
    /// zum bisherigen Start, ab einem Punkt voraus.
    func testRidingAgainstTheLineTurnsItAndPlansTheWayAhead() async throws {
        let router = ScriptedRouter(.straight)
        let line = [east(0), east(5_000)]
        let (tracker, replanner, kinds) = carRide(router, line: line)
        defer { tracker.stop() }
        driveWest(tracker, from: 3_000, seconds: 0...18)
        XCTAssertEqual(tracker.subject?.destination, "B", "eine Wende auf der Straße dauert kürzer")
        XCTAssertTrue(router.calls.isEmpty)

        driveWest(tracker, from: 3_000, seconds: 19...24)
        await replanner.settle()
        XCTAssertEqual(tracker.subject?.destination, "A", "die Fahrt geht zum bisherigen Start")
        let call = try XCTUnwrap(router.calls.first, "die umgedrehte Linie wird neu geplant")
        XCTAssertLessThan(call.to.distance(to: east(0)), 1)
        XCTAssertLessThan(call.from.longitude, east(3_000 - 19 * 15).longitude, "gefragt ab voraus, nach Westen")
        XCTAssertEqual(replanner.replans, 1)
        XCTAssertTrue(kinds().contains("übernommen"))
        let route = tracker.plannedRoute
        XCTAssertGreaterThan(route.first?.distance(to: east(5_000)) ?? 0, 2_000,
                             "geführt wird nicht die umgedrehte Linie vom alten Ziel aus")
        XCTAssertLessThan(angle(bearing(route[0], route[1]), 270), 10, "die Linie zeigt, wohin gefahren wird")
    }

    /// Fahrt 11.10.2026 (Geisterfahrer): eine umgedrehte Linie liegt auf der
    /// Gegenfahrbahn — nah genug, dass nie „neben der Route“ gemeldet wird,
    /// und deshalb würde auch nie neu geplant. Sie darf nicht gefahren werden,
    /// auch dann nicht, wenn kurz vorher eine Neuplanung als Wende verworfen
    /// wurde und die Minute bis zur nächsten noch läuft.
    func testATurnedLineIsReplannedEvenRightAfterARejectedReplan() async throws {
        let router = ScriptedRouter(.straight)
        let (tracker, replanner, kinds) = carRide(router, line: [east(0), east(5_000)])
        defer { tracker.stop() }
        // Vorher, nach Westen unterwegs: der Weg zum Ende der Linie (Osten) ist eine Wende.
        replanner.replan(from: east(3_000), course: 270)
        await replanner.settle()
        XCTAssertEqual(kinds(), ["neuplanung", "verworfen"])

        driveWest(tracker, from: 3_000, seconds: 0...24)
        await replanner.settle()
        XCTAssertEqual(tracker.subject?.destination, "A")
        XCTAssertEqual(router.calls.count, 2, "die umgedrehte Linie wird sofort neu geplant")
        XCTAssertEqual(replanner.replans, 1)
        XCTAssertGreaterThan(tracker.plannedRoute.first?.distance(to: east(5_000)) ?? 0, 2_000)
    }

    /// Fahrt 11.10.2026 (Geisterfahrer): kommt auf die Neuplanung der
    /// umgedrehten Linie keine Antwort (Funkloch), bleibt sie nur ein
    /// Behelf — sie wird neu geplant, sobald es wieder geht, auch ohne dass
    /// man neben ihr fährt.
    func testATurnedLineThatCouldNotBeReplannedStaysMarkedForReplanning() async throws {
        let router = ScriptedRouter(.fail, .straight)
        let (tracker, replanner, _) = carRide(router, line: [east(0), east(5_000)])
        defer { tracker.stop() }
        driveWest(tracker, from: 3_000, seconds: 0...24)
        await replanner.settle()
        XCTAssertEqual(tracker.subject?.destination, "A")
        XCTAssertEqual(router.calls.count, 1)
        XCTAssertEqual(replanner.replans, 0)
        XCTAssertTrue(replanner.needsReplan, "die umgedrehte Linie ist kein Plan")
    }

    // MARK: - Regel 2: Nie Kopfstein (Rad)

    /// Nutzer, 07.10.2026: „Nie Kopfstein, egal welche Route.“ Seit 1.17
    /// gibt es keinen Schalter mehr; auch ein alter, gespeicherter „aus“-Wert
    /// gilt nicht. Und jede Fahrt plant unterwegs mit der Pflasterregel neu,
    /// welche Linie auch immer gewählt war.
    func testCobblesAreAvoidedByDefaultEverywhere() {
        XCTAssertTrue(PlanSettings().avoidCobbles)
        XCTAssertTrue(BRouterClient().avoidCobbles)
        let defaults = UserDefaults(suiteName: "rules-\(UUID().uuidString)")!
        defaults.set(false, forKey: "avoidCobbles")
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.snapshot.avoidCobbles, "ein alter Schalter von vor 1.17 zählt nicht")

        let sources: [BikeLineSource] = [.brouter(.trekking), .brouter(.quiet), .brouter(.fastbike),
                                         .brouter(.shortest), .brouter(.safety), .brouter(.lowTraffic),
                                         .apple, .habit]
        for source in sources {
            var option = TripOption(mode: .bike, legs: [Leg(kind: .bike, fromName: "A", toName: "B",
                                                            departure: .now, arrival: .now.addingTimeInterval(600),
                                                            distance: 3_000, coordinates: [east(0), east(3_000)])],
                                    prep: 0)
            option.bikeRoute = BikeRouteInfo(variants: [.balanced], stats: nil, source: source)
            let plan = RidePlan.make(option: option, options: [option], settings: settings)
            XCTAssertTrue(plan.avoidCobbles, "Neuplanung unterwegs auf der Linie \(source)")
        }
    }

    /// Nutzer, 07.10.2026: „Nie Kopfstein, egal welche Route.“ Jedes Profil,
    /// das an BRouter geht — jede Rolle, mit und ohne Fahrradstraßen —, trägt
    /// den Aufschlag in wirksamer Höhe vor dem Knotenteil.
    func testEveryBRouterProfileCarriesTheCobblePenalty() throws {
        let all: [BRouterClient.Profile] = [.trekking, .safety, .fastbike, .shortest, .lowTraffic, .quiet]
        for profile in all {
            let kind = CustomProfile.Kind(profile: profile, withoutCobbles: true)
            let url = try XCTUnwrap(Bundle.main.url(forResource: kind.resource, withExtension: "brf"), profile.rawValue)
            let text = CustomProfile.adjusted(try String(contentsOf: url, encoding: .utf8), withoutCobbles: true,
                                              cycleStreets: profile.cycleStreetAdvantage)
            let penalty = try XCTUnwrap(FakeBRouter.cobblePenalty(in: text), profile.rawValue)
            XCTAssertGreaterThanOrEqual(penalty, FakeBRouter.effectivePenalty, profile.rawValue)
        }
    }

    /// Nutzer, 07.10.2026: „Nie Kopfstein, egal welche Route.“ Die ganze
    /// Radplanung gegen einen nachgestellten BRouter, der den kurzen Weg über
    /// Pflaster nimmt, wenn das Profil es nicht teuer genug macht: jedes
    /// hochgeladene Profil trägt den Aufschlag, keine Route wird ohne
    /// eigenes Profil gefragt, und keine gezeigte Linie fährt über Pflaster.
    func testThePlannedBikeLinesAvoidCobbles() async throws {
        var planner = TripPlanner.offline
        planner.brouter.session = FakeBRouter.session()
        let req = bikeRequest()
        let options = try await planner.bikeOptions(req)

        XCTAssertEqual(options.count, req.settings.bikeOptions, "eine Linie je Rolle")
        let uploads = FakeBRouter.uploads
        XCTAssertEqual(Set(uploads.compactMap(FakeBRouter.profileName)), ["trekking", "quiet", "fastbike", "shortest"])
        for text in uploads {
            XCTAssertGreaterThanOrEqual(FakeBRouter.cobblePenalty(in: text) ?? 0, FakeBRouter.effectivePenalty,
                                        FakeBRouter.profileName(text) ?? "?")
        }
        XCTAssertEqual(FakeBRouter.plainRequests, [], "jede Route mit Pflasterregel")
        for option in options {
            XCTAssertLessThanOrEqual(try XCTUnwrap(option.bikeRoute).cobbleMeters, BikeCandidate.cobbleAllowance,
                                     "\(option.bikeRoute?.variants ?? [])")
        }
    }

    /// Nutzer, 07.10.2026: „Nie Kopfstein, egal welche Route.“ Lässt sich ein
    /// Profil nicht hochladen, fragt der Client BRouters eigenes, ohne
    /// Pflasterregel — lieber eine Linie als keine. Gezeigt wird sie trotzdem
    /// nicht, solange andere ohne Pflaster dastehen, auch wenn sie die
    /// schnellste und kürzeste ist.
    func testALineWithCobblesIsNotShownWhileOneWithoutExists() async throws {
        var planner = TripPlanner.offline
        planner.brouter.session = FakeBRouter.session(refusing: "fastbike")
        let options = try await planner.bikeOptions(bikeRequest())

        XCTAssertEqual(FakeBRouter.plainRequests, ["fastbike"], "der Rückfall ist eingetreten")
        XCTAssertFalse(options.isEmpty)
        for option in options {
            XCTAssertLessThanOrEqual(try XCTUnwrap(option.bikeRoute).cobbleMeters, BikeCandidate.cobbleAllowance,
                                     "\(option.bikeRoute?.variants ?? []) fährt über Pflaster")
        }
    }

    /// Nutzer, 07.10.2026: „Nie Kopfstein, egal welche Route.“ Die
    /// Rollenvergabe für sich: eine Linie mit Pflaster bekommt keine Rolle
    /// und keinen Platz, wenn es eine ohne gibt — auch nicht als gewohnte.
    /// Haben alle Pflaster, steht trotzdem eine da.
    func testRoleAssignmentSkipsLinesWithCobbles() {
        func candidate(_ source: BikeLineSource, km: Double, cobbles: Double, bend: Double) -> BikeCandidate {
            let line = [east(0), CLLocationCoordinate2D(latitude: alex.latitude + bend, longitude: east(km * 500).longitude),
                        east(km * 1_000)]
            return BikeCandidate(source: source, route: StreetRoute(distance: km * 1_000, expectedTravelTime: 0,
                                                                    coordinates: line, cobbleMeters: cobbles))
        }
        let cobbled = candidate(.brouter(.fastbike), km: 4.0, cobbles: 400, bend: 0)
        let clean = [candidate(.brouter(.trekking), km: 4.6, cobbles: 0, bend: 0.004),
                     candidate(.brouter(.quiet), km: 5.0, cobbles: 20, bend: 0.008),
                     candidate(.brouter(.shortest), km: 4.4, cobbles: 0, bend: -0.004)]
        let habit = candidate(.habit, km: 4.1, cobbles: 300, bend: -0.008)
        let s = PlanSettings()

        let picked = BikeCandidate.pick([cobbled] + clean + [habit], settings: s)
        XCTAssertFalse(picked.isEmpty)
        XCTAssertFalse(picked.contains { $0.0.route.cobbleMeters > BikeCandidate.cobbleAllowance },
                       "gezeigt: \(picked.map { "\($0.0.source) \(Int($0.0.route.cobbleMeters)) m" })")
        XCTAssertTrue(picked.contains { $0.1.contains(.fastest) }, "„schnellst“ geht an die schnellste ohne Pflaster")

        let onlyCobbled = BikeCandidate.pick([cobbled], settings: s)
        XCTAssertEqual(onlyCobbled.count, 1, "lieber eine Linie mit Pflaster als keine")
    }

    /// Nutzer, 07.10.2026: „Nie Kopfstein, egal welche Route.“ Auch die
    /// Neuplanung unterwegs fragt BRouter mit dem Profil der gewählten Linie
    /// **und** dem Aufschlag — vom Plan über die Aufzeichnung bis zum
    /// hochgeladenen Profil.
    func testTheReplanOnTheBikeAsksForTheCobblePenalty() async throws {
        var client = BRouterClient()
        client.session = FakeBRouter.session()
        client.cached = false
        let replanner = Replanner(router: CompositeRouter(brouter: client, apple: DeadRouter()),
                                  signalsAlong: { _ in [] })
        let tracker = RideTracker(store: store, replanner: replanner)
        tracker.authorization = { .authorizedWhenInUse }
        defer { tracker.stop() }
        var option = TripOption(mode: .bike, legs: [Leg(kind: .bike, fromName: "A", toName: "B",
                                                        departure: .now, arrival: .now.addingTimeInterval(900),
                                                        distance: 4_000, coordinates: [east(0), east(4_000)])],
                                prep: 0)
        option.bikeRoute = BikeRouteInfo(variants: [.fastest], stats: nil, source: .brouter(.fastbike))
        let settings = AppSettings(defaults: UserDefaults(suiteName: "rules-\(UUID().uuidString)")!)
        tracker.start(RidePlan.make(option: option, options: [option], settings: settings))

        replanner.replan(from: north(600), course: 90)
        await replanner.settle()
        XCTAssertEqual(replanner.replans, 1)
        XCTAssertEqual(FakeBRouter.uploads.compactMap(FakeBRouter.profileName), ["fastbike"],
                       "das Profil der gewählten Linie")
        XCTAssertGreaterThanOrEqual(FakeBRouter.uploads.first.flatMap(FakeBRouter.cobblePenalty) ?? 0,
                                    FakeBRouter.effectivePenalty)
        XCTAssertEqual(FakeBRouter.plainRequests, [])
        XCTAssertEqual(FakeBRouter.answeredCobbles, [0], "die neue Linie fährt nicht über Pflaster")
    }

    // MARK: - Werkzeug

    private func bikeRequest() -> PlanRequest {
        PlanRequest(origin: Place(name: "Alexanderplatz", latitude: alex.latitude, longitude: alex.longitude),
                    destination: Place(name: "S Wannsee", latitude: wannsee.latitude, longitude: wannsee.longitude),
                    target: .departAfter(.now), settings: PlanSettings())
    }

    private func waitUntil(_ done: () -> Bool, seconds: Double = 10) async throws {
        let until = Date.now.addingTimeInterval(seconds)
        while !done() {
            guard Date.now < until else { return XCTFail("nach \(Int(seconds)) s nicht fertig") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

// MARK: - Erfundene Router

/// Ein Straßenrouter, der der Reihe nach antwortet, wie der Test es will, und
/// mitschreibt, wonach gefragt wurde. Die letzte Antwort gilt für alles Weitere.
private final class ScriptedRouter: StreetRouting, @unchecked Sendable {
    enum Answer {
        /// Gerade vom Start zum Ziel.
        case straight
        /// Erst `meters` gegen `course` zurück, dann zum Ziel — eine Wende.
        case backFirst(course: Double, meters: Double)
        /// Keine Antwort.
        case fail
    }

    struct Call { var from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, mode: StreetMode }

    private let lock = NSLock()
    private var answers: [Answer]
    private var made: [Call] = []

    init(_ answers: Answer...) { self.answers = answers }

    var calls: [Call] { lock.withLock { made } }

    func route(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
               mode: StreetMode, departure: Date?) async throws -> StreetRoute {
        let answer = lock.withLock { () -> Answer in
            made.append(Call(from: from, to: to, mode: mode))
            return answers.count > 1 ? answers.removeFirst() : answers[0]
        }
        let line: [CLLocationCoordinate2D]
        switch answer {
        case .straight: line = Self.straight(from, to)
        case .backFirst(let course, let meters):
            let back = Geo.ahead(from, course: (course + 180).truncatingRemainder(dividingBy: 360), meters: meters)
            line = Self.straight(from, back) + Self.straight(back, to).dropFirst()
        case .fail: throw DeadRouter.Offline()
        }
        return StreetRoute(distance: TurnGuide.cumulative(line).last ?? 0, expectedTravelTime: 600, coordinates: line)
    }

    /// Alle 50 m ein Punkt, damit die Prüfung auf die ersten 150 m etwas sieht.
    static func straight(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        let n = Swift.max(2, Int(a.distance(to: b) / 50))
        return (0...n).map { i in
            let f = Double(i) / Double(n)
            return CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * f,
                                          longitude: a.longitude + (b.longitude - a.longitude) * f)
        }
    }
}

/// brouter.de, nachgestellt: nimmt Profile entgegen und beantwortet Routen
/// so, wie der echte Server es auf einer Strecke mit einer kurzen
/// Pflasterstraße täte — den kurzen Weg über das Pflaster, wenn das Profil
/// es nicht teuer genug macht, sonst den Umweg ohne. Jedes Profil bekommt
/// einen eigenen Umweg, damit die Rollen verschiedene Linien sehen.
private final class FakeBRouter: URLProtocol {
    /// Ab diesem Aufschlag je Meter meidet ein Profil das Pflaster. Gemessen
    /// am 07.10.2026 (`CustomProfile.withoutCobbles`): mit 5 blieben auf der
    /// Teststrecke 115–310 m, mit 20 noch 290 m, mit 100 nur 0–43 m.
    static let effectivePenalty = 100
    /// So viel Pflaster liegt auf dem kurzen Weg.
    static let cobbleMeters = 400.0

    private static let lock = NSLock()
    nonisolated(unsafe) private static var profiles: [String: String] = [:]
    nonisolated(unsafe) private static var uploaded: [String] = []
    nonisolated(unsafe) private static var plain: [String] = []
    nonisolated(unsafe) private static var cobbles: [Double] = []
    nonisolated(unsafe) private static var refused: Set<String> = []

    static func reset() {
        lock.withLock { profiles = [:]; uploaded = []; plain = []; cobbles = []; refused = [] }
    }

    /// Eine Sitzung, die nur diesen Server kennt. `refusing`: Profile, deren
    /// Hochladen scheitert.
    static func session(refusing: String...) -> URLSession {
        lock.withLock { refused = Set(refusing) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeBRouter.self]
        return URLSession(configuration: config)
    }

    /// Die hochgeladenen Profile, im Wortlaut.
    static var uploads: [String] { lock.withLock { uploaded } }
    /// Routen, die mit BRouters eigenem Profil gefragt wurden — ohne Pflasterregel.
    static var plainRequests: [String] { lock.withLock { plain } }
    /// Die Pflastermeter jeder beantworteten Route.
    static var answeredCobbles: [Double] { lock.withLock { cobbles } }

    /// Der Aufschlag aufs Pflaster, wo er in der Kostenzeile vor dem
    /// Knotenteil steht — und nur dort wirkt er.
    static func cobblePenalty(in text: String) -> Int? {
        guard let node = text.range(of: "---context:node") else { return nil }
        let head = text[..<node.lowerBound]
        let rule = "switch surface=sett|cobblestone "
        guard head.contains("assign costfactor_base"), let at = head.range(of: rule) else { return nil }
        return Int(head[at.upperBound...].prefix { $0.isNumber })
    }

    /// Welches Profil ein hochgeladener Text ist.
    static func profileName(_ text: String) -> String? {
        let first = text.prefix { $0 != "\n" }
        if first.contains("RadPendler „wenig Autos“") { return "quiet" }
        for name in ["fastbike-lowtraffic", "fastbike", "trekking", "shortest", "safety"]
            where first.contains("„\(name)“") { return name }
        return nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        if url.path.hasSuffix("/profile") {
            let text = String(decoding: body(), as: UTF8.self)
            let name = Self.profileName(text) ?? "?"
            let id = "custom_\(UUID().uuidString)"
            let refuse = Self.lock.withLock { () -> Bool in
                Self.uploaded.append(text)
                if Self.refused.contains(name) { return true }
                Self.profiles[id] = text
                return false
            }
            if refuse { return reply(500, Data("{\"error\":\"nachgestellt\"}".utf8)) }
            return reply(200, try! JSONSerialization.data(withJSONObject: ["profileid": id]))
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let profile = items.first { $0.name == "profile" }?.value ?? ""
        let ends = (items.first { $0.name == "lonlats" }?.value ?? "").split(separator: "|").map { pair in
            let v = pair.split(separator: ",").compactMap { Double($0) }
            return CLLocationCoordinate2D(latitude: v[1], longitude: v[0])
        }
        guard let from = ends.first, let to = ends.last else { return reply(400, Data()) }
        let text: String?
        if profile.hasPrefix("custom_") {
            // Eine Kennung aus einem früheren Test kennt dieser Server nicht —
            // wie der echte, wenn er sie weggeräumt hat. Der Client lädt neu.
            guard let known = Self.lock.withLock({ Self.profiles[profile] }) else {
                return reply(500, Data("unknown profile".utf8))
            }
            text = known
        } else {
            Self.lock.withLock { Self.plain.append(profile) }
            text = nil
        }
        let avoids = text.flatMap(Self.cobblePenalty).map { $0 >= Self.effectivePenalty } ?? false
        let name = text.flatMap(Self.profileName) ?? profile
        let detour = ["trekking": 1, "quiet": 2, "fastbike": 3, "shortest": 4, "safety": 5,
                      "fastbike-lowtraffic": 6][name] ?? 7
        let cobbles = avoids ? 0 : Self.cobbleMeters
        Self.lock.withLock { Self.cobbles.append(cobbles) }
        reply(200, Self.geojson(from: from, to: to, bend: avoids ? 0.004 * Double(detour) : 0, cobbles: cobbles))
    }

    private func body() -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 16_384)
        stream.open()
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        stream.close()
        return data
    }

    private func reply(_ status: Int, _ data: Data) {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    /// Eine Antwort im Format von brouter.de: die Linie (über einen
    /// seitlichen Bogen, wenn `bend` nicht 0 ist) und die Tabelle der
    /// Abschnitte mit ihrem Belag.
    static func geojson(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
                        bend: Double, cobbles: Double) -> Data {
        let mid = CLLocationCoordinate2D(latitude: (from.latitude + to.latitude) / 2 + bend,
                                         longitude: (from.longitude + to.longitude) / 2 + bend)
        let line = ScriptedRouter.straight(from, mid) + ScriptedRouter.straight(mid, to).dropFirst()
        let length = TurnGuide.cumulative(line).last ?? 0
        var rows: [[String]] = [["Longitude", "Latitude", "Distance", "WayTags"]]
        rows.append([String(Int(from.longitude * 1e6)), String(Int(from.latitude * 1e6)),
                     String(Int(length - cobbles)), "highway=residential surface=asphalt"])
        if cobbles > 0 {
            rows.append([String(Int(mid.longitude * 1e6)), String(Int(mid.latitude * 1e6)),
                         String(Int(cobbles)), "highway=residential surface=cobblestone"])
        }
        let feature: [String: Any] = [
            "type": "Feature",
            "geometry": ["type": "LineString", "coordinates": line.map { [$0.longitude, $0.latitude, 40] }],
            "properties": ["track-length": String(Int(length)), "total-time": String(Int(length / 5)),
                           "filtered ascend": "0", "messages": rows],
        ]
        return try! JSONSerialization.data(withJSONObject: ["type": "FeatureCollection", "features": [feature]])
    }
}
