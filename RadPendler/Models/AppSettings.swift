import CoreLocation
import Foundation
import Observation

/// User preferences, persisted in UserDefaults on every change.
@Observable
final class AppSettings {
    /// Empty until the user picks one; then kept on the device.
    var origin: Place? = nil { didSet { save(origin, "origin") } }
    var destination: Place? = nil { didSet { save(destination, "destination") } }
    /// Minutes between "plan now" and walking out of the door.
    var prepMinutes: Int = 5 { didSet { defaults.set(prepMinutes, forKey: "prepMinutes") } }
    /// Average cycling speed; MapKit's own cycling ETA is ignored.
    /// Speed while rolling, without stops; lights are added per junction.
    /// (0.1.x stored an all-in average under "bikeSpeedKmh" — deliberately not read.)
    var bikeSpeedKmh: Double = AppSettings.defaultBikeSpeedKmh { didSet { defaults.set(bikeSpeedKmh, forKey: "bikeMovingSpeedKmh") } }
    /// Time to get the bike from the street onto the platform, and back.
    var bikeStationBufferMinutes: Int = 3 { didSet { defaults.set(bikeStationBufferMinutes, forKey: "bikeStationBufferMinutes") } }
    /// Farthest station the bike+rail search rides to, at either end.
    var maxBikeToStationKm: Double = 5 { didSet { defaults.set(maxBikeToStationKm, forKey: "maxBikeToStationKm") } }
    /// Added to every car trip for finding a parking space.
    var parkingMinutes: Int = 0 { didSet { defaults.set(parkingMinutes, forKey: "parkingMinutes") } }
    /// How many minutes of travel time one change of train is worth avoiding.
    var transferPenaltyMinutes: Int = 10 { didSet { defaults.set(transferPenaltyMinutes, forKey: "transferPenaltyMinutes") } }
    /// Quick departure choices: "in 15 min" or "um 8:00".
    var departurePresets: [DeparturePreset] = [.relative(15), .relative(60), .clock(8, 0), .clock(18, 0)] {
        didSet { defaults.set(departurePresets.map(\.stored), forKey: "departurePresets2") }
    }

    /// Places a route has to touch, e.g. "S Musterhausen" — routes that miss
    /// them are shown greyed out at the end of their section.
    var waypoints: [Place] = [] { didSet { defaults.set(try? JSONEncoder().encode(waypoints), forKey: "waypoints") } }
    /// true: a route must touch every fixed point, false: one is enough.
    var requireAllWaypoints: Bool = false { didSet { defaults.set(requireAllWaypoints, forKey: "requireAllWaypoints") } }

    /// Extra minutes before every departure that are not travel time.
    var departureBufferMinutes: Int = 0 { didSet { defaults.set(departureBufferMinutes, forKey: "departureBufferMinutes") } }
    /// How many minutes before the wanted arrival the trip should be there.
    var arrivalBufferMinutes: Int = 5 { didSet { defaults.set(arrivalBufferMinutes, forKey: "arrivalBufferMinutes") } }
    /// The address the commute goes to in the morning; trips towards it default
    /// to "be there at …" instead of "leave now".
    var workPlace: Place? = nil { didSet { save(workPlace, "workPlace") } }
    /// Where the commute comes back to. Marked wherever an address is shown,
    /// and offered first in the address search.
    var homePlace: Place? = nil { didSet { save(homePlace, "homePlace") } }
    /// Default arrival time for trips towards the work address.
    var workArrivalMinutes: Int = 9 * 60 { didSet { defaults.set(workArrivalMinutes, forKey: "workArrivalMinutes") } }
    /// Minutes before departure at which the countdown beeps.
    var alertMinutes: [Int] = [10, 5, 1] { didSet { defaults.set(alertMinutes, forKey: "alertMinutes") } }
    var alertsOn: Bool = true { didSet { defaults.set(alertsOn, forKey: "alertsOn") } }

    /// Addresses that have been used before, with how often — the list the
    /// search offers before anything is typed. Device only, like the addresses.
    var placeHistory: [PlaceUse] = [] {
        didSet { defaults.set(try? JSONEncoder().encode(placeHistory), forKey: "placeHistory") }
    }

    /// Which mode wins when two trips arrive at nearly the same time, and the
    /// order of the four boxes. The user's own by default: Rad vor Rad + Bahn
    /// vor Auto vor Bahn & Bus.
    var modeOrder: [TravelMode] = TravelMode.defaultOrder {
        didSet { defaults.set(modeOrder.map(\.rawValue), forKey: "modeOrder") }
    }
    /// Which of the bike routes the app suggests, and in which order they are
    /// stepped through. First = the one that gets recommended.
    var bikeVariantOrder: [BikeVariant] = BikeVariant.defaultOrder {
        didSet { defaults.set(bikeVariantOrder.map(\.rawValue), forKey: "bikeVariantOrder") }
    }
    var carVariantOrder: [CarVariant] = CarVariant.defaultOrder {
        didSet { defaults.set(carVariantOrder.map(\.rawValue), forKey: "carVariantOrder") }
    }
    /// From this much rain on the bike belongs in the train rather than on the
    /// whole way. Default: leichter Regen, which is what the app always did.
    var rainSwitchLevel: RainLevel = .light {
        didSet { defaults.set(rainSwitchLevel.rawValue, forKey: "rainSwitchLevel") }
    }

    /// Lines the app has seen in a route, and what the user decided about
    /// taking the bike on them. Open entries are the reason a trip can carry
    /// the warning "Mitnahme ungeklärt".
    var bikeLines: [BikeLine] = [] {
        didSet { defaults.set(try? JSONEncoder().encode(bikeLines), forKey: "bikeLines") }
    }

    /// Which timetable answers. Automatic keeps the VBB for the region it
    /// knows best and hands everything beyond it to Transitous.
    var timetableSource: TimetableSource = .automatic {
        didSet { defaults.set(timetableSource.rawValue, forKey: "timetableSource") }
    }

    /// Average wait per traffic light on the bike (half of them are green).
    var signalWaitSeconds: Int = 20 { didSet { defaults.set(signalWaitSeconds, forKey: "signalWaitSeconds") } }

    /// 29 km/h rolling + 20 s per signalised junction reproduces the user's
    /// measured ~21 km/h door-to-door on the Berlin commute it was built for.
    static let defaultBikeSpeedKmh = 29.0

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// Reads everything out of UserDefaults. Also the way back in after iCloud
    /// handed us another device's settings — every property keeps what it has
    /// when the key is missing, so a partial store cannot wipe anything.
    func load() {
        origin = Self.place("origin", defaults) ?? origin
        destination = Self.place("destination", defaults) ?? destination
        workPlace = Self.place("workPlace", defaults) ?? workPlace
        homePlace = Self.place("homePlace", defaults) ?? homePlace
        prepMinutes = defaults.object(forKey: "prepMinutes") as? Int ?? prepMinutes
        // 0.1.x stored an all-in average under "bikeSpeedKmh" — deliberately not read.
        bikeSpeedKmh = defaults.object(forKey: "bikeMovingSpeedKmh") as? Double ?? bikeSpeedKmh
        bikeStationBufferMinutes = defaults.object(forKey: "bikeStationBufferMinutes") as? Int ?? bikeStationBufferMinutes
        maxBikeToStationKm = defaults.object(forKey: "maxBikeToStationKm") as? Double ?? maxBikeToStationKm
        parkingMinutes = defaults.object(forKey: "parkingMinutes") as? Int ?? parkingMinutes
        transferPenaltyMinutes = defaults.object(forKey: "transferPenaltyMinutes") as? Int ?? transferPenaltyMinutes
        signalWaitSeconds = defaults.object(forKey: "signalWaitSeconds") as? Int ?? signalWaitSeconds
        departurePresets = (defaults.array(forKey: "departurePresets2") as? [String])?
            .compactMap(DeparturePreset.init(stored:)) ?? departurePresets
        waypoints = defaults.data(forKey: "waypoints").flatMap { try? JSONDecoder().decode([Place].self, from: $0) } ?? waypoints
        requireAllWaypoints = defaults.object(forKey: "requireAllWaypoints") as? Bool ?? requireAllWaypoints
        departureBufferMinutes = defaults.object(forKey: "departureBufferMinutes") as? Int ?? departureBufferMinutes
        arrivalBufferMinutes = defaults.object(forKey: "arrivalBufferMinutes") as? Int ?? arrivalBufferMinutes
        workArrivalMinutes = defaults.object(forKey: "workArrivalMinutes") as? Int ?? workArrivalMinutes
        alertMinutes = defaults.array(forKey: "alertMinutes") as? [Int] ?? alertMinutes
        alertsOn = defaults.object(forKey: "alertsOn") as? Bool ?? alertsOn
        placeHistory = defaults.data(forKey: "placeHistory")
            .flatMap { try? JSONDecoder().decode([PlaceUse].self, from: $0) } ?? placeHistory
        bikeLines = defaults.data(forKey: "bikeLines")
            .flatMap { try? JSONDecoder().decode([BikeLine].self, from: $0) } ?? bikeLines
        timetableSource = (defaults.string(forKey: "timetableSource"))
            .flatMap(TimetableSource.init(rawValue:)) ?? timetableSource
        modeOrder = storedOrder(defaults.array(forKey: "modeOrder") as? [String], fallback: TravelMode.defaultOrder)
        bikeVariantOrder = storedOrder(defaults.array(forKey: "bikeVariantOrder") as? [String],
                                       fallback: BikeVariant.defaultOrder)
        carVariantOrder = storedOrder(defaults.array(forKey: "carVariantOrder") as? [String],
                                      fallback: CarVariant.defaultOrder)
        rainSwitchLevel = (defaults.object(forKey: "rainSwitchLevel") as? Int)
            .flatMap(RainLevel.init(rawValue:)) ?? rainSwitchLevel
    }

    /// Back to what the app ships with — one button beats four drags.
    func resetPriorities() {
        modeOrder = TravelMode.defaultOrder
        bikeVariantOrder = BikeVariant.defaultOrder
        carVariantOrder = CarVariant.defaultOrder
        rainSwitchLevel = .light
    }

    /// Called whenever an address is picked, wherever it was picked.
    func remember(_ place: Place) {
        placeHistory = placeHistory.recording(place)
    }

    /// Called after every plan: whatever lines it used go into the list.
    func noteLines(_ seen: [(name: String, known: BikeCarriage)]) {
        let updated = bikeLines.noting(seen)
        guard updated != bikeLines else { return }
        bikeLines = updated
    }

    func setBikeLine(_ name: String, allowed: Bool?) {
        if let i = bikeLines.firstIndex(where: { $0.name == name }) {
            bikeLines[i].allowed = allowed
        } else {
            bikeLines.append(BikeLine(name: name, allowed: allowed, lastSeen: .now))
        }
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
    func isWork(_ place: Place?) -> Bool { role(of: place) == .work }

    /// Which of the two named addresses this is, if either. Within 150 m counts
    /// as the same place: a pin dropped on the other side of the house is still
    /// home.
    func role(of place: Place?) -> PlaceRole? {
        guard let place else { return nil }
        if let home = homePlace, place.coordinate.distance(to: home.coordinate) < 150 { return .home }
        if let work = workPlace, place.coordinate.distance(to: work.coordinate) < 150 { return .work }
        return nil
    }

    func place(for role: PlaceRole) -> Place? { role == .home ? homePlace : workPlace }

    func setPlace(_ place: Place?, for role: PlaceRole) {
        if role == .home { homePlace = place } else { workPlace = place }
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
                     departureBufferMinutes: departureBufferMinutes, arrivalBufferMinutes: arrivalBufferMinutes,
                     modeOrder: modeOrder, bikeVariantOrder: bikeVariantOrder,
                     carVariantOrder: carVariantOrder, rainSwitchLevel: rainSwitchLevel,
                     bikeLineStatus: bikeLines.status, timetableSource: timetableSource)
    }

    private func save(_ place: Place?, _ key: String) {
        guard let place else { return defaults.removeObject(forKey: key) }
        defaults.set(try? JSONEncoder().encode(place), forKey: key)
    }

    private static func place(_ key: String, _ defaults: UserDefaults) -> Place? {
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
    var modeOrder: [TravelMode] = TravelMode.defaultOrder
    var bikeVariantOrder: [BikeVariant] = BikeVariant.defaultOrder
    var carVariantOrder: [CarVariant] = CarVariant.defaultOrder
    var rainSwitchLevel: RainLevel = .light
    /// Line name → whether the bike may come. Missing means undecided, which
    /// is shown with a warning rather than hidden.
    var bikeLineStatus: [String: Bool] = [:]
    var timetableSource: TimetableSource = .automatic
    /// Beyond this, the whole way by bike is a curiosity rather than a plan:
    /// its box moves to the end of the row and the OpenStreetMap corridor gets
    /// too big to ask Overpass for.
    var longTripKm = 100.0

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

    /// What is known about taking the bike on this leg: what the user decided
    /// beats what the timetable said, because the user has stood on the
    /// platform and the timetable has not.
    func carriage(_ leg: Leg) -> BikeCarriage {
        guard let line = leg.lineName else { return .yes }
        if let decided = bikeLineStatus[line] { return decided ? .yes : .no }
        return leg.bikeCarriage
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

/// Reads a stored order back. What the stored list does not mention is appended
/// in its default position — a variant added in a later version must not vanish
/// because an older device wrote the list before it existed.
func storedOrder<T: RawRepresentable & Equatable>(_ stored: [T.RawValue]?, fallback: [T]) -> [T] {
    guard let stored else { return fallback }
    let known = stored.compactMap(T.init(rawValue:))
    return known + fallback.filter { !known.contains($0) }
}

/// Where the timetable comes from.
enum TimetableSource: String, CaseIterable, Identifiable {
    /// VBB inside Berlin and Brandenburg, Transitous everywhere else.
    case automatic
    /// The VBB's own HAFAS: the best real-time data for the region, and the
    /// only one that states bike carriage per train.
    case vbb
    /// Transitous (MOTIS) on the nationwide DELFI dataset and beyond.
    case transitous

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatisch"
        case .vbb: "VBB"
        case .transitous: "Transitous"
        }
    }

    /// Berlin and Brandenburg, generously drawn. Inside it the VBB knows more
    /// than a nationwide dataset does — outside it, it knows nothing.
    static let vbbArea = (south: 51.35, west: 11.26, north: 53.56, east: 14.77)

    static func covers(_ c: CLLocationCoordinate2D) -> Bool {
        c.latitude >= vbbArea.south && c.latitude <= vbbArea.north
            && c.longitude >= vbbArea.west && c.longitude <= vbbArea.east
    }

    /// The source that actually answers for this pair of places.
    func resolved(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> TimetableSource {
        guard self == .automatic else { return self }
        return Self.covers(from) && Self.covers(to) ? .vbb : .transitous
    }
}
