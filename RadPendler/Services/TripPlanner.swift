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
                let limit = mode == .bike ? req.settings.bikeOptions : req.settings.optionsPerMode
                result.options += options.prefix(Swift.max(1, limit))
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
                radius: req.settings.waypointRadius)
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
