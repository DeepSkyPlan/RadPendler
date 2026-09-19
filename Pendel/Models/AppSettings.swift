import Foundation
import Observation

/// User preferences, persisted in UserDefaults on every change.
@Observable
final class AppSettings {
    var origin: Place { didSet { save(origin, "origin") } }
    var destination: Place { didSet { save(destination, "destination") } }
    /// Minutes between "plan now" and walking out of the door.
    var prepMinutes: Int { didSet { defaults.set(prepMinutes, forKey: "prepMinutes") } }
    /// Average cycling speed; MapKit's own cycling ETA is ignored.
    var bikeSpeedKmh: Double { didSet { defaults.set(bikeSpeedKmh, forKey: "bikeSpeedKmh") } }
    /// Time to get the bike from the street onto the platform, and back.
    var bikeStationBufferMinutes: Int { didSet { defaults.set(bikeStationBufferMinutes, forKey: "bikeStationBufferMinutes") } }
    /// Farthest station the bike+rail search rides to, at either end.
    var maxBikeToStationKm: Double { didSet { defaults.set(maxBikeToStationKm, forKey: "maxBikeToStationKm") } }
    /// Added to every car trip for finding a parking space.
    var parkingMinutes: Int { didSet { defaults.set(parkingMinutes, forKey: "parkingMinutes") } }
    /// How many minutes of travel time one change of train is worth avoiding.
    var transferPenaltyMinutes: Int { didSet { defaults.set(transferPenaltyMinutes, forKey: "transferPenaltyMinutes") } }
    /// Average wait per traffic light on the bike (half of them are green).
    var signalWaitSeconds: Int { didSet { defaults.set(signalWaitSeconds, forKey: "signalWaitSeconds") } }

    static let defaultBikeSpeedKmh = 21.0

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        origin = Self.migrated(Self.load("origin", defaults)) ?? .office
        destination = Self.migrated(Self.load("destination", defaults)) ?? .home
        prepMinutes = defaults.object(forKey: "prepMinutes") as? Int ?? 5
        bikeSpeedKmh = defaults.object(forKey: "bikeSpeedKmh") as? Double ?? Self.defaultBikeSpeedKmh
        bikeStationBufferMinutes = defaults.object(forKey: "bikeStationBufferMinutes") as? Int ?? 3
        maxBikeToStationKm = defaults.object(forKey: "maxBikeToStationKm") as? Double ?? 5
        parkingMinutes = defaults.object(forKey: "parkingMinutes") as? Int ?? 0
        transferPenaltyMinutes = defaults.object(forKey: "transferPenaltyMinutes") as? Int ?? 10
        signalWaitSeconds = defaults.object(forKey: "signalWaitSeconds") as? Int ?? 20
    }

    func swapDirection() {
        (origin, destination) = (destination, origin)
    }

    func resetPlaces() {
        origin = .office
        destination = .home
    }

    var snapshot: PlanSettings {
        PlanSettings(prepMinutes: prepMinutes, bikeSpeedKmh: bikeSpeedKmh,
                     bikeStationBufferMinutes: bikeStationBufferMinutes,
                     maxBikeToStationKm: maxBikeToStationKm, parkingMinutes: parkingMinutes,
                     transferPenaltyMinutes: transferPenaltyMinutes, signalWaitSeconds: signalWaitSeconds)
    }

    private func save(_ place: Place, _ key: String) {
        defaults.set(try? JSONEncoder().encode(place), forKey: key)
    }

    /// Earlier builds stored the office with Apple's postcode 10000 and/or
    /// Apple's geocode (52.5367319, 13.3605566) instead of the real entrance.
    private static func migrated(_ p: Place?) -> Place? {
        guard let p, p.name.hasPrefix("Musterstraße 1,"), p.latitude == 52.5367319 || p.name.contains("10000") else { return p }
        return .office
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
