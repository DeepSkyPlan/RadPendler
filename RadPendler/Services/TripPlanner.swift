import CoreLocation
import Foundation

/// Either "leave after this" or "be there by this".
enum PlanTarget: Equatable {
    case departAfter(Date)
    case arriveBy(Date)
}

struct PlanRequest {
    var origin: Place
    var destination: Place
    var target: PlanTarget
    var settings: PlanSettings

    /// Earliest moment to walk out of the door: preparation comes on top of
    /// the chosen start.
    var earliestLeave: Date {
        switch target {
        case .departAfter(let d): d.addingTimeInterval(settings.prep)
        case .arriveBy: .now.addingTimeInterval(settings.prep)
        }
    }

    /// The moment to be there, buffer already subtracted.
    var arriveBy: Date? {
        if case .arriveBy(let d) = target { d.addingTimeInterval(-settings.arrivalBuffer) } else { nil }
    }

    var isArrival: Bool { arriveBy != nil }
}

struct PlanResult {
    var options: [TripOption] = []
    /// Per-mode failure text, shown in place of that mode's rows.
    var failures: [TravelMode: String] = [:]
    var rainFailure: String?
    var recommendation: Recommendation?
}

struct Recommendation {
    var optionID: TripOption.ID
    var reason: String
}

/// Asks all sources at once and merges their answers into one ranked list.
struct TripPlanner {
    var hafas = HafasClient()
    var motis = MotisClient()
    var streets: StreetRouting = CompositeRouter()
    /// Die eigenen gefahrenen Wege. Tests geben einen eigenen, leeren.
    var habits: RiddenPaths = .shared
    var brouter = BRouterClient()
    var apple: StreetRouting = MapKitRouter()
    var roads = RoadDataStore.shared
    var rain = RainService()

    /// S-Bahn/regional stations considered at each end of a bike+rail trip.
    /// 3 × 4 + 3 × 3 = 21 HAFAS searches per refresh — each ~0.2 s, in parallel.
    var originStationCount = 3
    var destinationStationCount = 4
    /// Nearest stations of any kind (incl. U-Bahn-only) for the alternative search.
    var alternativeStationCount = 2
    /// Plus the nearest tram stop at each end: where the tram is the direct
    /// line (M10, M1, the east), the way to the next S/U station is a detour.
    /// Asked for separately — the dense tram stops would otherwise crowd the
    /// S-Bahn stations out of the twenty nearest.
    var tramStationCount = 1

    /// `onProgress` bekommt den Stand nach jedem Modus — schon sortiert und
    /// mit Empfehlung, damit der Bildschirm ihn unverändert zeigen kann.
    ///
    /// Gefragt wird weiter alles gleichzeitig; gewartet wird in der
    /// Reihenfolge aus den Einstellungen. Steht das Rad dort oben, steht es
    /// nach einer Sekunde auf dem Bildschirm und die Bahn kommt nach — vorher
    /// stand alles auf „sucht …", bis der langsamste Dienst geantwortet hatte.
    /// `only` fragt **eine** Kategorie und lässt die anderen drei ungefragt.
    /// Dafür gibt es genau einen Fall: die im Hintergrund geweckte App stellt
    /// ihre Warnungen auf die Verbindung nach, auf die der Countdown zählt —
    /// und holte bis 1.3 dafür drei Radrouten, eine Autoroute, sechzehn
    /// Bahnhofspaare und die Regenvorhersage mit, die kein Mensch je sah.
    func plan(_ req: PlanRequest, only: TravelMode? = nil,
              onProgress: (@MainActor @Sendable (PlanResult) -> Void)? = nil) async -> PlanResult {
        let wanted = { (mode: TravelMode) in only == nil || only == mode }
        async let bike = capture(wanted(.bike)) { try await bikeOptions(req) }
        async let car = capture(wanted(.car)) { try await carOptions(req) }
        async let transit = capture(wanted(.transit)) { try await transitOptions(req) }
        async let bikeTransit = capture(wanted(.bikeTransit)) { try await bikeTransitOptions(req) }

        var result = PlanResult()
        // Dieselbe Liste, die auch die Kästen anordnet: was oben steht, wird
        // zuerst gezeigt. `modeOrder` enthält immer alle vier.
        for mode in req.settings.modeOrder {
            let outcome = switch mode {
            case .bike: await bike
            case .car: await car
            case .bikeTransit: await bikeTransit
            case .transit: await transit
            }
            switch outcome {
            case .success(let options):
                // Auch Bahn und Rad + Bahn: die eingestellte Zahl gilt für
                // jedes Verkehrsmittel. Bei den Fahrplänen sind es die
                // nächsten Abfahrten, bei Rad und Auto die obersten Rollen.
                result.options += options.prefix(Swift.max(1, req.settings.optionsPerMode))
            case .failure(let error): result.failures[mode] = error.localizedDescription
            }
            Self.settle(&result, req)
            await onProgress?(result)
        }

        // Der Regen zum Schluss, in **einer** Anfrage für alle Möglichkeiten.
        // Je Modus zu fragen wären vier Anfragen für dieselbe Auskunft. Für
        // die geweckte App gar nicht: sie stellt eine Weckzeit nach, und dafür
        // ist es gleich, ob es regnet.
        guard only == nil else {
            Self.settle(&result, req)
            return result
        }
        do {
            try await attachRain(&result.options)
        } catch {
            result.rainFailure = L("Regenvorhersage nicht verfügbar: %@", error.localizedDescription)
        }
        Self.settle(&result, req)
        return result
    }

    /// Fixpunkte prüfen, sortieren, empfehlen — auf dem Stand, der gerade da
    /// ist. Ein Zwischenstand ist damit genauso vollständig beschrieben wie
    /// das Endergebnis, nur mit weniger Möglichkeiten darin.
    private static func settle(_ result: inout PlanResult, _ req: PlanRequest) {
        for i in result.options.indices {
            result.options[i].passesWaypoints = WaypointMatcher.passes(
                result.options[i], waypoints: req.settings.waypoints,
                requireAll: req.settings.requireAllWaypoints, radius: req.settings.waypointRadius)
        }
        let penalty = req.settings.transferPenalty
        let order = req.settings.modeOrder
        // `arrival`: bei „um 9 da sein" gewinnt die **späteste Abfahrt**, nicht
        // die früheste Ankunft. Ohne das stand der Zug um 7:40 über dem um
        // 8:20, obwohl beide rechtzeitig ankommen.
        result.options.sort { ranking($0, $1, penalty: penalty, arrival: req.isArrival, order: order) }
        result.recommendation = recommend(result.options, penalty: penalty, order: order,
                                          rainSwitch: req.settings.rainSwitchLevel)
    }

    private func capture(_ wanted: Bool = true,
                         _ work: () async throws -> [TripOption]) async -> Result<[TripOption], Error> {
        guard wanted else { return .success([]) }
        do { return .success(try await work()) } catch { return .failure(error) }
    }

    // MARK: Modes

    /// Whole way by bike, as up to `optionsPerMode` distinct routes, one per
    /// role in the user's own order (optimal, schnellst, kürzest, wenig Autos,
    /// wenig Halts). Candidates come from BRouter profiles — Apple Maps only
    /// when cobbles are allowed or BRouter does not answer;
    /// OpenStreetMap data then counts traffic lights, large roads crossed and
    /// metres beside large roads for each. Riding time includes an expected
    /// wait at every light.
    func bikeOptions(_ req: PlanRequest) async throws -> [TripOption] {
        let (o, d) = (req.origin.coordinate, req.destination.coordinate)
        let via = WaypointRouting.via(req.settings.waypoints, from: o, to: d)
        // Was dieser Fahrer hier schon gefahren ist — und, ab zwei Fahrten,
        // die typische davon als Punkte zum Nachfahren.
        let ridden = await habits.matching(from: o, to: d)
        let habitVia = RiddenPaths.typical(ridden).map {
            WaypointRouting.ordered(RiddenPaths.via($0) + via, from: o, to: d)
        }
        let n = Swift.max(1, req.settings.optionsPerMode)
        let order = req.settings.bikeVariantOrder.filter { $0 != .alternative }
        func requests(for roles: some Sequence<BikeVariant>) -> [BikeLineSource] {
            roles.compactMap { v in
                switch v {
                case .balanced: .brouter(.trekking)
                case .fastest: .brouter(.fastbike)
                case .shortest: .brouter(.shortest)
                case .quiet: .brouter(.quiet)
                case .lowTraffic: .brouter(.lowTraffic)
                case .alternative: nil
                }
            }
        }
        // Höchstens so viele Anfragen gleichzeitig an BRouter. Der öffentliche
        // Server ist ein Geschenk und keine Infrastruktur: wirft man ihm acht
        // Anfragen auf einmal hin, antwortet er mit `403 Please, retry later!`
        // — und weil ein Fehlschlag hier nur eine fehlende Möglichkeit ist und
        // keinen Fehler, verschwanden die Varianten stillschweigend. Apple
        // zählt nicht mit, das ist ein anderer Dienst.
        var br = brouter
        br.avoidCobbles = req.settings.avoidCobbles
        let brouter = br
        func fetch(_ list: [BikeLineSource]) async -> [(BikeLineSource, StreetRoute)] {
            await Self.gathered(list, atOnce: 3) { source in
                if case .brouter(let profile) = source {
                    return try? await brouter.route(from: o, to: d, via: via, profile: profile)
                }
                return try? await apple.route(from: o, to: d, mode: .bike, departure: nil)
            }
        }
        func judge(_ found: [(BikeLineSource, StreetRoute)], _ data: RoadData?) async -> [BikeCandidate] {
            // 63 ms per route, six routes: serially that is 378 ms of the plan
            // for nothing. They do not depend on each other.
            await withTaskGroup(of: (Int, BikeCandidate).self) { group in
                for (i, (name, route)) in found.enumerated() {
                    group.addTask {
                        (i, BikeCandidate(source: name, route: route,
                                          stats: data.map { RouteAnalyzer.analyze(route.coordinates, roads: $0) },
                                          familiar: RiddenPaths.familiarShare(route.coordinates, ridden: ridden)))
                    }
                }
                var out: [(Int, BikeCandidate)] = []
                for await pair in group { out.append(pair) }
                return out.sorted { $0.0 < $1.0 }.map(\.1)
            }
        }

        // **Nur holen, was jemand sehen will** — zuerst. Jede Rolle braucht
        // ein bestimmtes BRouter-Profil, und die obersten `n` Rollen der
        // eigenen Reihenfolge sind, was gezeigt werden soll.
        // Apple Karten kennt keinen Belag: wer Pflaster meiden will (die
        // Voreinstellung), bekommt dessen Linie nur, wenn BRouter gar nicht
        // antwortet — und dann wird sie auch erst gefragt. Bis 1.9.1 kam sie
        // bei jeder Planung mit und wurde gleich wieder weggeworfen.
        let appleLine: [BikeLineSource] = [.apple]
        let asked = (req.settings.avoidCobbles ? [] : appleLine) + requests(for: order.prefix(n))
        var found = await fetch(asked)
        if req.settings.avoidCobbles, found.isEmpty {
            found = await fetch(appleLine)
        }
        // Die eigene typische Fahrt, sauber nachgefahren: danach, nicht
        // daneben — der Server will höchstens drei Anfragen gleichzeitig.
        if let habitVia, !found.isEmpty,
           let usual = try? await brouter.route(from: o, to: d, via: habitVia, profile: .trekking) {
            found.append((.habit, usual))
        }
        guard !found.isEmpty else { throw PlannerError.noBikeRoute }
        var data = Self.withLearned(try? await roads.data(covering: found.flatMap { $0.1.coordinates }), req.settings)
        var candidates = await judge(found, data)
        var picked = BikeCandidate.pick(candidates, settings: req.settings, fill: false)
        // **Eine Route ist immer doof.** Gewinnt eine Linie mehrere der
        // obersten Rollen, bleiben Plätze frei — dann geht es die eigene
        // Reihenfolge weiter hinunter (Nutzer, 28.09.2026: „kürzest, wenig
        // Halts, schnellst"), mit den Profilen, die dafür noch fehlen. Erst
        // wenn auch das keinen anderen Weg bringt, füllt eine „Alternative".
        if picked.count < n {
            let more = requests(for: order.dropFirst(n)).filter { !asked.contains($0) }
            if !more.isEmpty {
                let extra = await fetch(more)
                if !extra.isEmpty {
                    found += extra
                    data = Self.withLearned(try? await roads.data(covering: found.flatMap { $0.1.coordinates }), req.settings)
                    candidates = await judge(found, data)
                }
            }
        }
        picked = BikeCandidate.pick(candidates, settings: req.settings)
        // Kam von BRouter gar nichts, steht nur Apples eine Linie da — dann
        // gibt es eine Variante statt fünf, und der Nutzer soll wissen, warum.
        let brouterAnswered = found.contains { $0.0 != .apple }

        return picked.enumerated().map { index, entry in
            let (c, variants) = entry
            let ride = c.time(req.settings)
            // Nie vor „frühestens los": eine Zielzeit, die schon vorbei ist,
            // ergab bisher eine Abfahrt in der Vergangenheit und einen
            // Countdown, der rückwärts lief.
            let leave = req.arriveBy.map { Swift.max($0.addingTimeInterval(-ride), req.earliestLeave) }
                ?? req.earliestLeave
            let leg = Leg(kind: .bike, fromName: req.origin.shortName, toName: req.destination.shortName,
                          departure: leave, arrival: leave.addingTimeInterval(ride),
                          distance: c.route.distance, coordinates: c.route.coordinates)
            var option = TripOption(mode: .bike, legs: [leg], prep: req.settings.prep,
                                    note: Self.bikeNote(roadData: data, brouterMissing: !brouterAnswered,
                                                        km: c.route.distance / 1000, settings: req.settings),
                                    bikeRoute: BikeRouteInfo(variants: variants, stats: c.stats, source: c.source,
                                                             mix: c.route.mix,
                                                             roadPoints: c.route.roadPoints,
                                                             ascent: c.route.ascent,
                                                             measuredKmh: c.measuredWins(req.settings)
                                                                 ? req.settings.measuredOverallKmh : nil,
                                                             familiar: c.familiar,
                                                             via: c.source == .habit ? habitVia ?? via
                                                                 : c.source == .apple ? [] : via))
            // Only the route that matches the user's first choice is the one
            // the recommendation weighs; the others are alternatives.
            option.isPreferredVariant = index == 0
            return option
        }
    }

    /// Läuft die Liste ab, aber nie mehr als `atOnce` gleichzeitig. Die
    /// Reihenfolge der Antworten ist wieder die der Liste — sie entscheidet,
    /// welche Route bei Gleichstand eine Rolle bekommt.
    static func gathered<T: Sendable>(_ items: [T], atOnce: Int,
                                      _ run: @escaping @Sendable (T) async -> StreetRoute?)
        async -> [(T, StreetRoute)] {
        var out: [(Int, StreetRoute)] = []
        await withTaskGroup(of: (Int, StreetRoute?).self) { group in
            var next = 0
            func add() {
                guard next < items.count else { return }
                let (i, item) = (next, items[next])
                next += 1
                group.addTask { (i, await run(item)) }
            }
            for _ in 0..<Swift.min(atOnce, items.count) { add() }
            for await (i, r) in group {
                if let r { out.append((i, r)) }
                add()
            }
        }
        return out.sorted { $0.0 < $1.0 }.map { (items[$0.0], $0.1) }
    }

    /// Was unter der Radroute steht, wenn etwas fehlte. Beides kann zutreffen;
    /// dann wiegt die fehlende Route schwerer — sie kostet Möglichkeiten,
    /// nicht nur Genauigkeit.
    static func bikeNote(roadData: RoadData?, brouterMissing: Bool, km: Double,
                         settings: PlanSettings) -> String? {
        if brouterMissing { return L("Nur die Route von Apple Karten — BRouter antwortet gerade nicht") }
        guard roadData == nil else { return nil }
        return noRoadDataNote(km: km, settings: settings)
    }

    /// OpenStreetMap's lit junctions plus the ones this rider has ridden
    /// through. `RouteAnalyzer` merges signal nodes within 60 m, so a learned
    /// light sitting on top of a mapped one does not count twice — and where
    /// the two are the same junction, the measured one wins.
    static func withLearned(_ data: RoadData?, _ settings: PlanSettings) -> RoadData? {
        guard var data, !settings.learnedSignals.isEmpty else { return data }
        data.learned = settings.learnedSignals
        return data
    }

    /// Why a route has no traffic-light count: too long to ask Overpass for,
    /// or Overpass simply did not answer.
    static func noRoadDataNote(km: Double, settings: PlanSettings) -> String {
        km > settings.longTripKm
            ? L("Ampeln und Hauptstraßen auf dieser Länge nicht gezählt")
            : L("Ampeln und Hauptstraßen unbekannt — OpenStreetMap antwortete nicht, wird im Hintergrund nachgeholt")
    }

    /// The car as the two or three lines Apple actually offers, labelled the
    /// way the bike routes are: schnellst (the default), kürzest, wenig Ampeln.
    /// The lights come from the same OpenStreetMap data the bike routes use —
    /// on a commute that is the difference between the autobahn detour and the
    /// straight run through town.
    func carOptions(_ req: PlanRequest) async throws -> [TripOption] {
        let guess = req.arriveBy ?? req.earliestLeave
        let moto = req.settings.motorcycle
        // Fürs Motorrad dieselbe Frage noch einmal für nachts um drei: was
        // Apple dann braucht, ist die Fahrzeit ohne Stau. Parallel, und ein
        // Fehler kostet nur den Abzug, nicht die Route.
        async let nightRoutes: [StreetRoute] = moto
            ? ((try? await apple.routes(from: req.origin.coordinate, to: req.destination.coordinate,
                                        mode: .car, departure: Self.freeFlowDeparture(after: guess))) ?? [])
            : []
        let found = try await apple.routes(from: req.origin.coordinate, to: req.destination.coordinate,
                                           mode: .car, departure: guess)
            // Two lines that differ by a hundred metres are one line.
            .reduce(into: [StreetRoute]()) { out, r in
                guard !out.contains(where: { abs($0.distance - r.distance) < 100
                                          && abs($0.expectedTravelTime - r.expectedTravelTime) < 60 }) else { return }
                out.append(r)
            }
        let night = await nightRoutes
        let free = CarCandidate.freeFlow(day: found, night: night)
        let data = Self.withLearned(try? await roads.data(covering: found.flatMap(\.coordinates)), req.settings)
        let candidates = zip(found, free).map { route, freeFlow in
            CarCandidate(route: route,
                         stats: data.map { RouteAnalyzer.analyze(route.coordinates, roads: $0) },
                         freeFlow: freeFlow)
        }
        // Das Motorrad steht vor der Tür; der Auto-Schnitt ist mit dem Auto
        // gemessen und gilt für es nicht.
        let parking = moto ? 0 : TimeInterval(req.settings.parkingMinutes * 60)
        let carKmh = moto ? nil : req.settings.carOverallKmh
        return CarCandidate.pick(candidates, settings: req.settings, order: req.settings.carVariantOrder).enumerated().map { index, entry in
            let (c, variants) = entry
            // Nie schneller, als dieser Fahrer laut seinen Autofahrten
            // Tür zu Tür ist — Parkplatzsuche eingeschlossen.
            let apple = c.driveTime(req.settings) + parking
            let own = carKmh.map { c.route.distance / ($0 / 3.6) } ?? 0
            let drive = Swift.max(apple, own.rounded())
            let leave = req.arriveBy.map { $0.addingTimeInterval(-drive) } ?? req.earliestLeave
            let leg = Leg(kind: .car, fromName: req.origin.shortName, toName: req.destination.shortName,
                          departure: leave, arrival: leave.addingTimeInterval(drive),
                          distance: c.route.distance, coordinates: c.route.coordinates)
            let saved = Int((c.queueSaving(req.settings) / 60).rounded())
            let note = moto ? Self.motorcycleNote(saved: saved, known: c.freeFlow != nil)
                : own > apple ? L("nach deinem Auto-Schnitt von %@", Fmt.kmh(carKmh ?? 0))
                : parking > 0 ? L("inkl. %d min Parkplatzsuche", req.settings.parkingMinutes)
                : L("Fahrzeit laut Apple Karten mit Verkehrslage")
            var option = TripOption(mode: .car, legs: [leg], prep: req.settings.prep, note: note,
                                    carRoute: CarRouteInfo(variants: variants, signals: c.stats?.signals,
                                                           signalPoints: c.stats?.signalPoints ?? []))
            option.isPreferredVariant = index == 0
            return option
        }
    }

    /// Wann auf dieser Strecke kein Verkehr ist: die nächste Nacht um drei.
    static func freeFlowDeparture(after date: Date, calendar: Calendar = .current) -> Date {
        calendar.nextDate(after: date, matching: DateComponents(hour: 3, minute: 0),
                          matchingPolicy: .nextTime) ?? date.addingTimeInterval(12 * 3600)
    }

    static func motorcycleNote(saved minutes: Int, known: Bool) -> String {
        guard known else { return L("Fahrzeit laut Apple Karten — Stau unbekannt, nichts abgezogen") }
        return minutes > 0 ? L("Motorrad: %d min Stau vorbeigerollt", minutes)
            : L("Fahrzeit laut Apple Karten — kein Stau auf der Strecke")
    }

    func transitOptions(_ req: PlanRequest) async throws -> [TripOption] {
        let journeys = try await source(req) == .transitous
            ? motis.journeys(from: req.origin.coordinate, to: req.destination.coordinate,
                             at: req.arriveBy ?? req.earliestLeave, arriveBy: req.isArrival,
                             access: .walk, results: 4)
            // HAFAS routes on the coordinate; the name is only display text it
            // echoes back. Sending the street and house number would tell the
            // timetable more about the user than it needs to answer.
            : hafas.journeys(
            from: .address(name: "Start", coordinate: req.origin.coordinate),
            to: .address(name: "Ziel", coordinate: req.destination.coordinate),
            departing: req.arriveBy ?? req.earliestLeave, arriveBy: req.isArrival,
            bikeCarriage: false, results: 4)
        let penalty = req.settings.transferPenalty
        let running = journeys.filter { !$0.contains(where: \.cancelled) }
        var options = running.map { TripOption(mode: .transit, legs: $0, prep: req.settings.prep) }
        if let by = req.arriveBy {
            let limit = by.addingTimeInterval(60)
            options = options.filter { $0.arrival <= limit }
        }
        options.sort { TripPlanner.ranking($0, $1, penalty: penalty, arrival: req.isArrival,
                                           order: req.settings.modeOrder) }
        return Array(options.prefix(3))
    }

    /// Which timetable answers for this request.
    func source(_ req: PlanRequest) -> TimetableSource {
        TimetableSource.resolved(from: req.origin.coordinate, to: req.destination.coordinate)
    }

    /// Bike at both ends, planned by Transitous in one request: MOTIS routes
    /// intermodally, so it picks the stations itself and the app does not have
    /// to try up to twenty-one station pairs as it does with HAFAS.
    func motisBikeTransitOptions(_ req: PlanRequest) async throws -> [TripOption] {
        let s = req.settings
        let journeys = try await motis.journeys(from: req.origin.coordinate, to: req.destination.coordinate,
                                                at: req.arriveBy ?? req.earliestLeave,
                                                arriveBy: req.isArrival, access: .bike, results: 5)
        let usable = journeys.filter { legs in
            let transit = legs.filter(\.isTransit)
            return !transit.isEmpty && transit.allSatisfy({ !$0.cancelled })
                && transit.allSatisfy({ s.carriage($0) != .no })
                && legs.contains(where: { $0.kind == .bike })
        }
        // Die Radstücke mit dem eigenen Zeitmodell, wie bei HAFAS — dafür
        // braucht es die Ampeln an ihnen. Ohne sie bliebe nur Rolltempo ohne
        // Wartezeit, und das ist optimistischer als Transitous' eigene
        // Schätzung; dann gilt die.
        let bikeLines = usable.flatMap { $0.filter { $0.kind == .bike }.flatMap(\.coordinates) }
        let data = bikeLines.isEmpty ? nil
            : Self.withLearned(try? await roads.data(covering: bikeLines), s)
        let options = usable.compactMap { legs -> TripOption? in
            let timed = Self.retimed(s.decided(legs), roads: data, settings: s)
            let option = TripOption(mode: .bikeTransit, legs: timed, prep: s.prep,
                                    note: data == nil ? L("Fahrten von Transitous; Radzeiten nach deren Schätzung")
                                                      : L("Fahrten von Transitous"))
            // Mit dem eigenen Tempo kann der Weg zum ersten Zug länger
            // werden als Transitous dachte — dann reicht die Zeit nicht.
            if let by = req.arriveBy { return option.arrival <= by.addingTimeInterval(60) ? option : nil }
            return option.leave >= req.earliestLeave.addingTimeInterval(-30) ? option : nil
        }
        return BikeTransitComposer.rank(options, preferred: 3, alternatives: 1,
                                        penalty: s.transferPenalty, arrival: req.isArrival)
    }

    /// Die Radstücke einer Transitous-Fahrt nach dem eigenen Zeitmodell
    /// (`PlanSettings.rideTime`): das vor dem ersten Zug endet, wo es endet,
    /// und beginnt entsprechend früher oder später; das nach dem letzten
    /// beginnt, wo es beginnt. Ohne Straßendaten bleibt alles, wie es kam.
    static func retimed(_ legs: [Leg], roads: RoadData?, settings s: PlanSettings) -> [Leg] {
        guard let roads, let first = legs.firstIndex(where: \.isTransit),
              let last = legs.lastIndex(where: \.isTransit) else { return legs }
        return legs.enumerated().map { i, leg in
            guard leg.kind == .bike, i < first || i > last,
                  let meters = leg.length, leg.coordinates.count > 1 else { return leg }
            let st = RouteAnalyzer.analyze(leg.coordinates, roads: roads)
            let t = s.rideTime(meters: meters, signals: st.signals, learned: st.learnedSignals,
                               measured: .slowerOnly)
            var l = leg
            if i < first { l.departure = leg.arrival.addingTimeInterval(-t) }
            else { l.arrival = leg.departure.addingTimeInterval(t) }
            return l
        }
    }

    /// Ride to a station, take only trains that carry bikes, ride on from the
    /// arrival station. The app does the station choice itself: VBB's HAFAS has
    /// a "bike & ride" mode in its web app, but the mgate request for it is not
    /// documented, and with address endpoints plus the bike filter it finds nothing.
    ///
    /// S-Bahn and regional trains first — they always have a bike compartment.
    /// The main search uses only S/RE stations and S/RE trains; a small second
    /// search from the nearest stations of any kind lets U-Bahn/tram in, and
    /// those results are kept only as the alternative.
    func bikeTransitOptions(_ req: PlanRequest) async throws -> [TripOption] {
        guard source(req) == .vbb else { return try await motisBikeTransitOptions(req) }
        let s = req.settings
        let radius = s.maxBikeToStationKm * 1000
        async let fromList = hafas.nearbyStations(around: req.origin.coordinate, radius: radius)
        async let toList = hafas.nearbyStations(around: req.destination.coordinate, radius: radius)
        async let fromTramList = hafas.nearbyStations(around: req.origin.coordinate, radius: radius,
                                                      productMask: TransitProduct.tram.rawValue)
        async let toTramList = hafas.nearbyStations(around: req.destination.coordinate, radius: radius,
                                                    productMask: TransitProduct.tram.rawValue)
        let fromAll = try await fromList, toAll = try await toList
        // A missing tram stop only costs the tram alternative, not the trip.
        let fromTram = (try? await fromTramList) ?? [], toTram = (try? await toTramList) ?? []

        var searches: [(from: Station, to: Station, mask: Int)] = []
        let preferredMask = TransitProduct.bikeCompartmentMask
        for a in fromAll.filter(\.hasBikeCompartment).prefix(originStationCount) {
            for b in toAll.filter(\.hasBikeCompartment).prefix(destinationStationCount) {
                searches.append((a, b, preferredMask))
            }
        }
        let fromAlt = unique(Array(fromAll.prefix(alternativeStationCount) + fromTram.prefix(tramStationCount)))
        let toAlt = unique(Array(toAll.prefix(alternativeStationCount) + toTram.prefix(tramStationCount)))
        for a in fromAlt {
            for b in toAlt {
                searches.append((a, b, TransitProduct.bikeSearchMask))
            }
        }
        searches.removeAll { $0.from.lid == $0.to.lid }
        guard !searches.isEmpty else { throw PlannerError.noStations(km: s.maxBikeToStationKm) }

        let starts = unique(searches.map(\.from)), ends = unique(searches.map(\.to))
        var (firstLegs, lastLegs) = await feederRoutes(origin: req.origin.coordinate, starts: starts.map(\.coordinate),
                                                       destination: req.destination.coordinate,
                                                       ends: ends.map(\.coordinate), avoidCobbles: s.avoidCobbles)
        // Same traffic-light wait as on the whole-way bike routes.
        let rides = (firstLegs + lastLegs).compactMap { $0 }
        if !rides.isEmpty, let data = try? await roads.data(covering: rides.flatMap(\.coordinates)) {
            let withSignals = { (r: StreetRoute?) -> StreetRoute? in
                r.map { r in
                    var r = r
                    let st = RouteAnalyzer.analyze(r.coordinates, roads: data)
                    r.signals = st.signals
                    r.learnedSignals = st.learnedSignals
                    return r
                }
            }
            firstLegs = firstLegs.map(withSignals)
            lastLegs = lastLegs.map(withSignals)
        }
        let ride1 = Dictionary(uniqueKeysWithValues: zip(starts.map(\.lid), firstLegs))
        let ride2 = Dictionary(uniqueKeysWithValues: zip(ends.map(\.lid), lastLegs))

        let candidates = try await withThrowingTaskGroup(of: [TripOption].self) { group in
            for (a, b, mask) in searches {
                guard let r1 = ride1[a.lid] ?? nil, let r2 = ride2[b.lid] ?? nil else { continue }
                group.addTask {
                    // An arrival search counts backwards: be at the last station
                    // in time for the final stretch on the bike.
                    let when = req.arriveBy.map { $0.addingTimeInterval(-s.rideTime(r2) - s.bikeStationBuffer) }
                        ?? req.earliestLeave.addingTimeInterval(s.rideTime(r1) + s.bikeStationBuffer)
                    let journeys = try await hafas.journeys(from: .station(lid: a.lid), to: .station(lid: b.lid),
                                                            departing: when, arriveBy: req.isArrival,
                                                            bikeCarriage: true, productMask: mask, results: 2)
                    return journeys.compactMap {
                        BikeTransitComposer.compose(origin: req.origin, destination: req.destination,
                                                    station1: a.name, ride1: r1, journey: $0,
                                                    station2: b.name, ride2: r2, settings: s,
                                                    earliestLeave: req.isArrival ? .distantPast : req.earliestLeave)
                    }
                }
            }
            return try await group.reduce(into: []) { $0 += $1 }
        }
        let inTime = req.arriveBy.map { by in candidates.filter { $0.arrival <= by.addingTimeInterval(60) } } ?? candidates
        return BikeTransitComposer.rank(inTime, preferred: 3, alternatives: 1,
                                        penalty: s.transferPenalty, arrival: req.isArrival)
    }

    typealias Station = HafasClient.Station

    private func unique(_ stations: [Station]) -> [Station] {
        var seen = Set<String>()
        return stations.filter { seen.insert($0.lid).inserted }
    }

    /// Die Zubringer an beiden Enden, nil, wo keiner gefunden wurde: `first`
    /// vom Start zu jedem Bahnhof, `last` von jedem Bahnhof zum Ziel.
    ///
    /// In **einer** Liste und höchstens drei zugleich, wie die Radrouten. Bis
    /// 1.9.1 gingen alle auf einmal hinaus, beide Enden nebeneinander — bis zu
    /// dreizehn Anfragen an BRouter, der ab acht mit 403 antwortet. Mit der
    /// Pflasterregel aus den Einstellungen; vorher fuhren die Zubringer über
    /// jedes Kopfsteinpflaster, das die ganze Radroute mied.
    func feederRoutes(origin: CLLocationCoordinate2D, starts: [CLLocationCoordinate2D],
                              destination: CLLocationCoordinate2D, ends: [CLLocationCoordinate2D],
                              avoidCobbles: Bool) async -> (first: [StreetRoute?], last: [StreetRoute?]) {
        let pairs = starts.map { (origin, $0) } + ends.map { ($0, destination) }
        let streets = streets
        let found = await Self.gathered(Array(pairs.indices), atOnce: 3) { i in
            try? await streets.feeder(from: pairs[i].0, to: pairs[i].1, avoidCobbles: avoidCobbles)
        }
        var out = [StreetRoute?](repeating: nil, count: pairs.count)
        for (i, route) in found { out[i] = route }
        return (Array(out.prefix(starts.count)), Array(out.dropFirst(starts.count)))
    }

    // MARK: Rain

    private func attachRain(_ options: inout [TripOption]) async throws {
        let perOption = options.map { opt in
            opt.bikeLegs.flatMap { RainSampler.samples(along: $0.coordinates, departure: $0.departure, arrival: $0.arrival) }
        }
        let all = perOption.flatMap { $0 }
        guard !all.isEmpty else { return }
        let readings = try await rain.readings(for: all)
        var k = 0
        for i in options.indices where !perOption[i].isEmpty {
            options[i].rain = RainAssessment(readings: Array(readings[k..<(k + perOption[i].count)]))
            k += perOption[i].count
        }
    }

    // MARK: Ranking

    /// Earliest arrival first, each change of train counted as `penalty`;
    /// within 3 minutes the more active mode first.
    /// `order` is the user's list of modes: it decides which one wins when two
    /// trips arrive within three minutes of each other.
    static func ranking(_ a: TripOption, _ b: TripOption, penalty: TimeInterval = 600,
                        arrival: Bool = false,
                        order: [TravelMode] = TravelMode.defaultOrder) -> Bool {
        if a.passesWaypoints != b.passesWaypoints { return a.passesWaypoints }
        // Leaving as late as possible is the point of an arrival search.
        let wa = score(a, penalty: penalty, arrival: arrival)
        let wb = score(b, penalty: penalty, arrival: arrival)
        if abs(wa - wb) < 180, a.mode != b.mode {
            return rank(a.mode, order) < rank(b.mode, order)
        }
        return wa < wb
    }

    static func rank(_ mode: TravelMode, _ order: [TravelMode]) -> Int {
        order.firstIndex(of: mode) ?? order.count
    }

    private static func score(_ o: TripOption, penalty: TimeInterval, arrival: Bool) -> Double {
        let d = arrival ? o.weightedLeave(penalty) : o.weightedArrival(penalty)
        return arrival ? -d.timeIntervalSince1970 : d.timeIntervalSince1970
    }

    /// The user's own rule, as far as the settings let it be one: dry → ride
    /// (the whole way, or with the train if that arrives earlier); wet → bike
    /// in the train, which keeps the time in the rain short; everything else in
    /// the order the user put the modes in. "Dry" and the order both come from
    /// the settings — `rainSwitch` is the level at which the bike goes into the
    /// train, `order` decides the ties.
    static func recommend(_ options: [TripOption], penalty: TimeInterval = 600,
                          order: [TravelMode] = TravelMode.defaultOrder,
                          rainSwitch: RainLevel = .light) -> Recommendation? {
        let arrival = { (o: TripOption) in o.weightedArrival(penalty) }
        let level = { (o: TripOption) in o.rain?.level ?? .dry }
        let preferredBike = { (o: TripOption) in o.mode == .bike && o.isPreferredVariant }
        // U-Bahn/tram connections only count when no S-Bahn/regional one exists.
        let onRoute = options.filter(\.passesWaypoints)
        let bikeTrains = (onRoute.isEmpty ? options : onRoute).filter { $0.mode == .bikeTransit && !$0.isAlternative }
        // The fallback stays inside the fixed points too — it used to reach
        // past them while the line below promised it would not.
        let anyBikeTransit = (onRoute.isEmpty ? options : onRoute).filter { $0.mode == .bikeTransit }
        let bikeTransit = bikeTrains.isEmpty ? anyBikeTransit : bikeTrains
        // Trips that miss the fixed points are never recommended while others exist.
        let options = options.contains(where: \.passesWaypoints) ? options.filter(\.passesWaypoints) : options
        let bikeish = options.filter(preferredBike) + bikeTransit
        let dry = bikeish.filter { level($0) < rainSwitch }

        if let pick = dry.min(by: { ranking($0, $1, penalty: penalty, order: order) }) {
            let reason = pick.mode == .bike
                ? "Radstrecke \(pick.rain?.summary ?? "ohne Regendaten")"
                : L("trocken und mit der Bahn schneller als die ganze Strecke per Rad")
            return Recommendation(optionID: pick.id, reason: reason)
        }
        if let pick = bikeTransit
            .min(by: { (level($0), arrival($0)) < (level($1), arrival($1)) }) {
            let wet = options.first(where: preferredBike)?.rain?.summary
            return Recommendation(optionID: pick.id,
                                  reason: L("Regen auf der Radstrecke%@ — Rad in die Bahn",
                                            wet.map { " (\($0))" } ?? ""))
        }
        // No connection that takes the bike: fall back in the user's own order,
        // minus bike + rail, which just had its turn.
        for mode in order where mode != .bikeTransit {
            if let pick = options.filter({ $0.mode == mode }).min(by: { arrival($0) < arrival($1) }) {
                return Recommendation(optionID: pick.id, reason: L("keine Verbindung mit Radmitnahme gefunden"))
            }
        }
        return nil
    }

    enum PlannerError: LocalizedError {
        case noStations(km: Double)
        case noBikeRoute
        var errorDescription: String? {
            switch self {
            case .noStations(let km): L("Kein Bahnhof mit Radmitnahme im Umkreis von %d km", Int(km))
            case .noBikeRoute: L("Keine Radroute gefunden (Apple Karten und BRouter)")
            }
        }
    }
}

/// Pure composition of a bike+rail trip, split out for tests.
enum BikeTransitComposer {
    static func compose(origin: Place, destination: Place,
                        station1: String, ride1: StreetRoute, journey: [Leg],
                        station2: String, ride2: StreetRoute,
                        settings s: PlanSettings, earliestLeave: Date) -> TripOption? {
        let transit = journey.filter(\.isTransit)
        guard let firstTrain = transit.first, let lastTrain = transit.last,
              transit.allSatisfy({ !$0.cancelled }) else { return nil }
        // A line the user has ruled out is out. One nobody has judged stays in,
        // with the warning — that is the whole point of the list.
        guard transit.allSatisfy({ s.carriage($0) != .no }) else { return nil }

        // Leave as late as still catches the first train. Walk legs HAFAS puts
        // in front (platform changes inside the station) count as buffer.
        let boardBy = journey.first?.departure ?? firstTrain.departure
        let ride1Time = s.rideTime(ride1)
        let leave = boardBy.addingTimeInterval(-s.bikeStationBuffer - ride1Time)
        guard leave >= earliestLeave.addingTimeInterval(-30) else { return nil }

        let alight = journey.last?.arrival ?? lastTrain.arrival
        let ride2Start = alight.addingTimeInterval(s.bikeStationBuffer)

        let first = Leg(kind: .bike, fromName: origin.shortName, toName: station1,
                        departure: leave, arrival: leave.addingTimeInterval(ride1Time),
                        distance: ride1.distance, coordinates: ride1.coordinates)
        let last = Leg(kind: .bike, fromName: station2, toName: destination.shortName,
                       departure: ride2Start, arrival: ride2Start.addingTimeInterval(s.rideTime(ride2)),
                       distance: ride2.distance, coordinates: ride2.coordinates)
        return TripOption(mode: .bikeTransit, legs: [first] + s.decided(journey) + [last], prep: s.prep,
                          note: L("%d min Puffer je Bahnhof fürs Rad", s.bikeStationBufferMinutes))
    }

    /// The best S-Bahn/regional connections, plus U-Bahn/tram ones only as the
    /// alternative: at most `alternatives` of them, or up to `preferred` when no
    /// S-Bahn/regional connection exists at all.
    static func rank(_ options: [TripOption], preferred: Int, alternatives: Int,
                     penalty: TimeInterval = 600, arrival: Bool = false) -> [TripOption] {
        let main = best(options.filter { !$0.isAlternative }, count: preferred, penalty: penalty, arrival: arrival)
        let alt = best(options.filter(\.isAlternative), count: main.isEmpty ? preferred : alternatives,
                       penalty: penalty, arrival: arrival)
        return main + alt
    }

    /// Drop duplicates (same trains reached from different stations — keep the
    /// one that leaves latest), then earliest arrival with each change of
    /// train counted as `penalty`, then latest leave.
    static func best(_ options: [TripOption], count: Int, penalty: TimeInterval = 600,
                     arrival: Bool = false) -> [TripOption] {
        var bySignature: [String: TripOption] = [:]
        for o in options {
            let key = o.transitLegs.map { "\($0.lineName ?? "")@\(Int($0.departure.timeIntervalSince1970))" }.joined(separator: "|")
            if let existing = bySignature[key],
               (existing.arrival, -existing.leave.timeIntervalSince1970) <= (o.arrival, -o.leave.timeIntervalSince1970) {
                continue
            }
            bySignature[key] = o
        }
        return bySignature.values
            .sorted { TripPlanner.ranking($0, $1, penalty: penalty, arrival: arrival) }
            .prefix(count).map { $0 }
    }
}
