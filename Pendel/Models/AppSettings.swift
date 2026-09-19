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
    /// Quick departure choices in minutes from now, e.g. 15, 60, 480.
    var departurePresets: [Int] { didSet { defaults.set(departurePresets, forKey: "departurePresets") } }

    /// Places a route has to touch, e.g. "S Musterhausen" — routes that miss
    /// them are shown greyed out at the end of their section.
    var waypoints: [Place] { didSet { defaults.set(try? JSONEncoder().encode(waypoints), forKey: "waypoints") } }
    /// true: a route must touch every fixed point, false: one is enough.
    var requireAllWaypoints: Bool { didSet { defaults.set(requireAllWaypoints, forKey: "requireAllWaypoints") } }

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
        departurePresets = defaults.array(forKey: "departurePresets") as? [Int] ?? [15, 60, 480, 1080]
        waypoints = defaults.data(forKey: "waypoints").flatMap { try? JSONDecoder().decode([Place].self, from: $0) } ?? []
        requireAllWaypoints = defaults.object(forKey: "requireAllWaypoints") as? Bool ?? false
    }

    func swapDirection() {
        (origin, destination) = (destination, origin)
    }

    /// Both addresses set: only then can a trip be planned.
    var isReady: Bool { origin != nil && destination != nil }

    /// "in 15 min", "in 1 h", "in 8 h 30 min".
    static func offsetTitle(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "in \(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "in \(h) h" : "in \(h) h \(m) min"
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
                     waypoints: waypoints, requireAllWaypoints: requireAllWaypoints)
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
