import CoreLocation
import Foundation

// Die ganze Strecke mit dem Rad: welche Linien angefragt werden, wie sie
// bewertet werden und was unter ihnen steht. Die Rollen selbst vergibt
// `BikeCandidate.pick` (RouteCandidates.swift).

extension TripPlanner {
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
            let wanted: [BikeLineSource] = roles.flatMap { v -> [BikeLineSource] in
                switch v {
                // „optimal" wägt Zeit gegen Ruhe ab — dazu muss die ruhige
                // Linie auch dastehen. „trekking" allein hält den Radweg an
                // der Hauptstraße für ideal; bis 1.14 kam „wenig Autos" nur
                // mit, wenn zufällig ein Platz frei blieb.
                case .balanced: [.brouter(.trekking), .brouter(.quiet)]
                case .fastest: [.brouter(.fastbike)]
                case .shortest: [.brouter(.shortest)]
                case .quiet: [.brouter(.quiet)]
                case .lowTraffic: [.brouter(.lowTraffic)]
                case .alternative: []
                }
            }
            return wanted.reduce(into: []) { out, source in if !out.contains(source) { out.append(source) } }
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
}
