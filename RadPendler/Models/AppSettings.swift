import Foundation
import Observation

/// User preferences, persisted in UserDefaults on every change.
@Observable
final class AppSettings {
    /// Empty until the user picks one; then kept on the device.
    var origin: Place? { didSet { save(origin, "origin") } }
    var destination: Place? { didSet { save(destination, "destination") } }
    /// Minutes between "plan now" and walking out of the door.
    var prepMinutes: Int { didSet { defaults.set(prepMinutes, forKey: "prepMinutes") } }
    /// Average cycling speed; MapKit's own cycling ETA is ignored.
    /// Speed while rolling, without stops; lights are added per junction.
    /// (0.1.x stored an all-in average under "bikeSpeedKmh" — deliberately not read.)
    var bikeSpeedKmh: Double { didSet { defaults.set(bikeSpeedKmh, forKey: "bikeMovingSpeedKmh") } }
    /// Time to get the bike from the street onto the platform, and back.
    var bikeStationBufferMinutes: Int { didSet { defaults.set(bikeStationBufferMinutes, forKey: "bikeStationBufferMinutes") } }
    /// Farthest station the bike+rail search rides to, at either end.
    var maxBikeToStationKm: Double { didSet { defaults.set(maxBikeToStationKm, forKey: "maxBikeToStationKm") } }
    /// Added to every car trip for finding a parking space.
    var parkingMinutes: Int { didSet { defaults.set(parkingMinutes, forKey: "parkingMinutes") } }
    /// How many minutes of travel time one change of train is worth avoiding.
    var transferPenaltyMinutes: Int { didSet { defaults.set(transferPenaltyMinutes, forKey: "transferPenaltyMinutes") } }
    /// Quick departure choices: "in 15 min" or "um 8:00".
    var departurePresets: [DeparturePreset] {
        didSet { defaults.set(departurePresets.map(\.stored), forKey: "departurePresets2") }
    }

    /// Places a route has to touch, e.g. "S Musterhausen" — routes that miss
    /// them are shown greyed out at the end of their section.
    var waypoints: [Place] { didSet { defaults.set(try? JSONEncoder().encode(waypoints), forKey: "waypoints") } }
    /// true: a route must touch every fixed point, false: one is enough.
    var requireAllWaypoints: Bool { didSet { defaults.set(requireAllWaypoints, forKey: "requireAllWaypoints") } }

    /// Extra minutes before every departure that are not travel time.
    var departureBufferMinutes: Int { didSet { defaults.set(departureBufferMinutes, forKey: "departureBufferMinutes") } }
    /// How many minutes before the wanted arrival the trip should be there.
    var arrivalBufferMinutes: Int { didSet { defaults.set(arrivalBufferMinutes, forKey: "arrivalBufferMinutes") } }
    /// The address the commute goes to in the morning; trips towards it default
    /// to "be there at …" instead of "leave now".
    var workPlace: Place? { didSet { save(workPlace, "workPlace") } }
    /// Default arrival time for trips towards the work address.
    var workArrivalMinutes: Int { didSet { defaults.set(workArrivalMinutes, forKey: "workArrivalMinutes") } }
    /// Minutes before departure at which the countdown beeps.
    var alertMinutes: [Int] { didSet { defaults.set(alertMinutes, forKey: "alertMinutes") } }
    var alertsOn: Bool { didSet { defaults.set(alertsOn, forKey: "alertsOn") } }

    /// Addresses that have been used before, with how often — the list the
    /// search offers before anything is typed. Device only, like the addresses.
    var placeHistory: [PlaceUse] {
        didSet { defaults.set(try? JSONEncoder().encode(placeHistory), forKey: "placeHistory") }
    }

    /// Average wait per traffic light on the bike (half of them are green).
    var signalWaitSeconds: Int { didSet { defaults.set(signalWaitSeconds, forKey: "signalWaitSeconds") } }

    /// 29 km/h rolling + 20 s per signalised junction reproduces the user's
    /// measured ~21 km/h door-to-door on the Musterstraße–Beispielweg commute.
    static let defaultBikeSpeedKmh = 29.0

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        origin = Self.load("origin", defaults)
        destination = Self.load("destination", defaults)
        prepMinutes = defaults.object(forKey: "prepMinutes") as? Int ?? 5
        bikeSpeedKmh = defaults.object(forKey: "bikeMovingSpeedKmh") as? Double ?? Self.defaultBikeSpeedKmh
        bikeStationBufferMinutes = defaults.object(forKey: "bikeStationBufferMinutes") as? Int ?? 3
        maxBikeToStationKm = defaults.object(forKey: "maxBikeToStationKm") as? Double ?? 5
        parkingMinutes = defaults.object(forKey: "parkingMinutes") as? Int ?? 0
        transferPenaltyMinutes = defaults.object(forKey: "transferPenaltyMinutes") as? Int ?? 10
        signalWaitSeconds = defaults.object(forKey: "signalWaitSeconds") as? Int ?? 20
        departurePresets = (defaults.array(forKey: "departurePresets2") as? [String])?
            .compactMap(DeparturePreset.init(stored:)) ?? [.relative(15), .relative(60), .clock(8, 0), .clock(18, 0)]
        waypoints = defaults.data(forKey: "waypoints").flatMap { try? JSONDecoder().decode([Place].self, from: $0) } ?? []
        requireAllWaypoints = defaults.object(forKey: "requireAllWaypoints") as? Bool ?? false
        departureBufferMinutes = defaults.object(forKey: "departureBufferMinutes") as? Int ?? 0
        arrivalBufferMinutes = defaults.object(forKey: "arrivalBufferMinutes") as? Int ?? 5
        workPlace = Self.load("workPlace", defaults)
        workArrivalMinutes = defaults.object(forKey: "workArrivalMinutes") as? Int ?? 9 * 60
        alertMinutes = defaults.array(forKey: "alertMinutes") as? [Int] ?? [10, 5, 1]
        alertsOn = defaults.object(forKey: "alertsOn") as? Bool ?? true
        placeHistory = defaults.data(forKey: "placeHistory")
            .flatMap { try? JSONDecoder().decode([PlaceUse].self, from: $0) } ?? []
    }

    /// Called whenever an address is picked, wherever it was picked.
    func remember(_ place: Place) {
        placeHistory = placeHistory.recording(place)
    }

    func forget(_ use: PlaceUse) {
        placeHistory.removeAll { $0.id == use.id }
    }

    func swapDirection() {
        (origin, destination) = (destination, origin)
    }

    /// Both addresses set: only then can a trip be planned.
    var isReady: Bool { origin != nil && destination != nil }

    /// Is this place the one the morning commute goes to?
    func isWork(_ place: Place?) -> Bool {
        guard let place, let work = workPlace else { return false }
        return place.coordinate.distance(to: work.coordinate) < 150
    }

    func clearPlaces() {
        origin = nil
        destination = nil
    }

    var snapshot: PlanSettings {
        PlanSettings(prepMinutes: prepMinutes, bikeSpeedKmh: bikeSpeedKmh,
                     bikeStationBufferMinutes: bikeStationBufferMinutes,
                     maxBikeToStationKm: maxBikeToStationKm, parkingMinutes: parkingMinutes,
                     transferPenaltyMinutes: transferPenaltyMinutes, signalWaitSeconds: signalWaitSeconds,
                     waypoints: waypoints, requireAllWaypoints: requireAllWaypoints,
                     departureBufferMinutes: departureBufferMinutes, arrivalBufferMinutes: arrivalBufferMinutes)
    }

    private func save(_ place: Place?, _ key: String) {
        guard let place else { return defaults.removeObject(forKey: key) }
        defaults.set(try? JSONEncoder().encode(place), forKey: key)
    }

    private static func load(_ key: String, _ defaults: UserDefaults) -> Place? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Place.self, from: $0) }
    }
}

/// Value copy of the settings a planning run uses, so a run is not affected by
/// edits made while it is in flight.
struct PlanSettings: Equatable {
    var prepMinutes = 5
    var bikeSpeedKmh = AppSettings.defaultBikeSpeedKmh
    var bikeStationBufferMinutes = 3
    var maxBikeToStationKm = 5.0
    var parkingMinutes = 0
    var transferPenaltyMinutes = 10
    var signalWaitSeconds = 20
    var waypoints: [Place] = []
    var requireAllWaypoints = false
    var departureBufferMinutes = 0
    var arrivalBufferMinutes = 5

    var departureBuffer: TimeInterval { TimeInterval(departureBufferMinutes * 60) }
    var arrivalBuffer: TimeInterval { TimeInterval(arrivalBufferMinutes * 60) }
    /// How close a route has to come to a fixed point to count as passing it.
    var waypointRadius: Double = 300

    var transferPenalty: TimeInterval { TimeInterval(transferPenaltyMinutes * 60) }
    var bikeSpeedMps: Double { bikeSpeedKmh / 3.6 }
    var prep: TimeInterval { TimeInterval(prepMinutes * 60) }
    var bikeStationBuffer: TimeInterval { TimeInterval(bikeStationBufferMinutes * 60) }

    /// Riding time for a distance at the configured speed.
    func bikeTime(_ meters: Double) -> TimeInterval {
        (meters / bikeSpeedMps).rounded()
    }

    /// Riding time plus the expected wait at the route's traffic lights.
    func rideTime(_ r: StreetRoute) -> TimeInterval {
        bikeTime(r.distance) + Double(r.signals * signalWaitSeconds)
    }
}

/// A quick choice for the start time: relative ("in 15 min") or a clock time
/// today or tomorrow ("um 8:00").
enum DeparturePreset: Hashable {
    case relative(Int)      // minutes from now
    case clock(Int, Int)    // hour, minute

    var title: String {
        switch self {
        case .relative(let m) where m < 60: "in \(m) min"
        case .relative(let m) where m % 60 == 0: "in \(m / 60) h"
        case .relative(let m): "in \(m / 60) h \(m % 60) min"
        case .clock(let h, let m): m == 0 ? "um \(h) Uhr" : String(format: "um %d:%02d", h, m)
        }
    }

    /// The next moment this preset means, counted from `now`; a clock time that
    /// has passed today means tomorrow.
    func date(from now: Date = .now, calendar: Calendar = .current) -> Date {
        switch self {
        case .relative(let m):
            return now.addingTimeInterval(Double(m) * 60)
        case .clock(let h, let m):
            let today = calendar.date(bySettingHour: h, minute: m, second: 0, of: now) ?? now
            return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today) ?? today
        }
    }

    var stored: String {
        switch self {
        case .relative(let m): "r\(m)"
        case .clock(let h, let m): "c\(h):\(m)"
        }
    }

    init?(stored: String) {
        if stored.hasPrefix("r"), let m = Int(stored.dropFirst()) { self = .relative(m); return }
        if stored.hasPrefix("c") {
            let parts = stored.dropFirst().split(separator: ":").compactMap { Int($0) }
            if parts.count == 2 { self = .clock(parts[0], parts[1]); return }
        }
        return nil
    }

    static let choices: [DeparturePreset] = [.relative(5), .relative(10), .relative(15), .relative(30),
                                             .relative(60), .relative(120),
                                             .clock(6, 0), .clock(7, 0), .clock(8, 0), .clock(9, 0),
                                             .clock(12, 0), .clock(16, 0), .clock(17, 0), .clock(18, 0), .clock(20, 0)]
}
