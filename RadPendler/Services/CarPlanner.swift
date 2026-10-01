import CoreLocation
import Foundation

// Das Auto (und das Motorrad im selben Kasten): Apples Linien, ihre Ampeln
// und die eigene Gegenprobe. Die Rollen vergibt `CarCandidate.pick`.

extension TripPlanner {
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
        return CarCandidate.pick(candidates, settings: req.settings, order: CarVariant.defaultOrder).enumerated().map { index, entry in
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
}
