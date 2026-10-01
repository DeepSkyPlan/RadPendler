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
    /// Der Kasten „Auto" fährt Motorrad: Stau kostet weniger, weil man wie mit
    /// dem Rad bis an die Ampel vorrollt, und einen Parkplatz sucht niemand.
    var motorcycle: Bool = false {
        didSet {
            defaults.set(motorcycle, forKey: "motorcycle")
            Vehicle.motorcycle = motorcycle
        }
    }
    /// Added to every car trip for finding a parking space.
    var parkingMinutes: Int = 0 { didSet { defaults.set(parkingMinutes, forKey: "parkingMinutes") } }
    /// How many minutes of travel time one change of train is worth avoiding.
    var transferPenaltyMinutes: Int = 10 { didSet { defaults.set(transferPenaltyMinutes, forKey: "transferPenaltyMinutes") } }
    /// Quick departure choices: "in 15 min" or "um 8:00".
    var departurePresets: [DeparturePreset] = [.relative(15), .relative(60), .clock(8, 0), .clock(18, 0)] {
        didSet { defaults.set(departurePresets.map(\.stored), forKey: "departurePresets2") }
    }

    /// Fixpunkte **je Strecke** — ein Fixpunkt auf dem Weg zur Arbeit hat auf
    /// dem Weg zum Bäcker nichts verloren (Nutzer, 01.10.2026). Bis 1.9 galten
    /// sie für jede Strecke.
    var routeWaypoints: [RouteWaypoints] = [] {
        didSet { defaults.set(try? JSONEncoder().encode(routeWaypoints), forKey: "routeWaypoints") }
    }

    /// Places the current route has to touch, e.g. "S Musterhausen" — routes
    /// that miss them are shown greyed out at the end of their section. Gilt
    /// für Start und Ziel, wie sie gerade stehen, in beiden Richtungen.
    var waypoints: [Place] {
        get {
            guard let origin, let destination else { return [] }
            return RouteWaypoints.find(routeWaypoints, origin.coordinate, destination.coordinate)?.points ?? []
        }
        set {
            guard let origin, let destination else { return }
            routeWaypoints = RouteWaypoints.setting(newValue, in: routeWaypoints,
                                                    origin.coordinate, destination.coordinate)
        }
    }
    /// true: a route must touch every fixed point, false: one is enough.
    var requireAllWaypoints: Bool = false { didSet { defaults.set(requireAllWaypoints, forKey: "requireAllWaypoints") } }

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
    /// Töne während der Fahrt: Start, Ende, Abbiegungen.
    var rideSounds: Bool = true { didSet { defaults.set(rideSounds, forKey: "rideSounds") } }
    /// Radrouten meiden Kopfsteinpflaster (Nutzer, 28.09.2026: „fürchterlich").
    var avoidCobbles: Bool = true { didSet { defaults.set(avoidCobbles, forKey: "avoidCobbles") } }

    /// Addresses that have been used before, with how often — the list the
    /// search offers before anything is typed. Device only, like the addresses.
    var placeHistory: [PlaceUse] = [] {
        didSet { defaults.set(try? JSONEncoder().encode(placeHistory), forKey: "placeHistory") }
    }

    /// Was gelöscht wurde — siehe `Tombstones`. Ohne diese Liste kommt jede
    /// gelöschte Adresse, Fahrt und Ampel vom zweiten Gerät zurück.
    var tombstones = Tombstones() {
        didSet { defaults.set(try? JSONEncoder().encode(tombstones), forKey: "tombstones") }
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

    /// Average wait per traffic light on the bike (half of them are green).
    var signalWaitSeconds: Int = 20 { didSet { defaults.set(signalWaitSeconds, forKey: "signalWaitSeconds") } }

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
    ///
    /// Voreingestellt **quer**: am Lenker liegt das Telefon quer, und die
    /// Karte hat dort die Breite, die sie braucht. Wer während einer Fahrt auf
    /// den Knopf tippt, stellt es um, und dabei bleibt es auch beim nächsten
    /// Mal — das hier ist nur der Anfang.
    var rideOrientation: OrientationLock = .landscape {
        didSet { defaults.set(rideOrientation.rawValue, forKey: "rideOrientationLock") }
    }

    /// In welcher Sprache die App spricht. Wirkt sofort, ohne Neustart —
    /// siehe `AppLanguage`.
    var language: AppLanguage = .system {
        didSet {
            defaults.set(language.rawValue, forKey: "language")
            AppLanguage.current = language
        }
    }

    /// Nach so vielen Sekunden ohne Berührung wird der Bildschirm während
    /// einer Fahrt dunkel; 0 schaltet es ab. Er bleibt **an** — nur dunkel,
    /// und beim ersten Antippen wieder hell.
    var rideDimSeconds: Double = 30 {
        didSet { defaults.set(rideDimSeconds, forKey: "rideDimSeconds") }
    }

    /// Ab wann ein Halt, an dem keine Ampel steht, die Aufzeichnung **anhält**
    /// — in Minuten; 0 schaltet es ab. Sie läuft von selbst weiter, sobald es
    /// weitergeht; so lange bleibt die Ortung sparsam.
    var autoPauseMinutes: Double = 3 {
        didSet { defaults.set(autoPauseMinutes, forKey: "autoPauseMinutes") }
    }

    /// Und ab wann er sie **beendet**. Das ist der andere Fall: nicht die
    /// Schranke, sondern das vergessene „Fahrt beenden" — das Telefon liegt
    /// auf dem Schreibtisch und ortet weiter.
    var autoStopMinutes: Double = 20 {
        didSet { defaults.set(autoStopMinutes, forKey: "autoStopMinutes") }
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

    /// Der Tür-zu-Tür-Schnitt, mit dem gerechnet wird — je Verkehrsmittel
    /// getrennt, weil ein Auto-Schnitt das Rad nichts angeht und umgekehrt.
    /// 0 heißt: keiner, es gilt die Rechnung (beim Rad Rolltempo, Ampeln und
    /// Höhenmeter; beim Auto Apple Karten). Nach jeder aufgezeichneten Fahrt
    /// schreibt `calibrate` die Messung hinein; von Hand gestellt gilt es bis
    /// dahin.
    var bikeOverallKmh: Double = 0 { didSet { defaults.set(bikeOverallKmh, forKey: "bikeOverallKmh") } }
    var carOverallKmh: Double = 0 { didSet { defaults.set(carOverallKmh, forKey: "carOverallKmh") } }
    /// Was die Autofahrten gemessen haben, zum Anzeigen neben der Einstellung.
    var measuredCarKmh: Double? = nil { didSet { defaults.set(measuredCarKmh, forKey: "measuredCarKmh") } }
    var measuredCarRides: Int = 0 { didSet { defaults.set(measuredCarRides, forKey: "measuredCarRides") } }

    /// 29 km/h rolling + 20 s per signalised junction reproduces the user's
    /// measured ~21 km/h door-to-door on the Berlin commute it was built for.
    static let defaultBikeSpeedKmh = 29.0

    /// **Die** Liste der Schlüssel, unter denen Einstellungen liegen.
    ///
    /// Sie stand zweimal da: einmal hier in den `didSet`, einmal in
    /// `CloudStore.settingsKeys` — und wer eine Einstellung hinzufügte und die
    /// zweite Liste vergaß, hatte eine, die nie auf dem iPad ankam. Genau das
    /// ist zwischen 0.10.0 und 0.12.1 vier Mal passiert. Jetzt leitet der
    /// CloudStore seine Liste von hier ab, und
    /// `testEverySettingTheAppSavesAlsoTravelsThroughICloud` vergleicht beide
    /// gegen das, was wirklich geschrieben wird.
    ///
    /// Die `didSet` selbst bleiben, wo sie sind: eine Tabelle aus KeyPaths
    /// ginge nur über einen eigenen Property-Wrapper, und der verträgt sich
    /// mit `@Observable` schlecht. Der Gewinn wäre eine Zeile weniger je
    /// Einstellung, der Preis eine Schicht zwischen jeder Ansicht und jedem
    /// Wert.
    static let storedKeys = [
        // Adressen und Orte
        "origin", "destination", "workPlace", "homePlace", "routeWaypoints", "placeHistory",
        "requireAllWaypoints", "workArrivalMinutes",
        // Planung
        "prepMinutes", "bikeMovingSpeedKmh", "bikeStationBufferMinutes", "maxBikeToStationKm",
        "parkingMinutes", "motorcycle", "transferPenaltyMinutes", "signalWaitSeconds", "departurePresets2",
        "arrivalBufferMinutes", "optionsPerMode",
        "modeOrder", "bikeVariantOrder", "carVariantOrder", "rainSwitchLevel",
        "bikeLines",
        // Countdown
        "alertMinutes", "alertsOn",
        // Aufzeichnen
        "learnedSignals", "replanOffRouteMeters",
        "autoStopMinutes", "autoPauseMinutes", "rideDimSeconds", "rideSounds", "avoidCobbles",
        "measuredOverallKmh", "measuredMovingKmh", "measuredRides",
        "bikeOverallKmh", "carOverallKmh", "measuredCarKmh", "measuredCarRides",
        // Anzeige
        "orientationLock", "rideOrientationLock", "language",
        // Was gelöscht wurde
        "tombstones",
    ]

    /// Einstellungen, die es nicht mehr gibt (seit 1.9.1). Ihre Schlüssel
    /// werden beim Laden gelöscht, damit sie weder herumliegen noch über
    /// iCloud zurückkommen — `CloudStore` trägt nur `storedKeys`.
    static let retiredKeys = ["departureBufferMinutes", "timetableSource",
                              "signalStopSeconds", "replanOffRouteMinutes"]

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
        // Der „Puffer vor der Abfahrt" tat auf das Losgehen dasselbe wie die
        // Rüstzeit. Wer einen hatte, findet ihn einmal in der Rüstzeit wieder.
        if let buffer = defaults.object(forKey: "departureBufferMinutes") as? Int, buffer > 0 {
            prepMinutes += buffer
        }
        for key in Self.retiredKeys where defaults.object(forKey: key) != nil {
            defaults.removeObject(forKey: key)
        }
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
        assign(\.routeWaypoints, defaults.data(forKey: "routeWaypoints")
            .flatMap { try? JSONDecoder().decode([RouteWaypoints].self, from: $0) } ?? routeWaypoints)
        // Die alten, für alle Strecken geltenden Fixpunkte gehören ab 1.9.1
        // der Strecke, die gerade eingestellt ist — die, für die sie
        // eingetragen wurden.
        if let old = defaults.data(forKey: "waypoints").flatMap({ try? JSONDecoder().decode([Place].self, from: $0) }),
           origin != nil, destination != nil {
            if !old.isEmpty, waypoints.isEmpty { waypoints = old }
            defaults.removeObject(forKey: "waypoints")
        }
        assign(\.requireAllWaypoints, defaults.object(forKey: "requireAllWaypoints") as? Bool ?? requireAllWaypoints)
        assign(\.arrivalBufferMinutes, defaults.object(forKey: "arrivalBufferMinutes") as? Int ?? arrivalBufferMinutes)
        assign(\.workArrivalMinutes, defaults.object(forKey: "workArrivalMinutes") as? Int ?? workArrivalMinutes)
        assign(\.alertMinutes, defaults.array(forKey: "alertMinutes") as? [Int] ?? alertMinutes)
        assign(\.alertsOn, defaults.object(forKey: "alertsOn") as? Bool ?? alertsOn)
        assign(\.placeHistory, defaults.data(forKey: "placeHistory")
            .flatMap { try? JSONDecoder().decode([PlaceUse].self, from: $0) } ?? placeHistory)
        assign(\.bikeLines, defaults.data(forKey: "bikeLines")
            .flatMap { try? JSONDecoder().decode([BikeLine].self, from: $0) } ?? bikeLines)
        assign(\.modeOrder, storedOrder(defaults.array(forKey: "modeOrder") as? [String],
                                        fallback: TravelMode.defaultOrder))
        assign(\.bikeVariantOrder, storedOrder(defaults.array(forKey: "bikeVariantOrder") as? [String],
                                               fallback: BikeVariant.defaultOrder))
        assign(\.carVariantOrder, storedOrder(defaults.array(forKey: "carVariantOrder") as? [String],
                                              fallback: CarVariant.defaultOrder))
        assign(\.rainSwitchLevel, (defaults.object(forKey: "rainSwitchLevel") as? Int)
            .flatMap(RainLevel.init(rawValue:)) ?? rainSwitchLevel)
        assign(\.learnedSignals, defaults.data(forKey: "learnedSignals")
            .flatMap { try? JSONDecoder().decode([LearnedSignal].self, from: $0) } ?? learnedSignals)
        assign(\.orientation, (defaults.string(forKey: "orientationLock"))
            .flatMap(OrientationLock.init(rawValue:)) ?? orientation)
        assign(\.replanOffRouteMeters,
               defaults.object(forKey: "replanOffRouteMeters") as? Double ?? replanOffRouteMeters)
        assign(\.optionsPerMode, defaults.object(forKey: "optionsPerMode") as? Int ?? optionsPerMode)
        assign(\.rideOrientation, (defaults.string(forKey: "rideOrientationLock"))
            .flatMap(OrientationLock.init(rawValue:)) ?? rideOrientation)
        assign(\.autoStopMinutes, defaults.object(forKey: "autoStopMinutes") as? Double ?? autoStopMinutes)
        assign(\.rideSounds, defaults.object(forKey: "rideSounds") as? Bool ?? rideSounds)
        assign(\.avoidCobbles, defaults.object(forKey: "avoidCobbles") as? Bool ?? avoidCobbles)
        assign(\.autoPauseMinutes, defaults.object(forKey: "autoPauseMinutes") as? Double ?? autoPauseMinutes)
        assign(\.tombstones, defaults.data(forKey: "tombstones")
            .flatMap { try? JSONDecoder().decode(Tombstones.self, from: $0) } ?? tombstones)
        assign(\.rideDimSeconds, defaults.object(forKey: "rideDimSeconds") as? Double ?? rideDimSeconds)
        assign(\.language, defaults.string(forKey: "language").flatMap(AppLanguage.init(rawValue:)) ?? language)
        // `assign` setzt nur, was sich unterscheidet — beim Start auf
        // „Deutsch" feuert das didSet also nicht, und `AppLanguage.current`
        // bliebe auf dem Voreingestellten stehen.
        AppLanguage.current = language
        assign(\.motorcycle, defaults.object(forKey: "motorcycle") as? Bool ?? motorcycle)
        // Aus demselben Grund wie die Sprache.
        Vehicle.motorcycle = motorcycle
        assign(\.measuredOverallKmh, defaults.object(forKey: "measuredOverallKmh") as? Double)
        assign(\.measuredMovingKmh, defaults.object(forKey: "measuredMovingKmh") as? Double)
        assign(\.measuredRides, defaults.object(forKey: "measuredRides") as? Int ?? measuredRides)
        assign(\.carOverallKmh, defaults.object(forKey: "carOverallKmh") as? Double ?? carOverallKmh)
        assign(\.measuredCarKmh, defaults.object(forKey: "measuredCarKmh") as? Double)
        assign(\.measuredCarRides, defaults.object(forKey: "measuredCarRides") as? Int ?? measuredCarRides)
        assign(\.bikeOverallKmh, defaults.object(forKey: "bikeOverallKmh") as? Double ?? bikeOverallKmh)
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
        bikeOverallKmh = Self.halfStep(overall)
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

    /// Dasselbe fürs Auto, ohne Rolltempo und Ampeln: nur der Tür-zu-Tür-
    /// Schnitt. Er ist beim Planen die Untergrenze für Apples Fahrzeit —
    /// Apple kennt den Verkehr, aber nicht den Parkplatz vor der Tür und
    /// nicht, wie dieser Fahrer fährt. Motorradfahrten zählen nicht mit: sie
    /// rollen am Stau vorbei und würden das Auto schneller machen, als es ist.
    func calibrateCar(from rides: [Ride]) {
        let relevant = rides
            .filter { $0.travelMode == .car && $0.motorcycle != true && $0.meters >= 2_000 && $0.movingSeconds > 60 }
            .sorted { $0.started > $1.started }
            .prefix(Self.calibrationWindow)
        guard relevant.count >= Self.calibrationRides else { return }
        let overall = Self.median(relevant.map(\.averageKmh))
        measuredCarRides = relevant.count
        measuredCarKmh = overall
        carOverallKmh = overall.rounded()
    }

    /// Auf halbe km/h — so weit, wie der Stepper geht.
    static func halfStep(_ kmh: Double) -> Double { (kmh * 2).rounded() / 2 }

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
        tombstones = Tombstones.bury([Tombstones.key(place: use.id)], in: defaults)
    }

    /// Alle gelernten Kreuzungen vergessen — und zwar so, dass sie nicht vom
    /// zweiten Gerät zurückkommen.
    func forgetLearnedSignals() {
        tombstones = Tombstones.bury(learnedSignals.map { Tombstones.key(signal: $0.id) }, in: defaults)
        learnedSignals = []
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
                     arrivalBufferMinutes: arrivalBufferMinutes,
                     modeOrder: modeOrder, bikeVariantOrder: bikeVariantOrder,
                     carVariantOrder: carVariantOrder, optionsPerMode: optionsPerMode,
                     rainSwitchLevel: rainSwitchLevel,
                     bikeLineStatus: bikeLines.status,
                     learnedSignals: learnedSignals,
                     measuredOverallKmh: bikeOverallKmh > 0 ? bikeOverallKmh : nil,
                     carOverallKmh: carOverallKmh > 0 ? carOverallKmh : nil,
                     avoidCobbles: avoidCobbles, motorcycle: motorcycle)
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
    /// Junctions this rider has ridden through. They join the ones
    /// OpenStreetMap knows before a route is judged — and they bring their
    /// measured wait, where the mapped ones only get `signalWaitSeconds`.
    var learnedSignals: [LearnedSignal] = []
    /// Der gemessene Tür-zu-Tür-Schnitt dieses Fahrers, aus seinen
    /// aufgezeichneten Fahrten. nil, solange es zu wenige sind.
    var measuredOverallKmh: Double? = nil
    /// Der Tür-zu-Tür-Schnitt fürs Auto; nil heißt, Apples Fahrzeit gilt.
    var carOverallKmh: Double? = nil
    /// Radrouten meiden Kopfsteinpflaster.
    var avoidCobbles = true
    /// Der Kasten „Auto" fährt Motorrad — siehe `CarCandidate.driveTime`.
    var motorcycle = false
    /// Beyond this, the whole way by bike is a curiosity rather than a plan:
    /// its box moves to the end of the row and the OpenStreetMap corridor gets
    /// too big to ask Overpass for.
    var longTripKm = 100.0

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

    /// Die Fahrt mit dieser Entscheidung an jedem Zug, damit Zeitstrahl und
    /// Warnungen dasselbe sagen wie die Auswahl.
    func decided(_ legs: [Leg]) -> [Leg] {
        legs.map { leg in
            guard leg.isTransit else { return leg }
            var l = leg
            l.bikeCarriage = carriage(leg)
            return l
        }
    }

    // MARK: Das Zeitmodell fürs Rad

    /// Was ein Höhenmeter an Zeit kostet.
    ///
    /// Fünf Sekunden je Meter sind 720 Höhenmeter in der Stunde — das Tempo
    /// von jemandem, der in der Ebene 29 km/h rollt. Bergab wird nichts
    /// gutgeschrieben: man holt die Zeit, die ein Anstieg kostet, auf der
    /// anderen Seite nicht wieder herein, und eine Strecke mit hundert Metern
    /// hoch und hundert wieder runter ist anstrengender als eine flache, auch
    /// wenn sie am Ende gleich lang ist.
    static let climbSecondsPerMeter = 5.0

    /// Die reine Rechnung: Strecke im Rolltempo, Wartezeit an den Ampeln,
    /// Höhenmeter. Sie allein unterscheidet zwei Linien gleicher Länge und
    /// entscheidet deshalb, welche die schnellste ist.
    ///
    /// Bis 1.9.1 stand sie dreimal da — für die ganze Radroute mit
    /// Höhenmetern, für die Zubringer ohne, und die von Transitous fuhren mit
    /// dessen eigener Schätzung. Jetzt rechnet alles, was geplant wird, hier.
    func computedRideTime(meters: Double, signals: Int, learned: [LearnedSignal] = [],
                          ascent: Double? = nil) -> TimeInterval {
        bikeTime(meters) + signalWait(signals: signals, learned: learned)
            + (ascent ?? 0) * Self.climbSecondsPerMeter
    }

    /// Wann der gemessene Schnitt die Rechnung ersetzt.
    enum MeasuredRule {
        /// In beide Richtungen — die ganze Radroute, siehe `realistic`.
        case wins
        /// Nur, wenn er langsamer ist. Das sind die Zubringer zum Bahnhof:
        /// rechnet die App sie schneller, als dieser Fahrer wirklich fährt,
        /// steht er auf dem Bahnsteig und sieht die Rücklichter. Umgekehrt
        /// kostet ein zu vorsichtiger Zubringer nur ein paar Minuten früher
        /// losgehen.
        case slowerOnly
    }

    /// Die Fahrzeit, mit der geplant und die angezeigt wird: die Rechnung,
    /// gegengeprüft am eigenen gemessenen Schnitt.
    func rideTime(meters: Double, signals: Int, learned: [LearnedSignal] = [], ascent: Double? = nil,
                  measured rule: MeasuredRule) -> TimeInterval {
        let computed = computedRideTime(meters: meters, signals: signals, learned: learned, ascent: ascent)
        let measured = realistic(computed, meters: meters)
        return rule == .wins ? measured : Swift.max(computed, measured)
    }

    /// Ein Zubringer zum oder vom Bahnhof.
    func rideTime(_ r: StreetRoute) -> TimeInterval {
        rideTime(meters: r.distance, signals: r.signals, learned: r.learnedSignals, ascent: r.ascent,
                 measured: .slowerOnly)
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
        case .relative(let m) where m < 60: L("in %d min", m)
        case .relative(let m) where m % 60 == 0: L("in %d h", m / 60)
        case .relative(let m): L("in %d h %d min", m / 60, m % 60)
        case .clock(let h, let m): m == 0 ? L("um %d Uhr", h) : L("um %d:%02d", h, m)
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

/// Where the timetable comes from: VBB inside Berlin and Brandenburg,
/// Transitous everywhere else. Bis 1.9.1 ließ sich das in den Einstellungen
/// festnageln; gebraucht hat das niemand, und falsch gewählt fand die App
/// außerhalb des VBB-Gebiets gar nichts.
enum TimetableSource: String {
    /// The VBB's own HAFAS: the best real-time data for the region, and the
    /// only one that states bike carriage per train.
    case vbb
    /// Transitous (MOTIS) on the nationwide DELFI dataset and beyond.
    case transitous

    /// Berlin and Brandenburg, generously drawn. Inside it the VBB knows more
    /// than a nationwide dataset does — outside it, it knows nothing.
    static let vbbArea = (south: 51.35, west: 11.26, north: 53.56, east: 14.77)

    static func covers(_ c: CLLocationCoordinate2D) -> Bool {
        c.latitude >= vbbArea.south && c.latitude <= vbbArea.north
            && c.longitude >= vbbArea.west && c.longitude <= vbbArea.east
    }

    /// The source that answers for this pair of places.
    static func resolved(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> TimetableSource {
        covers(from) && covers(to) ? .vbb : .transitous
    }
}


/// Whether the screen may turn with the phone, or has to stay as it is.
enum OrientationLock: String, CaseIterable, Codable {
    case auto, portrait, landscape

    var title: String {
        switch self {
        case .auto: L("Automatisch")
        case .portrait: L("Hochkant")
        case .landscape: L("Querformat")
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

/// Die Fixpunkte einer Strecke. Eine Strecke sind zwei Enden, in beiden
/// Richtungen dieselbe — wer abends über den Korso heimfährt, will morgens
/// auch über ihn hin. Ein Ende gilt als dasselbe, solange es höchstens
/// `radius` entfernt liegt: „hier" aus der Ortung liegt nie genau auf der
/// Hausnummer.
struct RouteWaypoints: Codable, Equatable {
    var a: TrackPoint
    var b: TrackPoint
    var points: [Place]

    static let radius = 500.0

    func matches(_ from: CLLocationCoordinate2D, _ to: CLLocationCoordinate2D) -> Bool {
        let (x, y) = (a.coordinate, b.coordinate)
        return (x.distance(to: from) <= Self.radius && y.distance(to: to) <= Self.radius)
            || (y.distance(to: from) <= Self.radius && x.distance(to: to) <= Self.radius)
    }

    static func find(_ all: [RouteWaypoints], _ from: CLLocationCoordinate2D,
                     _ to: CLLocationCoordinate2D) -> RouteWaypoints? {
        all.first { $0.matches(from, to) }
    }

    static func setting(_ points: [Place], in all: [RouteWaypoints], _ from: CLLocationCoordinate2D,
                        _ to: CLLocationCoordinate2D) -> [RouteWaypoints] {
        var out = all.filter { !$0.matches(from, to) }
        if !points.isEmpty { out.append(RouteWaypoints(a: TrackPoint(from), b: TrackPoint(to), points: points)) }
        return out
    }
}
