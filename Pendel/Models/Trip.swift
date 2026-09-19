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
    /// Everything but buses — BVG buses do not take bikes.
    static let bikeSearchMask = allCases.filter { $0 != .bus }.reduce(0) { $0 | $1.rawValue }
    static let allMask = allCases.reduce(0) { $0 | $1.rawValue }

    init(cls: Int) {
        self = TransitProduct(rawValue: cls) ?? .regional
    }
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

    var leave: Date { legs.first?.departure ?? .distantPast }
    var arrival: Date { legs.last?.arrival ?? .distantPast }
    /// When to start getting ready.
    var getReady: Date { leave.addingTimeInterval(-prep) }
    var duration: TimeInterval { arrival.timeIntervalSince(leave) }
    var transitLegs: [Leg] { legs.filter(\.isTransit) }
    var transfers: Int { max(0, transitLegs.count - 1) }
    var bikeLegs: [Leg] { legs.filter { $0.kind == .bike } }
    var bikeDistance: Double { bikeLegs.compactMap(\.distance).reduce(0, +) }
    var walkDistance: Double { legs.filter { $0.kind == .walk }.compactMap(\.distance).reduce(0, +) }

}
