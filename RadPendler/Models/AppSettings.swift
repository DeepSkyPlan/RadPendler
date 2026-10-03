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
    /// Speed while rolling, without stops; lights are added per junction.
    /// MapKit's own cycling ETA is ignored. Gemessen (`calibrate`) oder die
    /// Voreinstellung; von Hand nur über `bikeSpeedOverride`.
    /// (0.1.x stored an all-in average under "bikeSpeedKmh" — deliberately not read.)
    var calibratedBikeSpeedKmh: Double = AppSettings.defaultBikeSpeedKmh {
        didSet { defaults.set(calibratedBikeSpeedKmh, forKey: "bikeMovingSpeedKmh") }
    }
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
    /// Gemessen (`calibrate`) oder die Voreinstellung; von Hand nur über
    /// `signalWaitOverride`.
    var calibratedSignalWaitSeconds: Int = 20 {
        didSet { defaults.set(calibratedSignalWaitSeconds, forKey: "signalWaitSeconds") }
    }

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

    /// Der gemessene Tür-zu-Tür-Schnitt — je Verkehrsmittel getrennt, weil
    /// ein Auto-Schnitt das Rad nichts angeht und umgekehrt. 0 heißt: keiner,
    /// es gilt die Rechnung (beim Rad Rolltempo, Ampeln und Höhenmeter; beim
    /// Auto Apple Karten). Nach jeder aufgezeichneten Fahrt schreibt
    /// `calibrate` die Messung hinein.
    var calibratedBikeOverallKmh: Double = 0 {
        didSet { defaults.set(calibratedBikeOverallKmh, forKey: "bikeOverallKmh") }
    }
    var calibratedCarOverallKmh: Double = 0 {
        didSet { defaults.set(calibratedCarOverallKmh, forKey: "carOverallKmh") }
    }

    // MARK: Von Hand statt gemessen

    // Bis 1.9.1 standen die vier gemessenen Werte als Stepper in den
    // Einstellungen, und `calibrate` schrieb nach jeder Fahrt darüber: was von
    // Hand gestellt war, galt bis zur nächsten Fahrt. Jetzt steht die Messung
    // für sich, und wer etwas anderes will, stellt es daneben — das überlebt
    // jede Fahrt. nil heißt: es gilt die Messung.
    var bikeSpeedOverride: Double? = nil { didSet { defaults.set(bikeSpeedOverride, forKey: "bikeSpeedOverride") } }
    var signalWaitOverride: Int? = nil { didSet { defaults.set(signalWaitOverride, forKey: "signalWaitOverride") } }
    var bikeOverallOverride: Double? = nil {
        didSet { defaults.set(bikeOverallOverride, forKey: "bikeOverallOverride") }
    }
    var carOverallOverride: Double? = nil {
        didSet { defaults.set(carOverallOverride, forKey: "carOverallOverride") }
    }

    /// Womit geplant wird: von Hand, wo gestellt, sonst gemessen.
    var bikeSpeedKmh: Double { bikeSpeedOverride ?? calibratedBikeSpeedKmh }
    var signalWaitSeconds: Int { signalWaitOverride ?? calibratedSignalWaitSeconds }
    var bikeOverallKmh: Double { bikeOverallOverride ?? calibratedBikeOverallKmh }
    var carOverallKmh: Double { carOverallOverride ?? calibratedCarOverallKmh }
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
        "workArrivalMinutes",
        // Planung
        "prepMinutes", "bikeMovingSpeedKmh", "bikeStationBufferMinutes", "maxBikeToStationKm",
        "parkingMinutes", "motorcycle", "transferPenaltyMinutes", "signalWaitSeconds", "departurePresets2",
        "arrivalBufferMinutes", "optionsPerMode",
        "modeOrder", "bikeVariantOrder", "rainSwitchLevel",
        "bikeLines",
        // Countdown
        "alertMinutes", "alertsOn",
        // Aufzeichnen
        "learnedSignals", "replanOffRouteMeters",
        "autoStopMinutes", "autoPauseMinutes", "rideDimSeconds", "rideSounds", "avoidCobbles",
        "measuredOverallKmh", "measuredMovingKmh", "measuredRides",
        "bikeOverallKmh", "carOverallKmh", "measuredCarKmh", "measuredCarRides",
        "bikeSpeedOverride", "signalWaitOverride", "bikeOverallOverride", "carOverallOverride",
        // Anzeige
        "orientationLock", "rideOrientationLock", "language",
        // Was gelöscht wurde
        "tombstones",
    ]

    /// Einstellungen, die es nicht mehr gibt (seit 1.9.1). Ihre Schlüssel
    /// werden beim Laden gelöscht, damit sie weder herumliegen noch über
    /// iCloud zurückkommen — `CloudStore` trägt nur `storedKeys`.
    static let retiredKeys = ["departureBufferMinutes", "timetableSource",
                              "signalStopSeconds", "replanOffRouteMinutes",
                              // 1.10: ein Fixpunkt reicht; Autorouten in fester Reihenfolge.
                              "requireAllWaypoints", "carVariantOrder"]

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
            // Gleich auch in iCloud: `CloudStore.start` zieht sonst gleich danach
            // die alte Rüstzeit von dort herein, und der Puffer ist weg. Nur wenn
            // dort schon eine steht — ein leerer Speicher gälte sonst nicht mehr
            // als leer, und `pull` räumte alles andere hier ab.
            let cloud = NSUbiquitousKeyValueStore.default
            if defaults === UserDefaults.standard, cloud.object(forKey: "prepMinutes") != nil {
                cloud.set(prepMinutes, forKey: "prepMinutes")
            }
        }
        for key in Self.retiredKeys where defaults.object(forKey: key) != nil {
            defaults.removeObject(forKey: key)
        }
        // 0.1.x stored an all-in average under "bikeSpeedKmh" — deliberately not read.
        assign(\.calibratedBikeSpeedKmh, defaults.object(forKey: "bikeMovingSpeedKmh") as? Double ?? calibratedBikeSpeedKmh)
        assign(\.bikeStationBufferMinutes,
               defaults.object(forKey: "bikeStationBufferMinutes") as? Int ?? bikeStationBufferMinutes)
        assign(\.maxBikeToStationKm, defaults.object(forKey: "maxBikeToStationKm") as? Double ?? maxBikeToStationKm)
        assign(\.parkingMinutes, defaults.object(forKey: "parkingMinutes") as? Int ?? parkingMinutes)
        assign(\.transferPenaltyMinutes,
               defaults.object(forKey: "transferPenaltyMinutes") as? Int ?? transferPenaltyMinutes)
        assign(\.calibratedSignalWaitSeconds,
               defaults.object(forKey: "signalWaitSeconds") as? Int ?? calibratedSignalWaitSeconds)
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
        assign(\.rainSwitchLevel, (defaults.object(forKey: "rainSwitchLevel") as? Int)
            .flatMap(RainLevel.init(rawValue:)) ?? rainSwitchLevel)
        assign(\.learnedSignals, defaults.data(forKey: "learnedSignals")
            .flatMap { try? JSONDecoder().decode([LearnedSignal].self, from: $0) }
            .map(LearnedSignal.healed) ?? learnedSignals)
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
        assign(\.calibratedCarOverallKmh, defaults.object(forKey: "carOverallKmh") as? Double ?? calibratedCarOverallKmh)
        assign(\.measuredCarKmh, defaults.object(forKey: "measuredCarKmh") as? Double)
        assign(\.measuredCarRides, defaults.object(forKey: "measuredCarRides") as? Int ?? measuredCarRides)
        assign(\.calibratedBikeOverallKmh, defaults.object(forKey: "bikeOverallKmh") as? Double ?? calibratedBikeOverallKmh)
        // Fehlt der Schlüssel, ist nichts von Hand gestellt — auch nach dem
        // Umstieg von 1.9.1: was dort stand, gilt als gemessen.
        assign(\.bikeSpeedOverride, defaults.object(forKey: "bikeSpeedOverride") as? Double)
        assign(\.signalWaitOverride, defaults.object(forKey: "signalWaitOverride") as? Int)
        assign(\.bikeOverallOverride, defaults.object(forKey: "bikeOverallOverride") as? Double)
        assign(\.carOverallOverride, defaults.object(forKey: "carOverallOverride") as? Double)
        loadedOnce = true
    }

    /// Back to what the app ships with — one button beats four drags.
    func resetPriorities() {
        modeOrder = TravelMode.defaultOrder
        bikeVariantOrder = BikeVariant.defaultOrder
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
                     waypoints: waypoints,
                     arrivalBufferMinutes: arrivalBufferMinutes,
                     modeOrder: modeOrder, bikeVariantOrder: bikeVariantOrder,
                     optionsPerMode: optionsPerMode,
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
    var arrivalBufferMinutes = 5
    var modeOrder: [TravelMode] = TravelMode.defaultOrder
    var bikeVariantOrder: [BikeVariant] = BikeVariant.defaultOrder
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

/// Reads a stored order back. What the stored list does not mention is appended
/// in its default position — a variant added in a later version must not vanish
/// because an older device wrote the list before it existed.
func storedOrder<T: RawRepresentable & Equatable>(_ stored: [T.RawValue]?, fallback: [T]) -> [T] {
    guard let stored else { return fallback }
    let known = stored.compactMap(T.init(rawValue:))
    return known + fallback.filter { !known.contains($0) }
}
