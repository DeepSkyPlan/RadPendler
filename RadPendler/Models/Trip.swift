import CoreLocation
import Foundation

enum TravelMode: String, CaseIterable, Identifiable {
    case bike, bikeTransit, transit, car

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bike: L("Fahrrad")
        case .bikeTransit: L("Rad + Bahn")
        case .transit: L("Bus & Bahn")
        case .car: Vehicle.title
        }
    }

    var symbol: String {
        switch self {
        case .bike: "bicycle"
        case .bikeTransit: "bicycle.circle.fill"
        case .transit: "tram.fill"
        case .car: Vehicle.symbol
        }
    }

    /// What the app ships with — the user can reorder it in the settings, and
    /// that order decides which mode wins when two trips arrive at nearly the
    /// same time, and in which order the four boxes stand.
    static let defaultOrder: [TravelMode] = [.bike, .bikeTransit, .car, .transit]

    /// For the one line that has to hold all four: "Rad › Rad+Bahn › Auto › ÖPNV".
    var short: String {
        switch self {
        case .bike: L("Rad")
        case .bikeTransit: L("Rad+Bahn")
        case .transit: L("ÖPNV")
        case .car: Vehicle.title
        }
    }
}

/// Womit der Kasten „Auto" fährt: mit dem Auto oder mit dem Motorrad.
///
/// Kein fünftes Verkehrsmittel, sondern dasselbe mit anderem Fahrzeug — es
/// fährt dieselben Straßen, dieselbe Apple-Route, zeichnet sich genauso auf.
/// Anders ist nur, was ein Stau kostet (`CarCandidate.driveTime`), und wie es
/// heißt. Wie `AppLanguage.current` ein Wert für die ganze App: die
/// Einstellung schreibt ihn, Titel und Symbol lesen ihn, und die
/// Wurzelansicht baut sich neu, wenn er wechselt.
enum Vehicle {
    static var motorcycle = false

    static var title: String { motorcycle ? L("Motorrad") : L("Auto") }
    static var symbol: String { motorcycle ? motorcycleSymbol : "car.fill" }

    /// `motorcycle.fill` gibt es erst ab iOS 18; darunter der Roller.
    static var motorcycleSymbol: String {
        if #available(iOS 18, watchOS 11, *) { return "motorcycle.fill" }
        return "scooter"
    }
}

/// Die zwei Regeln, nach denen überall dasselbe gelten muss: **worauf der
/// Countdown zählt** und **in welcher Reihenfolge eine Kategorie ihre
/// Möglichkeiten zeigt**.
///
/// Sie standen dreimal da — im `PlanModel`, in `WatchLink` und in
/// `BackgroundReplan` —, und zwei dieser drei Kopien sieht man beim
/// Ausprobieren nie: die Uhr und die im Hintergrund geweckte App. Es ist
/// zugleich die Stelle, die vor dem falschen Zug warnt.
enum TripRules {
    /// Eine Fahrt hat nur dann eine feste Abfahrt, wenn ein Zug oder ein Bus
    /// darin vorkommt — oder wenn nach einer Ankunftszeit gesucht wurde. Rad
    /// und Auto mit „jetzt los" haben nichts, worauf sich zählen ließe.
    static func countsDown(_ option: TripOption, arrivalSearch: Bool) -> Bool {
        arrivalSearch || !option.transitLegs.isEmpty
    }

    /// Erst die eigentlichen Möglichkeiten, dann die Alternativen; und
    /// innerhalb beider erst, was über die Fixpunkte führt.
    static func ordered(_ options: [TripOption]) -> [TripOption] {
        let sorted = options.filter { !$0.isAlternative } + options.filter(\.isAlternative)
        return sorted.filter(\.passesWaypoints) + sorted.filter { !$0.passesWaypoints }
    }
}

/// HAFAS product classes as the VBB profile numbers them.
enum TransitProduct: Int, CaseIterable {
    case suburban = 1, subway = 2, tram = 4, bus = 8, ferry = 16, express = 32, regional = 64
    /// A class the timetable did not name, or named in a way this app does not
    /// know. It must not pass as a regional train: that would hand it a bike
    /// compartment nobody promised.
    case unknown = 128

    /// S-Bahn, U-Bahn and regional trains: the stations worth riding a bike to.
    static let bikeStationMask = suburban.rawValue | subway.rawValue | regional.rawValue
    /// S-Bahn and regional trains always have a bike compartment — the
    /// preferred way to take the bike. U-Bahn and tram are only the alternative.
    static let bikeCompartmentMask = suburban.rawValue | regional.rawValue

    var hasBikeCompartment: Bool { rawValue & Self.bikeCompartmentMask != 0 }
    /// Everything but buses — BVG buses do not take bikes.
    static let bikeSearchMask = allCases.filter { $0 != .bus && $0 != .unknown }.reduce(0) { $0 | $1.rawValue }
    static let allMask = allCases.filter { $0 != .unknown }.reduce(0) { $0 | $1.rawValue }

    init(cls: Int) {
        self = TransitProduct(rawValue: cls) ?? .unknown
    }
}

/// Which of the bike route variants an option is; one route can be several.
enum BikeVariant: String, CaseIterable, Comparable {
    // New cases go at the end: `Comparable` reads the position in `allCases`,
    // and inserting one in the middle would silently reorder the old ones.
    case fastest, shortest, balanced, quiet, lowTraffic
    /// Ein Weg, der keine Rolle gewinnt, weil eine andere Linie alle
    /// gewonnen hat. Steht nie in der eigenen Reihenfolge — siehe
    /// `BikeCandidate.pick`.
    case alternative

    /// „ruhigst" und „verkehrsarm" waren am Wort nicht auseinanderzuhalten,
    /// obwohl sie zwei verschiedene Fragen beantworten: die eine, **wie lange
    /// man neben Autos fährt**, die andere, **wie oft man ihretwegen anhält**.
    /// Die Namen sagen das jetzt.
    var title: String {
        switch self {
        case .fastest: L("schnellst")
        case .shortest: L("kürzest")
        case .balanced: L("optimal")
        case .quiet: L("wenig Autos")
        case .lowTraffic: L("wenig Halts")
        case .alternative: L("Alternative")
        }
    }

    /// Ein Satz, der den Namen erklärt — für die Detailseite und die
    /// Einstellungen, wo Platz dafür ist.
    var explanation: String {
        switch self {
        case .fastest: L("kürzeste Fahrzeit, Ampeln und Höhenmeter eingerechnet")
        case .shortest: L("die kürzeste Strecke, ganz gleich worüber")
        case .balanced: L("die Mischung: zügig, wenig neben Autos, wenig Halts")
        case .quiet: L("die wenigsten Meter neben fahrenden Autos")
        case .lowTraffic: L("am seltensten wegen des Verkehrs anhalten")
        case .alternative: L("ein anderer Weg — in keiner Hinsicht der beste, aber anders")
        }
    }

    var symbol: String {
        switch self {
        case .fastest: "hare"
        case .shortest: "ruler"
        case .balanced: "checkmark.seal"
        case .quiet: "leaf"
        case .lowTraffic: "road.lanes"
        case .alternative: "arrow.triangle.branch"
        }
    }

    static func < (a: BikeVariant, b: BikeVariant) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }

    /// Ships with "optimal" first: that is the one the app suggests. The user
    /// can put "wenig Autos" or "kürzest" in front of it.
    static let defaultOrder: [BikeVariant] = [.balanced, .fastest, .shortest, .quiet, .lowTraffic]
}

/// Which of the car alternatives an option is; one route can be several.
/// Apple returns two or three lines for a commute — the fastest is the
/// default, the other roles only get a label when a different line wins them.
enum CarVariant: String, CaseIterable, Comparable {
    case fastest, shortest, balanced, fewSignals
    /// A line Apple offered that wins no role of its own. It is still worth
    /// showing: the fastest route is not always the one you want to drive.
    case alternative

    var title: String {
        switch self {
        case .fastest: L("schnellst")
        case .shortest: L("kürzest")
        case .balanced: L("optimal")
        case .fewSignals: L("wenig Ampeln")
        case .alternative: L("Alternative")
        }
    }

    static func < (a: CarVariant, b: CarVariant) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }

    /// Fest seit 1.10: Apple liefert meist zwei, drei Linien, und auf die
    /// verteilen sich die Namen ohnehin — fünf Rollen zu sortieren brachte
    /// nichts. Der Sortier-Editor ist weg.
    static let defaultOrder: [CarVariant] = [.balanced, .fastest, .fewSignals, .shortest, .alternative]
}

/// The chosen car line and what sets it apart from the others.
struct CarRouteInfo {
    var variants: [CarVariant]
    /// Signalised junctions along the way; nil when OpenStreetMap was unreachable.
    var signals: Int?
    var signalPoints: [CLLocationCoordinate2D] = []
    /// Apples reine Fahrzeit für diese Linie, mit Verkehrslage — vor
    /// Parkplatzsuche, eigenem Schnitt und gelerntem Faktor. Wandert in die
    /// aufgezeichnete Fahrt (`Ride.appleSeconds`).
    var appleSeconds: TimeInterval? = nil

    /// Already in the user's order; the first one names the route.
    var title: String { variants.map(\.title).joined(separator: " · ") }
}

/// Woher eine Radlinie stammt — welcher Router sie mit welchem Profil
/// gezeichnet hat.
///
/// Bis 1.9.1 stand hier ein Text: der Name, unter dem der Planer angefragt
/// hatte, teils übersetzt („verkehrsarm"), teils irreführend („safety" für
/// das eigene „wenig Autos"). Eine Neuplanung unterwegs musste daraus das
/// Profil zurückraten.
enum BikeLineSource: Hashable, Sendable {
    case brouter(BRouterClient.Profile)
    /// Apples eine Radlinie, ohne Profil.
    case apple
    /// Die eigene typische Fahrt, mit „trekking" über ihre Punkte nachgefahren
    /// — siehe `RiddenPaths`.
    case habit

    /// Womit eine Neuplanung unterwegs diese Linie weiterzeichnet. Apples
    /// Linie hat kein Profil; für sie gilt „trekking", BRouters Allzweckprofil
    /// — wie für die gewohnte, die damit angefragt wurde.
    var profile: BRouterClient.Profile {
        if case .brouter(let p) = self { p } else { .trekking }
    }

    /// Was die Detailseite in Klammern hinter „BRouter" schreibt — die Namen,
    /// die dort schon immer standen.
    var label: String {
        switch self {
        case .apple: "Apple"
        case .habit: L("gewohnt")
        case .brouter(let p):
            switch p {
            case .quiet: "safety"
            case .lowTraffic: L("verkehrsarm")
            default: p.rawValue
            }
        }
    }
}

struct BikeRouteInfo {
    var variants: [BikeVariant]
    var stats: BikeRouteStats?
    /// Welcher Router mit welchem Profil diese Linie gezeichnet hat.
    var source: BikeLineSource
    /// Metres per road class, where the router said. Empty for Apple's line.
    var mix = RoadMix()
    /// The same with positions, handed to a recording so the ride can be
    /// attributed to the same classes afterwards.
    var roadPoints: [RoadPoint] = []
    /// Summierter Anstieg in Metern; nil, wenn der Router keine Höhen kennt.
    var ascent: Double? = nil
    /// Gesetzt, wenn nicht die Rechnung die Fahrzeit bestimmt hat, sondern der
    /// gemessene Schnitt dieses Fahrers — dann soll das auch dastehen.
    var measuredKmh: Double? = nil
    /// Anteil auf schon gefahrenen Wegen, 0…1 — siehe `RiddenPaths`.
    var familiar: Double = 0
    /// Die Zwischenpunkte, über die diese Linie geplant wurde: Fixpunkte und,
    /// bei „gewohnt", die Punkte auf der eigenen Fahrt. Eine Neuplanung
    /// unterwegs fährt die noch vor einem liegenden ebenfalls an.
    var via: [CLLocationCoordinate2D] = []

    /// Die Linie, die die eigene typische Fahrt nachfährt.
    var isHabit: Bool { source == .habit }

    /// Already in the order the user put the variants in; the first is the one
    /// that decides what the box says. Leer heißt: diese Linie ist in keiner
    /// Hinsicht die beste — ein anderer Weg ist sie trotzdem.
    var title: String {
        // Eine Linie ohne eigene Rolle, die die eigene Fahrt nachfährt, ist
        // keine „Alternative", sondern die gewohnte.
        if isHabit, variants == [.alternative] { return L("gewohnt") }
        return variants.map(\.title).joined(separator: " · ")
    }
    /// Was der Kasten schreibt: der erste Name.
    var shortTitle: String {
        if isHabit, variants == [.alternative] { return L("gewohnt") }
        return variants.first?.title ?? "Route"
    }

    /// Warum diese Linie so heißt — und, wenn sie mehrere Rollen gewonnen hat,
    /// dass sie in **allen** diesen Hinsichten die beste ist. Eine Aufzählung
    /// „optimal · schnellst · wenig Autos" allein liest sich wie eine Auswahl,
    /// aus der man etwas anklicken müsste; gemeint ist das Gegenteil.
    var reason: String {
        guard let first = variants.first else { return "" }
        guard variants.count > 1 else { return first.explanation }
        let rest = variants.dropFirst().map(\.title)
        let list = rest.count == 1 ? rest[0]
                                   : rest.dropLast().joined(separator: ", ") + L(" und ") + rest.last!
        return L("%@ — und zugleich %@", first.explanation, list)
    }
}

/// Whether the bike may come along. `unknown` is a real answer, not a missing
/// one: the trip is still offered, with a warning, until the user has said.
enum BikeCarriage: String, Codable, Equatable {
    case yes, no, unknown
}

enum LegKind: Equatable {
    case walk
    case bike
    case car
    case transit(line: String, product: TransitProduct)
}

struct Leg: Identifiable {
    let id = UUID()
    var kind: LegKind
    var fromName: String
    var toName: String
    /// Best known time: real-time prognosis if HAFAS has one, else the timetable.
    var departure: Date
    var arrival: Date
    var plannedDeparture: Date? = nil
    var plannedArrival: Date? = nil
    var distance: Double? = nil
    var coordinates: [CLLocationCoordinate2D] = []
    var departurePlatform: String? = nil
    var arrivalPlatform: String? = nil
    var direction: String? = nil
    /// What is known about taking the bike on this leg. The timetable only ever
    /// says yes or nothing; the user decides the rest, per line, in the
    /// settings. Nothing is guessed.
    var bikeCarriage: BikeCarriage = .unknown
    var cancelled = false

    var duration: TimeInterval { arrival.timeIntervalSince(departure) }

    /// Metres: what the router said, else the length of the drawn line.
    var length: Double? {
        if let distance { return distance }
        guard coordinates.count > 1 else { return nil }
        return zip(coordinates, coordinates.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    var departureDelay: TimeInterval {
        plannedDeparture.map { departure.timeIntervalSince($0) } ?? 0
    }

    var isTransit: Bool {
        if case .transit = kind { true } else { false }
    }

    var lineName: String? {
        if case .transit(let line, _) = kind { line } else { nil }
    }
}

struct TripOption: Identifiable {
    var mode: TravelMode
    var legs: [Leg]
    /// Minutes of preparation before `leave`.
    var prep: TimeInterval
    var note: String? = nil
    var rain: RainAssessment? = nil
    /// Set on whole-way bike options.
    var bikeRoute: BikeRouteInfo? = nil
    /// Set on car options.
    var carRoute: CarRouteInfo? = nil
    /// False when the trip misses the fixed points from the settings.
    var passesWaypoints = true
    /// The one route of its mode that matches the user's first choice — the
    /// only whole-way bike route the recommendation considers.
    var isPreferredVariant = true

    /// Dieselbe Möglichkeit hat in zwei Planungen dieselbe Kennung.
    ///
    /// Bis 1.9.1 war das eine `UUID()` je Planung: jede Neuplanung — und jeder
    /// ihrer vier Zwischenstände — brachte dieselben Linien mit neuen Kennungen.
    /// Die Auswahl fiel deshalb nach jedem Lauf auf die Empfehlung zurück, die
    /// Karte erkannte ihre Linien an der Geometrie statt an der Kennung, und
    /// die Uhr meldete ihre Wahl als Stelle in der Liste.
    ///
    /// Rad und Auto: Rollen und Linie (Länge auf 100 m, Mittelpunkt auf rund
    /// 100 m) — **ohne** Abfahrt, denn bei „jetzt los" rückt die mit jeder
    /// Neuplanung eine Minute weiter, und es bleibt doch dieselbe Route. Bahn
    /// und Rad + Bahn: jeder Zug mit Linie, Abfahrtsbahnhof und **planmäßiger**
    /// Abfahrtsminute; eine Verspätung macht aus dem Zug keinen anderen.
    var id: String {
        let minute = { (d: Date) in String(Int((d.timeIntervalSince1970 / 60).rounded(.down))) }
        let hm = String(Int((totalDistance / 100).rounded()))
        switch mode {
        case .bike, .car:
            let roles = bikeRoute?.variants.map(\.rawValue) ?? carRoute?.variants.map(\.rawValue) ?? []
            let line = legs.first?.coordinates ?? []
            let mid = line.isEmpty ? "-" : String(format: "%.3f,%.3f", line[line.count / 2].latitude,
                                                  line[line.count / 2].longitude)
            return [mode.rawValue, roles.joined(separator: "+"), hm, mid].joined(separator: "|")
        case .transit, .bikeTransit:
            let trains = transitLegs.map {
                "\($0.lineName ?? "?")@\($0.fromName)@\(minute($0.plannedDeparture ?? $0.departure))>\($0.toName)"
            }
            // Zu Fuß ganz ohne Zug: dann eben die Abfahrt und die Strecke.
            guard !trains.isEmpty else { return [mode.rawValue, minute(leave), hm].joined(separator: "|") }
            return ([mode.rawValue] + trains).joined(separator: "|")
        }
    }

    var leave: Date { legs.first?.departure ?? .distantPast }
    var arrival: Date { legs.last?.arrival ?? .distantPast }
    /// When to start getting ready.
    var getReady: Date { leave.addingTimeInterval(-prep) }
    var duration: TimeInterval { arrival.timeIntervalSince(leave) }
    var transitLegs: [Leg] { legs.filter(\.isTransit) }
    var transfers: Int { max(0, transitLegs.count - 1) }
    var bikeLegs: [Leg] { legs.filter { $0.kind == .bike } }
    var bikeDistance: Double { bikeLegs.compactMap(\.distance).reduce(0, +) }
    /// Door-to-door average on the bike legs, stops included.
    var bikeAverageKmh: Double? {
        let t = bikeLegs.map(\.duration).reduce(0, +)
        return t > 0 ? bikeDistance / t * 3.6 : nil
    }
    var totalDistance: Double { legs.compactMap(\.length).reduce(0, +) }

    /// Arrival used for ranking: every change of train counts as `penalty`
    /// extra seconds, so a direct train beats a slightly faster one with changes.
    func weightedArrival(_ penalty: TimeInterval) -> Date {
        arrival.addingTimeInterval(Double(transfers) * penalty)
    }

    /// Mirror for arrival searches: a connection with a change has to leave
    /// that much later to be worth taking.
    func weightedLeave(_ penalty: TimeInterval) -> Date {
        leave.addingTimeInterval(-Double(transfers) * penalty)
    }

    var transferText: String? {
        transitLegs.isEmpty ? nil
            : (transfers == 0 ? L("direkt")
               : (transfers == 1 ? L("1× umsteigen") : L("%d× umsteigen", transfers)))
    }

    /// At least one leg whose bike carriage nobody has confirmed — shown with
    /// a warning instead of being hidden.
    var bikeCarriageUnclear: Bool {
        mode == .bikeTransit && transitLegs.contains { $0.bikeCarriage == .unknown }
    }

    /// Bike+rail using U-Bahn or tram somewhere: shown, but only as the
    /// alternative to S-Bahn/regional trains with a bike compartment.
    var isAlternative: Bool {
        mode == .bikeTransit && transitLegs.contains {
            if case .transit(_, let p) = $0.kind { !p.hasBikeCompartment } else { false }
        }
    }

}
