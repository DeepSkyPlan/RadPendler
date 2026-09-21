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

    /// When two options arrive at nearly the same time, the more active one wins.
    var preference: Int {
        switch self {
        case .bike: 0
        case .bikeTransit: 1
        case .transit: 2
        case .car: 3
        }
    }
}

/// HAFAS product classes as the VBB profile numbers them.
enum TransitProduct: Int, CaseIterable {
    case suburban = 1, subway = 2, tram = 4, bus = 8, ferry = 16, express = 32, regional = 64

    /// S-Bahn, U-Bahn and regional trains: the stations worth riding a bike to.
    static let bikeStationMask = suburban.rawValue | subway.rawValue | regional.rawValue
    /// S-Bahn and regional trains always have a bike compartment — the
    /// preferred way to take the bike. U-Bahn and tram are only the alternative.
    static let bikeCompartmentMask = suburban.rawValue | regional.rawValue

    var hasBikeCompartment: Bool { rawValue & Self.bikeCompartmentMask != 0 }
    /// Everything but buses — BVG buses do not take bikes.
    static let bikeSearchMask = allCases.filter { $0 != .bus }.reduce(0) { $0 | $1.rawValue }
    static let allMask = allCases.reduce(0) { $0 | $1.rawValue }

    init(cls: Int) {
        self = TransitProduct(rawValue: cls) ?? .regional
    }
}

/// Which of the bike route variants an option is; one route can be several.
enum BikeVariant: String, CaseIterable, Comparable {
    case fastest, shortest, balanced, quiet

    var title: String {
        switch self {
        case .fastest: "schnellst"
        case .shortest: "kürzest"
        case .balanced: "optimal"
        case .quiet: "ruhigst"
        }
    }

    var symbol: String {
        switch self {
        case .fastest: "hare"
        case .shortest: "ruler"
        case .balanced: "checkmark.seal"
        case .quiet: "leaf"
        }
    }

    static func < (a: BikeVariant, b: BikeVariant) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

/// Which of the car alternatives an option is; one route can be several.
/// Apple returns two or three lines for a commute — the fastest is the
/// default, the other roles only get a label when a different line wins them.
enum CarVariant: String, CaseIterable, Comparable {
    case fastest, shortest, fewSignals

    var title: String {
        switch self {
        case .fastest: "schnellst"
        case .shortest: "kürzest"
        case .fewSignals: "wenig Ampeln"
        }
    }

    static func < (a: CarVariant, b: CarVariant) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

/// The chosen car line and what sets it apart from the others.
struct CarRouteInfo {
    var variants: [CarVariant]
    /// Signalised junctions along the way; nil when OpenStreetMap was unreachable.
    var signals: Int?
    var signalPoints: [CLLocationCoordinate2D] = []

    var title: String { variants.sorted().map(\.title).joined(separator: " · ") }
}

struct BikeRouteInfo {
    var variants: [BikeVariant]
    var stats: BikeRouteStats?
    /// BRouter profile or "Apple" — which router drew this line.
    var source: String

    var title: String { variants.sorted().map(\.title).joined(separator: " · ") }
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
    /// For transit legs: HAFAS says this train carries bikes (remark "FK").
    var bikeCarriage = false
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

    /// The bike variant the recommendation considers (Mittelweg).
    var isDefaultBikeVariant: Bool {
        mode == .bike && (bikeRoute.map { $0.variants.contains(.balanced) } ?? true)
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
    var walkDistance: Double { legs.filter { $0.kind == .walk }.compactMap(\.distance).reduce(0, +) }
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

    /// Bike+rail using U-Bahn or tram somewhere: shown, but only as the
    /// alternative to S-Bahn/regional trains with a bike compartment.
    var isAlternative: Bool {
        mode == .bikeTransit && transitLegs.contains {
            if case .transit(_, let p) = $0.kind { !p.hasBikeCompartment } else { false }
        }
    }

}
