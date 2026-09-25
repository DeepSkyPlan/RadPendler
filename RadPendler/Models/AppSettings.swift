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

    /// A standstill this long counts as a red light even where no map knows
    /// one. Nobody waits half a minute in the middle of a street for fun, and
    /// OpenStreetMap does not know every light — least of all the crossings
    /// that only behave like one.
    var signalStopSeconds: Int = 30 { didSet { defaults.set(signalStopSeconds, forKey: "signalStopSeconds") } }

    /// Junctions this rider has ridden through. Learned from the recorded
    /// rides and used from the next one on — for recognising a red light, and
    /// for the bike times, where such a junction costs what it was measured to
    /// cost instead of `signalWaitSeconds`.
    var learnedSignals: [LearnedSignal] = [] {
        didSet { defaults.set(try? JSONEncoder().encode(learnedSignals), forKey: "learnedSignals") }
    }

    /// Ab wie vielen Metern neben der geplanten Linie der Weg zum Ziel neu
    /// berechnet wird. 0 schaltet es ab — dann bleibt es beim Pfeil zurück
    /// zur alten Route.
    var replanOffRouteMeters: Double = 200 {
        didSet { defaults.set(replanOffRouteMeters, forKey: "replanOffRouteMeters") }
    }

    /// Oder: nach so vielen Minuten ohne Unterbrechung neben der Route, egal
    /// wie weit. 0 schaltet es ab. Beides zusammen heißt „was zuerst
    /// eintritt" — wer im Kreis um einen gesperrten Weg fährt, kommt nie weit
    /// genug weg und braucht trotzdem irgendwann einen neuen Vorschlag.
    var replanOffRouteMinutes: Double = 0 {
        didSet { defaults.set(replanOffRouteMinutes, forKey: "replanOffRouteMinutes") }
    }

    /// Wie viele Möglichkeiten je Verkehrsmittel gerechnet und angeboten
    /// werden — die obersten so vieler aus der jeweiligen Reihenfolge.
    /// Weniger heißt auch weniger Anfragen: für eine Rolle, die niemand sieht,
    /// wird keine Route mehr geholt.
    var optionsPerMode: Int = 3 {
        didSet { defaults.set(optionsPerMode, forKey: "optionsPerMode") }
    }

    /// Whether the screen may turn. On a handlebar an automatic rotation is a
    /// nuisance, not a feature.
    var orientation: OrientationLock = .auto {
        didSet { defaults.set(orientation.rawValue, forKey: "orientationLock") }
    }

    /// Womit eine **Fahrt** anfängt. Wer das Telefon einmal am Lenker
    /// festgestellt hat, will das bei jeder Fahrt — und danach wieder eine App,
    /// die sich dreht wie jede andere. Deshalb zwei Werte: dieser gilt ab
    /// „Fahrt starten", `orientation` geht am Ende auf „Automatisch" zurück.
    var rideOrientation: OrientationLock = .auto {
        didSet { defaults.set(rideOrientation.rawValue, forKey: "rideOrientationLock") }
    }

    /// Der Tür-zu-Tür-Schnitt der letzten aufgezeichneten Radfahrten, und der
    /// rollende dazu. Aus ihnen kommen `bikeSpeedKmh` und `signalWaitSeconds`,
    /// und der erste ist beim Planen die Probe aufs Exempel: rechnet die App
    /// eine Fahrzeit aus, die schneller ist als das, was dieser Fahrer auf
    /// dieser Art Strecke wirklich fährt, gewinnt die Messung.
    var measuredOverallKmh: Double? = nil {
        didSet { defaults.set(measuredOverallKmh, forKey: "measuredOverallKmh") }
    }
    var measuredMovingKmh: Double? = nil {
        didSet { defaults.set(measuredMovingKmh, forKey: "measuredMovingKmh") }
    }
    /// Aus wie vielen Fahrten die beiden Zahlen stammen. Unter
    /// `Self.calibrationRides` ist noch nichts gemessen, sondern geraten.
    var measuredRides: Int = 0 {
        didSet { defaults.set(measuredRides, forKey: "measuredRides") }
    }

    /// 29 km/h rolling + 20 s per signalised junction reproduces the user's
    /// measured ~21 km/h door-to-door on the Berlin commute it was built for.
    static let defaultBikeSpeedKmh = 29.0

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// Setzt nur, was sich wirklich unterscheidet.
    ///
    /// `@Observable` fragt nicht nach: jede Zuweisung meldet eine Änderung,
    /// auch wenn derselbe Wert wieder hineingeschrieben wird. `load()` läuft
    /// nach jeder Rückmeldung aus iCloud und weist dreißig Eigenschaften zu —
    /// ohne diesen Vergleich macht das jedes Mal den halben Ansichtsbaum
    /// ungültig, samt Karte, und schreibt dreißig unnötige Werte in die
    /// UserDefaults, deren Benachrichtigung dann wieder `CloudStore` weckt.
    /// Beim ersten Lesen wird trotzdem alles geschrieben: erst damit steht die
    /// vollständige Liste der Schlüssel in den UserDefaults, und darauf beruht
    /// `testEverySettingTheAppSavesAlsoTravelsThroughICloud` — der Test, der
    /// merkt, wenn eine neue Einstellung den Weg nach iCloud nicht findet.
    /// Einmal beim Start ist das nichts; dreißigmal je iCloud-Rückmeldung war
    /// das Problem.
    private var loadedOnce = false

    private func assign<T: Equatable>(_ path: ReferenceWritableKeyPath<AppSettings, T>, _ value: T) {
        guard !loadedOnce || self[keyPath: path] != value else { return }
        self[keyPath: path] = value
    }

    /// Reads everything out of UserDefaults. Also the way back in after iCloud
    /// handed us another device's settings — every property keeps what it has
    /// when the key is missing, so a partial store cannot wipe anything.
    func load() {
        assign(\.origin, Self.place("origin", defaults) ?? origin)
        assign(\.destination, Self.place("destination", defaults) ?? destination)
        assign(\.workPlace, Self.place("workPlace", defaults) ?? workPlace)
        assign(\.homePlace, Self.place("homePlace", defaults) ?? homePlace)
        assign(\.prepMinutes, defaults.object(forKey: "prepMinutes") as? Int ?? prepMinutes)
        // 0.1.x stored an all-in average under "bikeSpeedKmh" — deliberately not read.
        assign(\.bikeSpeedKmh, defaults.object(forKey: "bikeMovingSpeedKmh") as? Double ?? bikeSpeedKmh)
        assign(\.bikeStationBufferMinutes,
               defaults.object(forKey: "bikeStationBufferMinutes") as? Int ?? bikeStationBufferMinutes)
        assign(\.maxBikeToStationKm, defaults.object(forKey: "maxBikeToStationKm") as? Double ?? maxBikeToStationKm)
        assign(\.parkingMinutes, defaults.object(forKey: "parkingMinutes") as? Int ?? parkingMinutes)
        assign(\.transferPenaltyMinutes,
               defaults.object(forKey: "transferPenaltyMinutes") as? Int ?? transferPenaltyMinutes)
        assign(\.signalWaitSeconds, defaults.object(forKey: "signalWaitSeconds") as? Int ?? signalWaitSeconds)
        assign(\.departurePresets, (defaults.array(forKey: "departurePresets2") as? [String])?
            .compactMap(DeparturePreset.init(stored:)) ?? departurePresets)
        assign(\.waypoints, defaults.data(forKey: "waypoints")
            .flatMap { try? JSONDecoder().decode([Place].self, from: $0) } ?? waypoints)
        assign(\.requireAllWaypoints, defaults.object(forKey: "requireAllWaypoints") as? Bool ?? requireAllWaypoints)
        assign(\.departureBufferMinutes,
               defaults.object(forKey: "departureBufferMinutes") as? Int ?? departureBufferMinutes)
        assign(\.arrivalBufferMinutes, defaults.object(forKey: "arrivalBufferMinutes") as? Int ?? arrivalBufferMinutes)
        assign(\.workArrivalMinutes, defaults.object(forKey: "workArrivalMinutes") as? Int ?? workArrivalMinutes)
        assign(\.alertMinutes, defaults.array(forKey: "alertMinutes") as? [Int] ?? alertMinutes)
        assign(\.alertsOn, defaults.object(forKey: "alertsOn") as? Bool ?? alertsOn)
        assign(\.placeHistory, defaults.data(forKey: "placeHistory")
            .flatMap { try? JSONDecoder().decode([PlaceUse].self, from: $0) } ?? placeHistory)
        assign(\.bikeLines, defaults.data(forKey: "bikeLines")
            .flatMap { try? JSONDecoder().decode([BikeLine].self, from: $0) } ?? bikeLines)
        assign(\.timetableSource, (defaults.string(forKey: "timetableSource"))
            .flatMap(TimetableSource.init(rawValue:)) ?? timetableSource)
        assign(\.modeOrder, storedOrder(defaults.array(forKey: "modeOrder") as? [String],
                                        fallback: TravelMode.defaultOrder))
        assign(\.bikeVariantOrder, storedOrder(defaults.array(forKey: "bikeVariantOrder") as? [String],
                                               fallback: BikeVariant.defaultOrder))
        assign(\.carVariantOrder, storedOrder(defaults.array(forKey: "carVariantOrder") as? [String],
                                              fallback: CarVariant.defaultOrder))
        assign(\.rainSwitchLevel, (defaults.object(forKey: "rainSwitchLevel") as? Int)
            .flatMap(RainLevel.init(rawValue:)) ?? rainSwitchLevel)
        assign(\.signalStopSeconds, defaults.object(forKey: "signalStopSeconds") as? Int ?? signalStopSeconds)
        assign(\.learnedSignals, defaults.data(forKey: "learnedSignals")
            .flatMap { try? JSONDecoder().decode([LearnedSignal].self, from: $0) } ?? learnedSignals)
        assign(\.orientation, (defaults.string(forKey: "orientationLock"))
            .flatMap(OrientationLock.init(rawValue:)) ?? orientation)
        assign(\.replanOffRouteMeters,
               defaults.object(forKey: "replanOffRouteMeters") as? Double ?? replanOffRouteMeters)
        assign(\.replanOffRouteMinutes,
               defaults.object(forKey: "replanOffRouteMinutes") as? Double ?? replanOffRouteMinutes)
        assign(\.optionsPerMode, defaults.object(forKey: "optionsPerMode") as? Int ?? optionsPerMode)
        assign(\.rideOrientation, (defaults.string(forKey: "rideOrientationLock"))
            .flatMap(OrientationLock.init(rawValue:)) ?? rideOrientation)
        assign(\.measuredOverallKmh, defaults.object(forKey: "measuredOverallKmh") as? Double)
        assign(\.measuredMovingKmh, defaults.object(forKey: "measuredMovingKmh") as? Double)
        assign(\.measuredRides, defaults.object(forKey: "measuredRides") as? Int ?? measuredRides)
        loadedOnce = true
    }

    /// Was eine beendete Fahrt über die Kreuzungen auf ihr weiß: an welchen
    /// gewartet wurde, und an welchen eben nicht.
    ///
    /// Das zweite ist so wichtig wie das erste. Zählt man nur die Halte, ist
    /// der Mittelwert einer Ampel der Mittelwert der Male, an denen man
    /// gewartet hat — eine Ampel, die jede zweite Fahrt grün ist, kostete
    /// dann das Doppelte dessen, was sie wirklich kostet. Deshalb zählt jede
    /// Kreuzung, an der die aufgezeichnete Linie vorbeikam, eine Vorbeifahrt.
    ///
    /// `junctions` sind die Kreuzungen der geplanten Route — die aus
    /// OpenStreetMap und die schon gelernten.
    func learn(stops: [RideStop], track: [RidePoint] = [], junctions: [CLLocationCoordinate2D] = []) {
        var list = learnedSignals
        for stop in stops where stop.atSignal {
            list = LearnedSignal.recording(list, at: stop.coordinate, waited: stop.seconds)
        }
        // Eine Kreuzung, eine Vorbeifahrt. Die Liste kommt aus zwei Quellen —
        // den Ampeln der geplanten Route und den gelernten — und dieselbe
        // Kreuzung steht deshalb oft zweimal darin; zweimal gezählt hielte sie
        // für halb so teuer, wie sie ist.
        var counted = stops.filter(\.atSignal).map(\.coordinate)
        for j in junctions {
            // An dieser Kreuzung wurde gerade gehalten — der Halt hat seine
            // Vorbeifahrt schon mitgebracht.
            guard !counted.contains(where: { $0.distance(to: j) <= LearnedSignal.mergeRadius }) else { continue }
            guard track.contains(where: { $0.coordinate.distance(to: j) <= LearnedSignal.passRadius }) else { continue }
            counted.append(j)
            list = LearnedSignal.passing(list, at: j)
        }
        guard list != learnedSignals else { return }
        learnedSignals = list
    }

    /// So viele Fahrten müssen es sein, bevor gemessene Werte die
    /// eingestellten ablösen. Eine einzelne Fahrt ist Wetter, Wind und ein
    /// Zug, der vor der Schranke stand.
    static let calibrationRides = 3
    /// Und so viele werden angeschaut. Mehr wäre das Rad von vorletztem
    /// Winter; weniger schwankt mit jedem Regentag.
    static let calibrationWindow = 8

    /// Was die App über diesen Fahrer weiß, aus seinen eigenen Fahrten:
    /// rollendes Tempo und Tür-zu-Tür-Schnitt. Der Median, nicht der
    /// Mittelwert — eine Fahrt mit Platten darf den Schnitt nicht kippen.
    ///
    /// Das rollende Tempo landet in `bikeSpeedKmh`, also in der Einstellung,
    /// die der Nutzer auch selbst stellen kann: er soll sehen, womit gerechnet
    /// wird. Der Tür-zu-Tür-Schnitt bleibt daneben stehen, weil er beim Planen
    /// die Gegenprobe ist.
    func calibrate(from rides: [Ride], mode: TravelMode = .bike) {
        let relevant = rides
            .filter { $0.travelMode == mode && $0.meters >= 2_000 && $0.movingSeconds > 60 }
            .sorted { $0.started > $1.started }
            .prefix(Self.calibrationWindow)
        guard relevant.count >= Self.calibrationRides else { return }
        let moving = Self.median(relevant.map(\.movingKmh))
        let overall = Self.median(relevant.map(\.averageKmh))
        measuredRides = relevant.count
        measuredMovingKmh = moving
        measuredOverallKmh = overall
        // Die Einstellung folgt der Messung, gerundet auf das, was der
        // Stepper hergibt.
        let speed = (moving).rounded()
        if speed >= 10, speed <= 45, speed != bikeSpeedKmh { bikeSpeedKmh = speed }
        // Und die Ampelwartezeit folgt dem, was an Ampeln wirklich gewartet
        // wurde — siehe `signalMeasurement`.
        if let m = signalMeasurement, m.passes >= Self.signalCalibrationPasses {
            let seconds = Int((m.wait / Double(m.passes) / 5).rounded() * 5)
            let clamped = Swift.min(90, Swift.max(0, seconds))
            if clamped != signalWaitSeconds { signalWaitSeconds = clamped }
        }
    }

    static func median(_ values: [Double]) -> Double {
        let s = values.sorted()
        guard !s.isEmpty else { return 0 }
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    /// So viele Vorbeifahrten braucht es, bevor der gemessene Ampelschnitt den
    /// eingestellten ablöst. Zwei Pendelfahrten über zwanzig Kreuzungen.
    static let signalCalibrationPasses = 40

    /// Was an den Ampeln dieses Fahrers wirklich passiert: wie oft er an
    /// einer stand, wie oft er durchkam, und wie lange er zusammen gewartet
    /// hat. Aus den gelernten Kreuzungen — die zählen beides mit.
    var signalMeasurement: (passes: Int, stops: Int, wait: TimeInterval)? {
        guard !learnedSignals.isEmpty else { return nil }
        let passes = learnedSignals.reduce(0) { $0 + $1.passCount }
        guard passes > 0 else { return nil }
        return (passes, learnedSignals.reduce(0) { $0 + $1.stops },
                learnedSignals.reduce(0) { $0 + $1.totalWait })
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

    /// The commute, in one gesture: where one is standing decides where one is
    /// going. Standing at home means going to work, standing at work means
    /// going home, and anywhere else the clock decides — before the morning
    /// window closes it is still the way in.
    ///
    /// A pure function, because "which way round is the commute" is exactly
    /// the kind of rule that is wrong at 18:59 and nobody notices.
    static func commuteDestination(from here: CLLocationCoordinate2D?, home: Place?, work: Place?,
                                   now: Date = .now, workArrivalMinutes: Int = 9 * 60,
                                   calendar: Calendar = .current) -> Place? {
        if let here {
            if let home, here.distance(to: home.coordinate) < 400 { return work ?? home }
            if let work, here.distance(to: work.coordinate) < 400 { return home ?? work }
        }
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        // Four hours past the time one wants to be at work, the morning is over.
        let morning = minutes < workArrivalMinutes + 4 * 60
        return (morning ? work : home) ?? (morning ? home : work)
    }

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
                     carVariantOrder: carVariantOrder, optionsPerMode: optionsPerMode,
                     rainSwitchLevel: rainSwitchLevel,
                     bikeLineStatus: bikeLines.status, timetableSource: timetableSource,
                     learnedSignals: learnedSignals,
                     measuredOverallKmh: measuredRides >= Self.calibrationRides ? measuredOverallKmh : nil)
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
    /// Wie viele Möglichkeiten je Verkehrsmittel gerechnet werden.
    var optionsPerMode = 3
    var rainSwitchLevel: RainLevel = .light
    /// Line name → whether the bike may come. Missing means undecided, which
    /// is shown with a warning rather than hidden.
    var bikeLineStatus: [String: Bool] = [:]
    var timetableSource: TimetableSource = .automatic
    /// Junctions this rider has ridden through. They join the ones
    /// OpenStreetMap knows before a route is judged — and they bring their
    /// measured wait, where the mapped ones only get `signalWaitSeconds`.
    var learnedSignals: [LearnedSignal] = []
    /// Der gemessene Tür-zu-Tür-Schnitt dieses Fahrers, aus seinen
    /// aufgezeichneten Fahrten. nil, solange es zu wenige sind.
    var measuredOverallKmh: Double? = nil
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
        bikeTime(r.distance) + signalWait(signals: r.signals, learned: r.learnedSignals)
    }

    /// Was die Ampeln einer Route an Zeit kosten.
    ///
    /// Wo dieser Fahrer schon gemessen hat, gilt das Gemessene: eine Kreuzung,
    /// an der zwanzig Vorbeifahrten zusammen vier Minuten gekostet haben,
    /// kostet zwölf Sekunden und nicht den eingestellten Mittelwert. Alle
    /// übrigen kennt nur die Karte, und die kosten ihn.
    func signalWait(signals: Int, learned: [LearnedSignal] = []) -> TimeInterval {
        Self.signalWait(signals: signals, learned: learned, flat: TimeInterval(signalWaitSeconds))
    }

    /// Die Gegenprobe zur gerechneten Fahrzeit: was dieser Fahrer auf dieser
    /// Strecke nach seinen eigenen Aufzeichnungen bräuchte.
    ///
    /// Die Rechnung aus Strecke, Rolltempo, Ampelzahl und Wartezeit ist eine
    /// Rechnung; der gemessene Schnitt ist eine Messung — **und die Messung
    /// gewinnt**, in beide Richtungen. Sie ist langsamer als die Rechnung?
    /// Dann ist die Rechnung zu optimistisch. Sie ist schneller? Dann fährt
    /// dieser Mensch schneller, als die Rechnung glaubt, und niemand will
    /// eine Ankunft angesagt bekommen, die zehn Minuten zu spät ist.
    ///
    /// Was die Rechnung dabei kann und der Schnitt nicht — Ampeln und
    /// Höhenmeter dieser einen Linie — entscheidet weiter, **welche** Linie
    /// die schnellste ist: die Rollen werden über `computedTime` vergeben.
    /// Der Schnitt sagt, wie lange es dauert, nicht, wo es langgeht.
    func realistic(_ computed: TimeInterval, meters: Double) -> TimeInterval {
        guard let kmh = measuredOverallKmh, kmh > 0, meters > 0 else { return computed }
        return (meters / (kmh / 3.6)).rounded()
    }

    /// Dieselbe Rechnung für alle, die nur die eine Einstellung haben und
    /// nicht die ganze Kopie — die Anzeige zum Beispiel.
    static func signalWait(signals: Int, learned: [LearnedSignal], flat: TimeInterval) -> TimeInterval {
        let measured = learned.reduce(0) { $0 + $1.expectedWait(default: flat) }
        return measured + Double(max(0, signals - learned.count)) * flat
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


/// Whether the screen may turn with the phone, or has to stay as it is.
enum OrientationLock: String, CaseIterable, Codable {
    case auto, portrait, landscape

    var title: String {
        switch self {
        case .auto: "Automatisch"
        case .portrait: "Hochkant"
        case .landscape: "Querformat"
        }
    }

    var symbol: String {
        switch self {
        case .auto: "rotate.right"
        case .portrait: "iphone"
        case .landscape: "iphone.landscape"
        }
    }

    /// Tap order of the button on the ride screen.
    var next: OrientationLock {
        switch self {
        case .auto: .portrait
        case .portrait: .landscape
        case .landscape: .auto
        }
    }
}
