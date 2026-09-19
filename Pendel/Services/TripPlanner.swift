import CoreLocation
import Foundation

struct PlanRequest {
    var origin: Place
    var destination: Place
    /// When the user wants to start getting ready; leaving is `start + prep`.
    var start: Date
    var settings: PlanSettings

    var earliestLeave: Date { start.addingTimeInterval(settings.prep) }
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
    var streets: StreetRouting = MapKitRouter()
    var rain = RainService()

    /// Stations considered at each end of a bike+rail trip. 3 × 4 = 12 HAFAS
    /// searches per refresh — each ~0.2 s, run in parallel.
    var originStationCount = 3
    var destinationStationCount = 4

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
        result.options.sort(by: Self.ranking)
        result.recommendation = Self.recommend(result.options)
        return result
    }

    private func capture(_ work: () async throws -> [TripOption]) async -> Result<[TripOption], Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }

    // MARK: Modes

    func bikeOptions(_ req: PlanRequest) async throws -> [TripOption] {
        let r = try await streets.route(from: req.origin.coordinate, to: req.destination.coordinate,
                                        mode: .bike, departure: nil)
        let leave = req.earliestLeave
        let leg = Leg(kind: .bike, fromName: req.origin.shortName, toName: req.destination.shortName,
                      departure: leave, arrival: leave.addingTimeInterval(req.settings.bikeTime(r.distance)),
                      distance: r.distance, coordinates: r.coordinates)
        return [TripOption(mode: .bike, legs: [leg], prep: req.settings.prep)]
    }

    func carOptions(_ req: PlanRequest) async throws -> [TripOption] {
        let leave = req.earliestLeave
        let r = try await streets.route(from: req.origin.coordinate, to: req.destination.coordinate,
                                        mode: .car, departure: leave)
        let parking = TimeInterval(req.settings.parkingMinutes * 60)
        let leg = Leg(kind: .car, fromName: req.origin.shortName, toName: req.destination.shortName,
                      departure: leave, arrival: leave.addingTimeInterval(r.expectedTravelTime + parking),
                      distance: r.distance, coordinates: r.coordinates)
        let note = parking > 0 ? "inkl. \(req.settings.parkingMinutes) min Parkplatzsuche" : "Fahrzeit laut Apple Karten mit Verkehrslage"
        return [TripOption(mode: .car, legs: [leg], prep: req.settings.prep, note: note)]
    }

    func transitOptions(_ req: PlanRequest) async throws -> [TripOption] {
        let journeys = try await hafas.journeys(
            from: .address(name: req.origin.name, coordinate: req.origin.coordinate),
            to: .address(name: req.destination.name, coordinate: req.destination.coordinate),
            departing: req.earliestLeave, bikeCarriage: false, results: 4)
        return journeys
            .filter { !$0.contains(where: \.cancelled) }
            .map { TripOption(mode: .transit, legs: $0, prep: req.settings.prep) }
            .sorted { $0.arrival < $1.arrival }
            .prefix(2).map { $0 }
    }

    /// Ride to a station, take only trains that carry bikes, ride on from the
    /// arrival station. The app does the station choice itself: VBB's HAFAS has
    /// a "bike & ride" mode in its web app, but the mgate request for it is not
    /// documented, and with address endpoints plus the bike filter it finds nothing.
    func bikeTransitOptions(_ req: PlanRequest) async throws -> [TripOption] {
        let s = req.settings
        let radius = s.maxBikeToStationKm * 1000
        async let fromList = hafas.nearbyStations(around: req.origin.coordinate, radius: radius)
        async let toList = hafas.nearbyStations(around: req.destination.coordinate, radius: radius)
        let starts = try await Array(fromList.prefix(originStationCount))
        let ends = try await Array(toList.prefix(destinationStationCount))
        guard !starts.isEmpty, !ends.isEmpty else {
            throw PlannerError.noStations(km: s.maxBikeToStationKm)
        }

        let firstLegs = await bikeRoutes(from: req.origin.coordinate, to: starts.map(\.coordinate), reverse: false)
        let lastLegs = await bikeRoutes(from: req.destination.coordinate, to: ends.map(\.coordinate), reverse: true)

        let candidates = try await withThrowingTaskGroup(of: [TripOption].self) { group in
            for (i, a) in starts.enumerated() {
                guard let ride1 = firstLegs[i] else { continue }
                for (j, b) in ends.enumerated() where a.lid != b.lid {
                    guard let ride2 = lastLegs[j] else { continue }
                    group.addTask {
                        let catchAt = req.earliestLeave.addingTimeInterval(s.bikeTime(ride1.distance) + s.bikeStationBuffer)
                        let journeys = try await hafas.journeys(from: .station(lid: a.lid), to: .station(lid: b.lid),
                                                                departing: catchAt, bikeCarriage: true,
                                                                productMask: TransitProduct.bikeSearchMask, results: 2)
                        return journeys.compactMap {
                            BikeTransitComposer.compose(origin: req.origin, destination: req.destination,
                                                        station1: a.name, ride1: ride1, journey: $0,
                                                        station2: b.name, ride2: ride2,
                                                        settings: s, earliestLeave: req.earliestLeave)
                        }
                    }
                }
            }
            return try await group.reduce(into: []) { $0 += $1 }
        }
        return BikeTransitComposer.best(candidates, count: 3)
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

    /// Earliest arrival first; within 3 minutes the more active mode first.
    static func ranking(_ a: TripOption, _ b: TripOption) -> Bool {
        if abs(a.arrival.timeIntervalSince(b.arrival)) < 180, a.mode != b.mode {
            return a.mode.preference < b.mode.preference
        }
        return a.arrival < b.arrival
    }

    /// The user's own rule: dry → ride (the whole way, or with the train if
    /// that arrives earlier); wet → bike in the train, which keeps the time in
    /// the rain short; Bus & Bahn only without any bike option; the car last.
    static func recommend(_ options: [TripOption]) -> Recommendation? {
        let level = { (o: TripOption) in o.rain?.level ?? .dry }
        let bikeish = options.filter { $0.mode == .bike || $0.mode == .bikeTransit }
        let dry = bikeish.filter { level($0) <= .possible }

        if let pick = dry.min(by: { $0.arrival < $1.arrival }) {
            let reason = pick.mode == .bike
                ? "Radstrecke \(pick.rain?.summary ?? "ohne Regendaten")"
                : "trocken und mit der Bahn schneller als die ganze Strecke per Rad"
            return Recommendation(optionID: pick.id, reason: reason)
        }
        if let pick = options.filter({ $0.mode == .bikeTransit })
            .min(by: { (level($0), $0.arrival) < (level($1), $1.arrival) }) {
            let wet = options.first { $0.mode == .bike }?.rain?.summary
            return Recommendation(optionID: pick.id,
                                  reason: "Regen auf der Radstrecke\(wet.map { " (\($0))" } ?? "") — Rad in die Bahn")
        }
        for mode in [TravelMode.transit, .bike, .car] {
            if let pick = options.filter({ $0.mode == mode }).min(by: { $0.arrival < $1.arrival }) {
                return Recommendation(optionID: pick.id, reason: "keine Verbindung mit Radmitnahme gefunden")
            }
        }
        return nil
    }

    enum PlannerError: LocalizedError {
        case noStations(km: Double)
        var errorDescription: String? {
            switch self {
            case .noStations(let km): "Kein Bahnhof mit Radmitnahme im Umkreis von \(Int(km)) km"
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
              transit.allSatisfy({ $0.bikeCarriage && !$0.cancelled }) else { return nil }

        // Leave as late as still catches the first train. Walk legs HAFAS puts
        // in front (platform changes inside the station) count as buffer.
        let boardBy = journey.first?.departure ?? firstTrain.departure
        let ride1Time = s.bikeTime(ride1.distance)
        let leave = boardBy.addingTimeInterval(-s.bikeStationBuffer - ride1Time)
        guard leave >= earliestLeave.addingTimeInterval(-30) else { return nil }

        let alight = journey.last?.arrival ?? lastTrain.arrival
        let ride2Start = alight.addingTimeInterval(s.bikeStationBuffer)

        let first = Leg(kind: .bike, fromName: origin.shortName, toName: station1,
                        departure: leave, arrival: leave.addingTimeInterval(ride1Time),
                        distance: ride1.distance, coordinates: ride1.coordinates)
        let last = Leg(kind: .bike, fromName: station2, toName: destination.shortName,
                       departure: ride2Start, arrival: ride2Start.addingTimeInterval(s.bikeTime(ride2.distance)),
                       distance: ride2.distance, coordinates: ride2.coordinates)
        return TripOption(mode: .bikeTransit, legs: [first] + journey + [last], prep: s.prep,
                          note: "\(s.bikeStationBufferMinutes) min Puffer je Bahnhof fürs Rad")
    }

    /// Drop duplicates (same trains reached from different stations — keep the
    /// one that leaves latest), then earliest arrival, then latest leave.
    static func best(_ options: [TripOption], count: Int) -> [TripOption] {
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
            .sorted { ($0.arrival, -$0.leave.timeIntervalSince1970) < ($1.arrival, -$1.leave.timeIntervalSince1970) }
            .prefix(count).map { $0 }
    }
}
