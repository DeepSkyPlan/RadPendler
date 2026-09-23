import CoreLocation
import Foundation

/// What kind of road a stretch is. Six buckets, because that is how one talks
/// about a commute: *wie viel davon war Hauptstraße?*
///
/// The classes come from OpenStreetMap's `highway=` tag, which BRouter hands
/// back per segment with every route it draws — so this costs no extra
/// request, no extra service and no extra key.
enum RoadClass: String, Codable, CaseIterable, Identifiable {
    case main, side, cycleway, path, footway, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .main: "Hauptstraße"
        case .side: "Nebenstraße"
        case .cycleway: "Radweg"
        case .path: "Weg"
        case .footway: "Fußweg"
        case .other: "sonstiges"
        }
    }

    var symbol: String {
        switch self {
        case .main: "road.lanes"
        case .side: "road.lanes.curved.right"
        case .cycleway: "bicycle"
        case .path: "tree"
        case .footway: "figure.walk"
        case .other: "questionmark"
        }
    }

    /// Order in the bar and in the legend: from the loudest to the quietest,
    /// which is also the order one cares about them.
    static let order: [RoadClass] = [.main, .side, .cycleway, .path, .footway, .other]

    /// `highway=…` as OpenStreetMap writes it.
    static func from(highway: String) -> RoadClass {
        switch highway {
        case "motorway", "motorway_link", "trunk", "trunk_link",
             "primary", "primary_link", "secondary", "secondary_link":
            .main
        case "tertiary", "tertiary_link", "unclassified", "residential",
             "living_street", "service", "road":
            .side
        case "cycleway": .cycleway
        case "path", "track", "bridleway": .path
        case "footway", "pedestrian", "steps", "corridor": .footway
        default: .other
        }
    }

    /// Pulls the class out of a BRouter `WayTags` string —
    /// `"highway=residential surface=asphalt …"`.
    ///
    /// A cycleway is not always tagged as one: a residential street with
    /// `bicycle=designated` rides like a bike path, and a way beside a main
    /// road with `cycleway=track` is one. Those count as Radweg, because that
    /// is what they are under the wheel.
    static func from(wayTags: String) -> RoadClass {
        var highway: String?
        var designated = false
        var separateTrack = false
        for pair in wayTags.split(separator: " ") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]), value = String(parts[1])
            switch key {
            case "highway": highway = value
            case "bicycle" where value == "designated": designated = true
            case "cycleway", "cycleway:both", "cycleway:left", "cycleway:right":
                if value == "track" { separateTrack = true }
            default: break
            }
        }
        guard let highway else { return .other }
        let base = from(highway: highway)
        if base == .cycleway { return .cycleway }
        // A designated bike way, whatever the street it is painted on.
        if designated, base == .side || base == .path || base == .footway { return .cycleway }
        if separateTrack, base == .main || base == .side { return .cycleway }
        return base
    }
}

/// Metres per road class along one route — or along one ride.
struct RoadMix: Codable, Equatable {
    private(set) var meters: [RoadClass: Double] = [:]

    init(meters: [RoadClass: Double] = [:]) { self.meters = meters }

    var total: Double { meters.values.reduce(0, +) }
    var isEmpty: Bool { total <= 0 }

    subscript(_ c: RoadClass) -> Double { meters[c] ?? 0 }

    mutating func add(_ metres: Double, to c: RoadClass) {
        guard metres > 0, metres.isFinite else { return }
        meters[c, default: 0] += metres
    }

    /// 0…1. Zero total gives zero, not a division by it.
    func share(_ c: RoadClass) -> Double {
        let t = total
        return t > 0 ? self[c] / t : 0
    }

    /// The classes that actually occur, in the fixed order, so the bar does
    /// not reshuffle itself between two routes.
    var present: [RoadClass] { RoadClass.order.filter { self[$0] > 0 } }

    /// The one line a box has room for: "62 % Nebenstraße".
    var headline: String? {
        guard let top = present.max(by: { self[$0] < self[$1] }), total > 0 else { return nil }
        return "\(Int((share(top) * 100).rounded())) % \(top.title)"
    }
}


/// One point of a route with the kind of road it lies on. Enough to say, of a
/// ride that happened, which metres were ridden on what — by asking which
/// stretch of the planned route each step was nearest to.
struct RoadPoint: Codable, Equatable {
    var lat: Double
    var lon: Double
    var cls: RoadClass

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }

    /// Farther than this from the planned line and the step is not on it —
    /// a detour, a wrong turn, a shortcut through a courtyard. Honest answer:
    /// "sonstiges".
    static let matchRadius = 60.0

    /// Nearest road point to a coordinate, searching forward from `from`.
    /// A ride runs along the route, so the last match is where the next one
    /// starts — scanning the whole list per step would be quadratic.
    static func nearest(_ points: [RoadPoint], to c: CLLocationCoordinate2D,
                        from: Int) -> (index: Int, cls: RoadClass)? {
        guard !points.isEmpty else { return nil }
        let mPerDegLat = 111_320.0
        let mPerDegLon = mPerDegLat * cos(c.latitude * .pi / 180)
        let lo = Swift.max(0, from - 5)
        var best: (Int, Double)?
        var i = lo
        while i < points.count {
            let dx = (points[i].lon - c.longitude) * mPerDegLon
            let dy = (points[i].lat - c.latitude) * mPerDegLat
            let d2 = dx * dx + dy * dy
            if best == nil || d2 < best!.1 { best = (i, d2) }
            // Clearly moving away again, and far enough past the best: stop.
            if let best, d2 > best.1, i > best.0 + 40 { break }
            i += 1
        }
        guard let best, best.1 <= matchRadius * matchRadius else { return nil }
        return (best.0, points[best.0].cls)
    }
}
