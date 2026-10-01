import CoreLocation
import Observation

/// Die geführte Linie einer Fahrt und was aus ihr wird, wenn man sie verlässt:
/// wie weit daneben, seit wann, und ab wann der Weg von hier aus neu berechnet
/// wird.
///
/// Stand bis zum Aufräumen nach 1.9.1 mitten in `RideTracker`, zwischen
/// Ortung, Pause und Uhr. Hier ist es für sich: der Tracker reicht jede Ortung
/// herein, der Replanner sagt über `onAdopt`, wenn eine neue Linie gilt, und der
/// Tracker rechnet daraus Abbiegungen und Ampeln neu. Router und Ampelsuche
/// lassen sich austauschen, damit ein Test die Buchführung ohne Netz prüfen kann.
@MainActor
@Observable
final class Replanner {
    /// Was beim Start der Fahrt feststeht und jede Neuplanung braucht.
    struct Config {
        var mode: StreetMode = .bike
        /// Ab wann neu berechnet wird; 0 schaltet es ab.
        var offRouteMeters = OffRoute.replanMeters
        /// Womit neu geplant wird: dasselbe Profil wie die gewählte Linie.
        var profile: BRouterClient.Profile = .quiet
        var avoidCobbles = false
        /// Die Fixpunkte, die die geplante Linie anfährt — eine Neuplanung fährt
        /// die noch vor einem liegenden ebenfalls an.
        var via: [CLLocationCoordinate2D] = []
        /// Alle Ampeln der Fahrt samt Gelerntem; sie gelten auch auf dem neuen Weg.
        var knownSignals: [CLLocationCoordinate2D] = []
    }

    private(set) var config = Config()
    /// Die Linie, die gerade geführt wird.
    private(set) var plannedRoute: [CLLocationCoordinate2D] = []
    /// Die Linie, mit der die Fahrt begonnen hat. Sie bleibt, auch wenn
    /// unterwegs neu geplant wird — auf der Karte liegt sie dann dünn neben
    /// der neuen, und hinterher neben der gefahrenen.
    private(set) var originalRoute: [CLLocationCoordinate2D] = []
    /// Jede Route, die eine Neuplanung verworfen hat, älteste zuerst.
    private(set) var pastRoutes: [[CLLocationCoordinate2D]] = []
    /// Wo die geplante Linie liegt, solange man nicht auf ihr ist — nil,
    /// solange man auf ihr fährt. Treibt den Pfeil und das Herauszoomen.
    private(set) var detour: OffRoute.Fix?
    /// Wie oft der Weg unterwegs neu berechnet wurde. Nur fürs Protokoll.
    private(set) var replans = 0
    /// Seit wann ohne Unterbrechung neben der Route. Steht im roten Band
    /// neben dem Abstand; zugewiesen wird nur beim Wechsel, sonst baute
    /// `@Observable` den Fahrtbildschirm einmal die Sekunde neu auf.
    private(set) var offSince: Date?
    private var lastReplan = Date.distantPast
    private var task: Task<Void, Never>?

    /// Ins Protokoll der Fahrt (`RideEvent`).
    @ObservationIgnored var log: (_ kind: String, _ note: String?, _ at: CLLocationCoordinate2D?) -> Void = { _, _, _ in }
    /// Ob noch aufgezeichnet wird. Eine Antwort, die nach dem Ende kommt, gilt nicht.
    @ObservationIgnored var isActive: () -> Bool = { true }
    /// Eine neue Linie gilt: Abbiegungen, Ampeln und Beläge neu zuordnen.
    @ObservationIgnored var onAdopt: (_ route: StreetRoute, _ lights: [CLLocationCoordinate2D]) -> Void = { _, _ in }

    private let router: StreetRouting
    /// Die Ampeln entlang einer Linie, aus OpenStreetMap.
    private let signalsAlong: @Sendable ([CLLocationCoordinate2D]) async -> [CLLocationCoordinate2D]

    init(router: StreetRouting = CompositeRouter(),
         signalsAlong: @escaping @Sendable ([CLLocationCoordinate2D]) async -> [CLLocationCoordinate2D] = Replanner.osmSignals) {
        self.router = router
        self.signalsAlong = signalsAlong
    }

    /// Die Ampeln des **neuen** Wegs: aus demselben OpenStreetMap-Ausschnitt,
    /// mit dem geplant wurde (meist schon im Speicher). Ohne Netz keine.
    nonisolated static let osmSignals: @Sendable ([CLLocationCoordinate2D]) async -> [CLLocationCoordinate2D] = { line in
        guard let data = try? await RoadDataStore.shared.data(covering: line) else { return [] }
        return RouteAnalyzer.analyze(line, roads: data).signalPoints
    }

    /// Eine neue Fahrt: alles vom letzten Mal vergessen, eine noch laufende
    /// Anfrage abbrechen.
    func reset(route: [CLLocationCoordinate2D], config: Config) {
        self.config = config
        plannedRoute = route
        originalRoute = route
        pastRoutes = []
        detour = nil
        replans = 0
        offSince = nil
        lastReplan = .distantPast
        task?.cancel()
        task = nil
    }

    /// Wartet, bis die laufende Neuplanung durch ist — für Tests.
    func settle() async { await task?.value }

    // MARK: Neben der Route

    /// Einmal je Ortung, also einmal die Sekunde. Zugewiesen wird nur, was sich
    /// unterscheidet: `@Observable` fragt nicht nach, und ein `detour = nil`
    /// auf ein bereits leeres `detour` wäre eine gemeldete Änderung pro
    /// Sekunde — und damit ein Neuaufbau des ganzen Fahrtbildschirms samt
    /// Karte, die ganze Fahrt lang.
    func update(at here: CLLocationCoordinate2D, course: CLLocationDirection) {
        guard !plannedRoute.isEmpty, let fix = OffRoute.nearest(to: here, on: plannedRoute) else {
            if detour != nil { detour = nil }
            return
        }
        let next = OffRoute.isOff(fix.meters, was: detour != nil) ? fix : nil
        if (detour == nil) != (next == nil) {
            log(next == nil ? "zurück" : "abseits", next.map { "\(Int($0.meters)) m neben der Route" }, here)
        }
        if detour != next { detour = next }
        guard let next else {
            if offSince != nil { offSince = nil }
            return
        }
        let since = offSince ?? .now
        if offSince == nil { offSince = since }
        guard OffRoute.shouldReplan(meters: next.meters,
                                    offFor: Date.now.timeIntervalSince(since),
                                    afterMeters: config.offRouteMeters,
                                    afterMinutes: OffRoute.replanMinutes) else { return }
        replan(from: here, course: course)
    }

    /// Über einem Kilometer daneben ist die geplante Linie keine Hilfe mehr,
    /// sondern ein Pfeil auf eine Straße, die man nicht mehr erreicht. Dann
    /// wird der Weg zum Ziel **von hier aus** neu berechnet.
    ///
    /// Das ist die einzige Ausnahme von der Regel, dass die Führung beim Start
    /// der Fahrt einfriert. Die Regel gibt es, damit eine beiläufige
    /// Neuplanung nicht nachträglich umdeutet, was schon gemessen wurde — und
    /// genau das passiert hier nicht: gemessen bleibt, was gemessen wurde, neu
    /// ist nur der Weg nach vorn. Die Ampeln des neuen Wegs kommen aus dem
    /// OpenStreetMap-Ausschnitt und dem Gelernten; die schon passierten
    /// zählen weiter mit (`RideTracker.signalsBehind`).
    func replan(from here: CLLocationCoordinate2D, course: CLLocationDirection) {
        guard task == nil, Date.now.timeIntervalSince(lastReplan) >= OffRoute.replanEvery,
              let destination = plannedRoute.last else { return }
        lastReplan = .now
        let mode = config.mode
        let router = router
        let signalsAlong = signalsAlong
        // **Nicht von hier, sondern von gleich.** Ein Router kennt nur einen
        // Punkt, keine Fahrtrichtung — und schickt einen auf der Autobahn
        // dorthin zurück, wo man hergekommen ist, weil das die kürzeste
        // Verbindung zum Ziel ist. Ein Startpunkt ein Stück **voraus** sagt
        // ihm, wohin man zeigt: dort ist die Ausfahrt, die man gleich nimmt,
        // und die Wende kommt nicht mehr in Frage.
        let from = course >= 0 ? Geo.ahead(here, course: course, meters: Self.lookahead) : here
        // Das Rad darf wenden — ein Weg, der zurückführt, ist dort eine
        // Auskunft. Nur fürs Auto gilt die Wende als Witz.
        let heading = mode == .car ? course : -1
        let known = config.knownSignals
        let (profile, cobbles) = (config.profile, config.avoidCobbles)
        let ahead = WaypointRouting.ahead(config.via, from: here, to: destination)
        log("neuplanung", "\(Int(detour?.meters ?? 0)) m daneben, Kurs \(Int(course))°, \(ahead.count) Fixpunkte voraus", here)
        task = Task { [weak self] in
            // Eine Anfrage, die nie zurückkommt, darf nicht jede weitere
            // Neuplanung sperren: `task` bliebe sonst für immer besetzt.
            var route: StreetRoute?
            var failure: String?
            do {
                route = try await Self.withTimeout(Self.timeout) {
                    mode == .bike
                        ? try await router.bikeRoute(from: from, to: destination, via: ahead,
                                                    profile: profile, avoidCobbles: cobbles)
                        : try await router.route(from: from, to: destination, mode: mode, departure: .now)
                }
            } catch {
                failure = error is TimedOut ? "keine Antwort nach \(Int(Self.timeout)) s" : "\(error)"
            }
            // Dazu alles Gelernte. Ohne Netz bleibt es beim Gelernten und bei
            // den Ampeln der alten Route, die auch auf der neuen liegen.
            var lights: [CLLocationCoordinate2D] = known
            if let line = route?.coordinates, line.count > 1 {
                lights += await signalsAlong(line)
            }
            await MainActor.run {
                if let failure { self?.log("fehlgeschlagen", failure, nil) }
                self?.adopt(route, heading: heading, lights: lights)
            }
        }
    }

    /// Länger wartet eine Neuplanung nicht auf ihre Antwort.
    static let timeout: TimeInterval = 30

    struct TimedOut: Error {}

    nonisolated static func withTimeout<T: Sendable>(_ seconds: TimeInterval,
                                                     _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimedOut()
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    /// So weit voraus wird die Neuplanung angesetzt. Zwei Sekunden bei
    /// Autobahntempo, zwanzig auf dem Rad — weit genug, dass keine Ausfahrt
    /// zurückliegt, nah genug, dass nichts übersprungen wird.
    static let lookahead = 60.0

    private func adopt(_ route: StreetRoute?, heading: CLLocationDirection, lights: [CLLocationCoordinate2D]) {
        task = nil
        guard isActive(), let route, route.coordinates.count > 1 else { return }
        // Führt der neue Weg als Erstes dorthin zurück, wo man herkommt, ist
        // er eine Wende — auf einer Autobahn ist das keine Auskunft, sondern
        // ein Witz. Dann lieber den alten Weg stehen lassen und es in einer
        // Minute noch einmal versuchen.
        if heading >= 0, Self.turnsBack(route.coordinates, heading: heading) {
            log("verworfen", "führt zurück", nil)
            return
        }
        log("übernommen", "\(Int(TurnGuide.cumulative(route.coordinates).last ?? 0)) m bis zum Ziel", nil)
        pastRoutes.append(plannedRoute)
        plannedRoute = route.coordinates
        if detour != nil { detour = nil }
        offSince = nil
        replans += 1
        onAdopt(route, lights)
    }

    /// Ob eine frisch geplante Linie als Erstes zurückweist. Gemessen über
    /// die ersten `backCheckMeters`: ein Bogen um einen Kreisverkehr zählt
    /// nicht, eine Wende schon.
    nonisolated static func turnsBack(_ route: [CLLocationCoordinate2D],
                                      heading: CLLocationDirection) -> Bool {
        guard let first = route.first else { return false }
        var ahead = route.last!
        var run = 0.0
        for (a, b) in zip(route, route.dropFirst()) {
            run += a.distance(to: b)
            if run >= backCheckMeters { ahead = b; break }
        }
        guard let bearing = RideTracker.courseFromTrack([RidePoint(lat: first.latitude, lon: first.longitude,
                                                                   t: .distantPast, v: 0),
                                                         RidePoint(lat: ahead.latitude, lon: ahead.longitude,
                                                                   t: .distantPast, v: 0)]) else { return false }
        let diff = abs((bearing - heading + 540).truncatingRemainder(dividingBy: 360) - 180)
        return diff > 120
    }

    /// So weit wird hineingesehen, um „geht zurück" von „macht einen Bogen"
    /// zu unterscheiden.
    static let backCheckMeters = 150.0
}
