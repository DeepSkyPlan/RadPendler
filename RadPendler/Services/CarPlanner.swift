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
        return CarCandidate.pick(candidates, settings: req.settings, order: CarVariant.defaultOrder).enumerated().map { index, entry in
            let (c, variants) = entry
            let (drive, basis) = c.doorToDoor(req.settings)
            let leave = req.arriveBy.map { $0.addingTimeInterval(-drive) } ?? req.earliestLeave
            let leg = Leg(kind: .car, fromName: req.origin.shortName, toName: req.destination.shortName,
                          departure: leave, arrival: leave.addingTimeInterval(drive),
                          distance: c.route.distance, coordinates: c.route.coordinates)
            let saved = Int((c.queueSaving(req.settings) / 60).rounded())
            let note: String = if moto { Self.motorcycleNote(saved: saved, known: c.freeFlow != nil) } else {
                switch basis {
                case .learned: L("Apple Karten %@ — aus deinen Autofahrten", Fmt.factor(req.settings.carAppleFactor ?? 1))
                case .ownPace: L("nach deinem Auto-Schnitt von %@", Fmt.kmh(req.settings.carOverallKmh ?? 0))
                case .parking: L("inkl. %d min Parkplatzsuche", req.settings.parkingMinutes)
                case .apple: L("Fahrzeit laut Apple Karten mit Verkehrslage")
                }
            }
            var option = TripOption(mode: .car, legs: [leg], prep: req.settings.prep, note: note,
                                    carRoute: CarRouteInfo(variants: variants, signals: c.stats?.signals,
                                                           signalPoints: c.stats?.signalPoints ?? [],
                                                           appleSeconds: c.route.expectedTravelTime))
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
