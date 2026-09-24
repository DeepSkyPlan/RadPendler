import CoreLocation
import Foundation

enum TravelMode: String, CaseIterable, Identifiable {
    case bike, bikeTransit, transit, car

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bike: "Fahrrad"
        case .bikeTransit: "Rad + Bahn"
        case .transit: "Bus & Bahn"
        case .car: "Auto"
        }
    }

    var symbol: String {
        switch self {
        case .bike: "bicycle"
        case .bikeTransit: "bicycle.circle.fill"
        case .transit: "tram.fill"
        case .car: "car.fill"
        }
    }

    /// What the app ships with — the user can reorder it in the settings, and
    /// that order decides which mode wins when two trips arrive at nearly the
    /// same time, and in which order the four boxes stand.
    static let defaultOrder: [TravelMode] = [.bike, .bikeTransit, .car, .transit]

    /// For the one line that has to hold all four: "Rad › Rad+Bahn › Auto › ÖPNV".
    var short: String {
        switch self {
        case .bike: "Rad"
        case .bikeTransit: "Rad+Bahn"
        case .transit: "ÖPNV"
        case .car: "Auto"
        }
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

    var title: String {
        switch self {
        case .fastest: "schnellst"
        case .shortest: "kürzest"
        case .balanced: "optimal"
        case .quiet: "ruhigst"
        case .lowTraffic: "verkehrsarm"
        }
    }

    var symbol: String {
        switch self {
        case .fastest: "hare"
        case .shortest: "ruler"
        case .balanced: "checkmark.seal"
        case .quiet: "leaf"
        case .lowTraffic: "road.lanes"
        }
    }

    static func < (a: BikeVariant, b: BikeVariant) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }

    /// Ships with "optimal" first: that is the one the app suggests. The user
    /// can put "ruhigst" or "kürzest" in front of it.
    static let defaultOrder: [BikeVariant] = [.balanced, .fastest, .quiet, .lowTraffic, .shortest]
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
        case .fastest: "schnellst"
        case .shortest: "kürzest"
        case .balanced: "optimal"
        case .fewSignals: "wenig Ampeln"
        case .alternative: "Alternative"
        }
    }

    static func < (a: CarVariant, b: CarVariant) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }

    static let defaultOrder: [CarVariant] = [.balanced, .fastest, .shortest, .fewSignals, .alternative]
}

/// The chosen car line and what sets it apart from the others.
struct CarRouteInfo {
    var variants: [CarVariant]
    /// Signalised junctions along the way; nil when OpenStreetMap was unreachable.
    var signals: Int?
    var signalPoints: [CLLocationCoordinate2D] = []

    /// Already in the user's order; the first one names the route.
    var title: String { variants.map(\.title).joined(separator: " · ") }
}

struct BikeRouteInfo {
    var variants: [BikeVariant]
    var stats: BikeRouteStats?
    /// BRouter profile or "Apple" — which router drew this line.
    var source: String
    /// Metres per road class, where the router said. Empty for Apple's line.
    var mix = RoadMix()
    /// The same with positions, handed to a recording so the ride can be
    /// attributed to the same classes afterwards.
    var roadPoints: [RoadPoint] = []
    /// Summierter Anstieg in Metern; nil, wenn der Router keine Höhen kennt.
    var ascent: Double? = nil

    /// Already in the order the user put the variants in; the first is the one
    /// that decides what the box says. Leer heißt: diese Linie ist in keiner
    /// Hinsicht die beste — ein anderer Weg ist sie trotzdem.
    var title: String { variants.isEmpty ? "Alternative" : variants.map(\.title).joined(separator: " · ") }
    /// Was der Kasten schreibt: der erste Name, oder „Alternative".
    var shortTitle: String { variants.first?.title ?? "Alternative" }
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
    let id = UUID()
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
        transitLegs.isEmpty ? nil : (transfers == 0 ? "direkt" : "\(transfers)× umsteigen")
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
