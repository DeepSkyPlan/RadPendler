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

    /// Earliest moment to walk out of the door: preparation and the departure
    /// buffer come on top of the chosen start.
    var earliestLeave: Date {
        switch target {
        case .departAfter(let d): d.addingTimeInterval(settings.prep + settings.departureBuffer)
        case .arriveBy: .now.addingTimeInterval(settings.prep + settings.departureBuffer)
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
    var brouter = BRouterClient()
    var apple = MapKitRouter()
    var roads = RoadDataStore.shared
    var rain = RainService()

    /// S-Bahn/regional stations considered at each end of a bike+rail trip.
    /// 3 × 4 + 2 × 2 = 16 HAFAS searches per refresh — each ~0.2 s, in parallel.
    var originStationCount = 3
    var destinationStationCount = 4
    /// Nearest stations of any kind (incl. U-Bahn-only) for the alternative search: 2 × 2.
    var alternativeStationCount = 2

    func plan(_ req: PlanRequest) async -> PlanResult {
        async let bike = capture { try await bikeOptions(req) }
        async let car = capture { try await carOptions(req) }
        async let transit = capture { try await transitOptions(req) }
        async let bikeTransit = capture { try await bikeTransitOptions(req) }

        var result = PlanResult()
        for (mode, outcome) in await [(TravelMode.bike, bike), (.car, car), (.transit, transit), (.bikeTransit, bikeTransit)] {
            switch outcome {
            case .success(let options): result.options += options
            case .failure(let error): result.failures[mode] = error.localizedDescription
            }
        }

        do {
            try await attachRain(&result.options)
        } catch {
            result.rainFailure = "Regenvorhersage nicht verfügbar: \(error.localizedDescription)"
        }
        for i in result.options.indices {
            result.options[i].passesWaypoints = WaypointMatcher.passes(
                result.options[i], waypoints: req.settings.waypoints,
                requireAll: req.settings.requireAllWaypoints, radius: req.settings.waypointRadius)
        }
        let penalty = req.settings.transferPenalty
        let order = req.settings.modeOrder
        result.options.sort { Self.ranking($0, $1, penalty: penalty, order: order) }
        result.recommendation = Self.recommend(result.options, penalty: penalty, order: order,
                                               rainSwitch: req.settings.rainSwitchLevel)
        return result
    }

    private func capture(_ work: () async throws -> [TripOption]) async -> Result<[TripOption], Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }

    // MARK: Modes

    /// Whole way by bike, as up to three distinct routes: kürzest, Mittelweg,
    /// ruhigst. Candidates come from Apple Maps and several BRouter profiles;
    /// OpenStreetMap data then counts traffic lights, large roads crossed and
    /// metres beside large roads for each. Riding time includes an expected
    /// wait at every light.
    func bikeOptions(_ req: PlanRequest) async throws -> [TripOption] {
        let (o, d) = (req.origin.coordinate, req.destination.coordinate)
        let requests: [(String, BRouterClient.Profile?, Int)] = [
            ("Apple", nil, 0), ("trekking", .trekking, 0), ("fastbike", .fastbike, 0),
            ("safety", .safety, 0), ("safety", .safety, 1), ("safety", .safety, 2),
            // Pays a detour to stay off roads with cars on them — often the
            // way one actually rides home, and not the same as "ruhigst",
            // which also counts lights and crossings.
            ("verkehrsarm", .lowTraffic, 0),
        ]
        let found = await withTaskGroup(of: (Int, String, StreetRoute?).self) { group in
            for (i, (name, profile, alt)) in requests.enumerated() {
                group.addTask {
                    let r: StreetRoute? = if let profile {
                        try? await brouter.route(from: o, to: d, profile: profile, alternative: alt)
                    } else {
                        try? await apple.route(from: o, to: d, mode: .bike, departure: nil)
                    }
                    return (i, name, r)
                }
            }
            var out: [(Int, String, StreetRoute)] = []
            for await (i, name, r) in group { if let r { out.append((i, name, r)) } }
            return out.sorted { $0.0 < $1.0 }.map { ($0.1, $0.2) }
        }
        guard !found.isEmpty else { throw PlannerError.noBikeRoute }

        let data = Self.withLearned(try? await roads.data(covering: found.flatMap { $0.1.coordinates }), req.settings)
        // 63 ms per route, six routes: serially that is 378 ms of the plan for
        // nothing. They do not depend on each other.
        let candidates = await withTaskGroup(of: (Int, BikeCandidate).self) { group in
            for (i, (name, route)) in found.enumerated() {
                group.addTask {
                    (i, BikeCandidate(source: name, route: route,
                                      stats: data.map { RouteAnalyzer.analyze(route.coordinates, roads: $0) }))
                }
            }
            var out: [(Int, BikeCandidate)] = []
            for await pair in group { out.append(pair) }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
        let picked = BikeCandidate.pick(candidates, settings: req.settings)

        return picked.enumerated().map { index, entry in
            let (c, variants) = entry
            let ride = c.time(req.settings)
            let leave = req.arriveBy.map { $0.addingTimeInterval(-ride) } ?? req.earliestLeave
            let leg = Leg(kind: .bike, fromName: req.origin.shortName, toName: req.destination.shortName,
                          departure: leave, arrival: leave.addingTimeInterval(ride),
                          distance: c.route.distance, coordinates: c.route.coordinates)
            var option = TripOption(mode: .bike, legs: [leg], prep: req.settings.prep,
                                    note: data == nil ? Self.noRoadDataNote(km: c.route.distance / 1000, settings: req.settings) : nil,
                                    bikeRoute: BikeRouteInfo(variants: variants, stats: c.stats, source: c.source))
            // Only the route that matches the user's first choice is the one
            // the recommendation weighs; the others are alternatives.
            option.isPreferredVariant = index == 0
            return option
        }
    }

    /// The car as the two or three lines Apple actually offers, labelled the
    /// way the bike routes are: schnellst (the default), kürzest, wenig Ampeln.
    /// The lights come from the same OpenStreetMap data the bike routes use —
    /// on a commute that is the difference between the autobahn detour and the
    /// straight run through town.
    /// Why a route has no traffic-light count: too long to ask Overpass for,
    /// or Overpass simply did not answer.
    /// OpenStreetMap's lit junctions plus the ones this rider has been stopped
    /// at. `RouteAnalyzer` merges signal nodes within 60 m, so a learned light
    /// sitting on top of a mapped one does not count twice.
    static func withLearned(_ data: RoadData?, _ settings: PlanSettings) -> RoadData? {
        guard var data, !settings.learnedSignals.isEmpty else { return data }
        data.signals += settings.learnedSignals.map(\.coordinate)
        return data
    }

    static func noRoadDataNote(km: Double, settings: PlanSettings) -> String {
        km > settings.longTripKm
            ? "Ampeln und Hauptstraßen auf dieser Länge nicht gezählt"
            : "Ampeln und Hauptstraßen unbekannt (OpenStreetMap nicht erreichbar)"
    }

    func carOptions(_ req: PlanRequest) async throws -> [TripOption] {
        let guess = req.arriveBy ?? req.earliestLeave
        let found = try await apple.routes(from: req.origin.coordinate, to: req.destination.coordinate,
                                           mode: .car, departure: guess)
            // Two lines that differ by a hundred metres are one line.
            .reduce(into: [StreetRoute]()) { out, r in
                guard !out.contains(where: { abs($0.distance - r.distance) < 100
                                          && abs($0.expectedTravelTime - r.expectedTravelTime) < 60 }) else { return }
                out.append(r)
            }
        let data = Self.withLearned(try? await roads.data(covering: found.flatMap(\.coordinates)), req.settings)
        let candidates = found.map { route in
            CarCandidate(route: route,
                         stats: data.map { RouteAnalyzer.analyze(route.coordinates, roads: $0) })
        }
        let parking = TimeInterval(req.settings.parkingMinutes * 60)
        return CarCandidate.pick(candidates, settings: req.settings, order: req.settings.carVariantOrder).enumerated().map { index, entry in
            let (c, variants) = entry
            let drive = c.route.expectedTravelTime + parking
            let leave = req.arriveBy.map { $0.addingTimeInterval(-drive) } ?? req.earliestLeave
            let leg = Leg(kind: .car, fromName: req.origin.shortName, toName: req.destination.shortName,
                          departure: leave, arrival: leave.addingTimeInterval(drive),
                          distance: c.route.distance, coordinates: c.route.coordinates)
            let note = parking > 0 ? "inkl. \(req.settings.parkingMinutes) min Parkplatzsuche" : "Fahrzeit laut Apple Karten mit Verkehrslage"
            var option = TripOption(mode: .car, legs: [leg], prep: req.settings.prep, note: note,
                                    carRoute: CarRouteInfo(variants: variants, signals: c.stats?.signals,
                                                           signalPoints: c.stats?.signalPoints ?? []))
            option.isPreferredVariant = index == 0
            return option
        }
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

    /// Ride to a station, take only trains that carry bikes, ride on from the
    /// arrival station. The app does the station choice itself: VBB's HAFAS has
    /// a "bike & ride" mode in its web app, but the mgate request for it is not
    /// documented, and with address endpoints plus the bike filter it finds nothing.
    ///
    /// S-Bahn and regional trains first — they always have a bike compartment.
    /// The main search uses only S/RE stations and S/RE trains; a small second
    /// search from the nearest stations of any kind lets U-Bahn/tram in, and
    /// those results are kept only as the alternative.
    /// A planner that cannot reach anything: every client points at a host
    /// that does not resolve, so a test using it fails fast instead of calling
    /// five live services. Used by the tests that only care about the state a
    /// search leaves behind, not about its result.
    static var offline: TripPlanner {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1
        config.protocolClasses = [BlockedProtocol.self]
        let session = URLSession(configuration: config)
        var planner = TripPlanner()
        planner.hafas.session = session
        planner.motis.session = session
        planner.brouter.session = session
        planner.rain.session = session
        return planner
    }

    /// Which timetable answers for this request.
    func source(_ req: PlanRequest) -> TimetableSource {
        req.settings.timetableSource.resolved(from: req.origin.coordinate, to: req.destination.coordinate)
    }

    /// Bike at both ends, planned by Transitous in one request: MOTIS routes
    /// intermodally, so it picks the stations itself and the app does not have
    /// to try sixteen station pairs as it does with HAFAS.
    func motisBikeTransitOptions(_ req: PlanRequest) async throws -> [TripOption] {
        let s = req.settings
        let journeys = try await motis.journeys(from: req.origin.coordinate, to: req.destination.coordinate,
                                                at: req.arriveBy ?? req.earliestLeave,
                                                arriveBy: req.isArrival, access: .bike, results: 5)
        let options = journeys.compactMap { legs -> TripOption? in
            let transit = legs.filter(\.isTransit)
            guard !transit.isEmpty, transit.allSatisfy({ !$0.cancelled }),
                  transit.allSatisfy({ s.carriage($0) != .no }),
                  legs.contains(where: { $0.kind == .bike }) else { return nil }
            let decided = legs.map { leg -> Leg in
                guard leg.isTransit else { return leg }
                var l = leg
                l.bikeCarriage = s.carriage(leg)
                return l
            }
            return TripOption(mode: .bikeTransit, legs: decided, prep: s.prep,
                              note: "Fahrten von Transitous; Radzeiten nach deren Schätzung")
        }
        return BikeTransitComposer.rank(options, preferred: 3, alternatives: 1,
                                        penalty: s.transferPenalty, arrival: req.isArrival)
    }

    func bikeTransitOptions(_ req: PlanRequest) async throws -> [TripOption] {
        guard source(req) == .vbb else { return try await motisBikeTransitOptions(req) }
        let s = req.settings
        let radius = s.maxBikeToStationKm * 1000
        async let fromList = hafas.nearbyStations(around: req.origin.coordinate, radius: radius)
        async let toList = hafas.nearbyStations(around: req.destination.coordinate, radius: radius)
        let fromAll = try await fromList, toAll = try await toList

        var searches: [(from: Station, to: Station, mask: Int)] = []
        let preferredMask = TransitProduct.bikeCompartmentMask
        for a in fromAll.filter(\.hasBikeCompartment).prefix(originStationCount) {
            for b in toAll.filter(\.hasBikeCompartment).prefix(destinationStationCount) {
                searches.append((a, b, preferredMask))
            }
        }
        for a in fromAll.prefix(alternativeStationCount) {
            for b in toAll.prefix(alternativeStationCount) {
                searches.append((a, b, TransitProduct.bikeSearchMask))
            }
        }
        searches.removeAll { $0.from.lid == $0.to.lid }
        guard !searches.isEmpty else { throw PlannerError.noStations(km: s.maxBikeToStationKm) }

        let starts = unique(searches.map(\.from)), ends = unique(searches.map(\.to))
        // The two ends do not wait for each other: measured 935 ms + 187 ms
        // sequentially, 935 ms together.
        async let firstGroup = bikeRoutes(from: req.origin.coordinate, to: starts.map(\.coordinate), reverse: false)
        async let lastGroup = bikeRoutes(from: req.destination.coordinate, to: ends.map(\.coordinate), reverse: true)
        var firstLegs = await firstGroup
        var lastLegs = await lastGroup
        // Same traffic-light wait as on the whole-way bike routes.
        let rides = (firstLegs + lastLegs).compactMap { $0 }
        if !rides.isEmpty, let data = try? await roads.data(covering: rides.flatMap(\.coordinates)) {
            let withSignals = { (r: StreetRoute?) -> StreetRoute? in
                r.map { var r = $0; r.signals = RouteAnalyzer.analyze(r.coordinates, roads: data).signals; return r }
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

    /// Bike routes between `anchor` and each station, nil where MapKit found none.
    /// `reverse` rides from the station to the anchor.
    private func bikeRoutes(from anchor: CLLocationCoordinate2D, to stations: [CLLocationCoordinate2D],
                            reverse: Bool) async -> [StreetRoute?] {
        await withTaskGroup(of: (Int, StreetRoute?).self) { group in
            for (i, st) in stations.enumerated() {
                group.addTask {
                    let r = try? await streets.route(from: reverse ? st : anchor, to: reverse ? anchor : st,
                                                     mode: .bike, departure: nil)
                    return (i, r)
                }
            }
            var out = [StreetRoute?](repeating: nil, count: stations.count)
            for await (i, r) in group { out[i] = r }
            return out
        }
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
                : "trocken und mit der Bahn schneller als die ganze Strecke per Rad"
            return Recommendation(optionID: pick.id, reason: reason)
        }
        if let pick = bikeTransit
            .min(by: { (level($0), arrival($0)) < (level($1), arrival($1)) }) {
            let wet = options.first(where: preferredBike)?.rain?.summary
            return Recommendation(optionID: pick.id,
                                  reason: "Regen auf der Radstrecke\(wet.map { " (\($0))" } ?? "") — Rad in die Bahn")
        }
        // No connection that takes the bike: fall back in the user's own order,
        // minus bike + rail, which just had its turn.
        for mode in order where mode != .bikeTransit {
            if let pick = options.filter({ $0.mode == mode }).min(by: { arrival($0) < arrival($1) }) {
                return Recommendation(optionID: pick.id, reason: "keine Verbindung mit Radmitnahme gefunden")
            }
        }
        return nil
    }

    enum PlannerError: LocalizedError {
        case noStations(km: Double)
        case noBikeRoute
        var errorDescription: String? {
            switch self {
            case .noStations(let km): "Kein Bahnhof mit Radmitnahme im Umkreis von \(Int(km)) km"
            case .noBikeRoute: "Keine Radroute gefunden (Apple Karten und BRouter)"
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
        var transit = journey.filter(\.isTransit)
        guard let firstTrain = transit.first, let lastTrain = transit.last,
              transit.allSatisfy({ !$0.cancelled }) else { return nil }
        // A line the user has ruled out is out. One nobody has judged stays in,
        // with the warning — that is the whole point of the list.
        guard transit.allSatisfy({ s.carriage($0) != .no }) else { return nil }
        transit = transit.map { var l = $0; l.bikeCarriage = s.carriage($0); return l }

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
        // The legs keep the decision, so the timeline and the warnings agree.
        let decided = journey.map { leg -> Leg in
            guard leg.isTransit else { return leg }
            var l = leg
            l.bikeCarriage = s.carriage(leg)
            return l
        }
        return TripOption(mode: .bikeTransit, legs: [first] + decided + [last], prep: s.prep,
                          note: "\(s.bikeStationBufferMinutes) min Puffer je Bahnhof fürs Rad")
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

/// One car line and how it scores. Apple gives the times; the lights come
/// from OpenStreetMap, and without them only speed and length can be judged.
struct CarCandidate {
    var route: StreetRoute
    var stats: BikeRouteStats?

    var signals: Int? { stats?.signals }

    /// Driving time with the waiting at the lights added, the way the bike
    /// routes count it — an Apple estimate already includes traffic, but not
    /// the difference between twelve junctions and forty.
    func time(_ s: PlanSettings) -> TimeInterval {
        route.expectedTravelTime + Double((signals ?? 0) * s.signalWaitSeconds) * 0.5
    }

    /// Mittelweg: time plus half the waiting, so a line that is two minutes
    /// slower but crosses twenty fewer junctions can win it.
    func balancedScore(_ s: PlanSettings) -> Double {
        route.expectedTravelTime + Double((signals ?? 0) * s.signalWaitSeconds)
    }

    /// schnellst = least driving time, kürzest = fewest metres, optimal = the
    /// best balance of time and lights, wenig Ampeln = fewest junctions.
    ///
    /// Every line Apple offered comes back, whether or not it won a role —
    /// showing only the fastest one made the car look like it had no choice.
    /// Roles are ordered the way the user put them.
    static func pick(_ all: [CarCandidate], settings s: PlanSettings = PlanSettings(),
                     order: [CarVariant] = CarVariant.defaultOrder) -> [(CarCandidate, [CarVariant])] {
        guard !all.isEmpty else { return [] }
        // One line wins everything by default; four labels on it say nothing.
        guard all.count > 1 else { return [(all[0], [.fastest])] }
        var roles: [Int: [CarVariant]] = [:]
        if let i = all.indices.min(by: { all[$0].route.expectedTravelTime < all[$1].route.expectedTravelTime }) {
            roles[i, default: []].append(.fastest)
        }
        if let i = all.indices.min(by: { all[$0].route.distance < all[$1].route.distance }) {
            roles[i, default: []].append(.shortest)
        }
        if all.contains(where: { $0.signals != nil }) {
            if let i = all.indices.min(by: { $0 == $1 ? false : all[$0].balancedScore(s) < all[$1].balancedScore(s) }) {
                roles[i, default: []].append(.balanced)
            }
            if let i = all.indices.min(by: { (all[$0].signals ?? .max) < (all[$1].signals ?? .max) }) {
                roles[i, default: []].append(.fewSignals)
            }
        }
        // A line without a role is still a line.
        for i in all.indices where roles[i] == nil { roles[i] = [.alternative] }
        let rank = { (v: CarVariant) in order.firstIndex(of: v) ?? order.count }
        return roles
            .map { (all[$0.key], $0.value.sorted { rank($0) < rank($1) }) }
            .sorted { rank($0.1.first!) < rank($1.1.first!) }
    }
}

/// One bike route candidate and how it scores.
struct BikeCandidate {
    var source: String
    var route: StreetRoute
    var stats: BikeRouteStats?

    /// Riding time at the configured speed plus the expected wait at lights.
    func time(_ s: PlanSettings) -> TimeInterval {
        s.bikeTime(route.distance) + Double((stats?.signals ?? route.signals) * s.signalWaitSeconds)
    }

    /// Mittelweg: time plus half the disturbance, converted to riding time.
    func balancedScore(_ s: PlanSettings) -> Double {
        time(s) + 0.5 * (stats?.disturbance ?? 0) / s.bikeSpeedMps
    }

    /// schnellst = least riding time (traffic lights included), ruhigst =
    /// least disturbance, verkehrsarm = fewest metres beside a main road,
    /// optimal = best balance of time and disturbance. A route winning several
    /// roles is listed once with all its labels. Without OpenStreetMap data
    /// only the time can be judged; BRouter's "safety" route then stands in
    /// for "ruhigst" and its low-traffic profile for "verkehrsarm".
    ///
    /// "ruhigst" and "verkehrsarm" are not the same question: the first counts
    /// lights and crossings too, the second only asks where the cars are.
    ///
    /// The list comes back in the order the user put the variants in, so the
    /// first route is the one the app suggests and the first the boxes show.
    static func pick(_ all: [BikeCandidate], settings s: PlanSettings) -> [(BikeCandidate, [BikeVariant])] {
        guard let fastest = all.indices.min(by: { all[$0].time(s) < all[$1].time(s) }) else { return [] }
        let quiet: Int, balanced: Int, lowTraffic: Int
        if all.contains(where: { $0.stats != nil }) {
            quiet = all.indices.min { (all[$0].stats?.disturbance ?? .infinity) < (all[$1].stats?.disturbance ?? .infinity) }!
            balanced = all.indices.min { all[$0].balancedScore(s) < all[$1].balancedScore(s) }!
            lowTraffic = all.indices.min {
                (all[$0].stats?.mainRoadMeters ?? .infinity) < (all[$1].stats?.mainRoadMeters ?? .infinity)
            }!
        } else {
            quiet = all.firstIndex { $0.source == "safety" } ?? fastest
            balanced = all.firstIndex { $0.source == "trekking" } ?? fastest
            lowTraffic = all.firstIndex { $0.source == "verkehrsarm" } ?? quiet
        }
        let shortest = all.indices.min { all[$0].route.distance < all[$1].route.distance }!
        var roles: [Int: [BikeVariant]] = [:]
        roles[fastest, default: []].append(.fastest)
        roles[shortest, default: []].append(.shortest)
        roles[balanced, default: []].append(.balanced)
        roles[quiet, default: []].append(.quiet)
        roles[lowTraffic, default: []].append(.lowTraffic)
        let order = s.bikeVariantOrder
        let rank = { (v: BikeVariant) in order.firstIndex(of: v) ?? order.count }
        return roles
            .map { (all[$0.key], $0.value.sorted { rank($0) < rank($1) }) }
            .sorted { rank($0.1.first!) < rank($1.1.first!) }
    }
}


/// Refuses every request. Lets a test run a real planner without a network.
final class BlockedProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
