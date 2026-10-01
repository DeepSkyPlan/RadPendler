import CoreLocation
import Foundation

// Alles mit Fahrplan: die Bahn allein und Rad + Bahn — im VBB über HAFAS mit
// selbst gewählten Bahnhöfen und Zubringern, sonst über Transitous (MOTIS),
// das die Bahnhöfe selbst wählt.

extension TripPlanner {
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
