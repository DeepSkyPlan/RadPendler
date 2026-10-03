import CoreLocation

/// Alles, was eine Fahrt beim Start aus dem Plan und aus den Einstellungen
/// mitnimmt — und danach nicht mehr ansieht.
///
/// Ein Wert statt zwölf Parametern: bis 1.9.1 rief `ContentView` den Tracker
/// mit einer Liste auf, in der jeder neue Schalter eine Zeile mehr war und
/// zwei Arrays von Koordinaten sich nur am Namen unterschieden. Zusammengesetzt
/// wird er an **einer** Stelle (`make`), und diese Stelle friert ein, was die
/// Fahrt führt: eine Neuplanung auf dem Startbildschirm ändert danach nichts
/// mehr an der laufenden Aufzeichnung.
struct RidePlan {
    var subject: RideTracker.Subject
    /// Die Ampeln, gegen die Halte gemessen werden: die der Route plus alles
    /// Gelernte.
    var signals: [CLLocationCoordinate2D]
    /// Davon nur die der geplanten Route — für Karte und Zählung.
    var plannedSignals: [CLLocationCoordinate2D] = []
    var route: [CLLocationCoordinate2D] = []
    var roadPoints: [RoadPoint] = []
    var replanOffRouteMeters = OffRoute.replanMeters
    var autoStopMinutes = 0.0
    var autoPauseMinutes = 0.0
    /// Womit neu geplant wird: dasselbe Profil wie die gewählte Linie.
    var bikeProfile: BRouterClient.Profile = .quiet
    var avoidCobbles = false
    /// Die Fixpunkte, die die geplante Linie anfährt.
    var via: [CLLocationCoordinate2D] = []

    /// Die Fahrt, die auf dem Bildschirm steht. Die Ampeln **dieser** Route
    /// kommen mit — sie entscheiden später, welcher Halt ein Rot war.
    static func make(option: TripOption, options: [TripOption], settings: AppSettings) -> RidePlan {
        let planned = option.bikeRoute?.stats?.signalPoints ?? option.carRoute?.signalPoints ?? []
        // Was OpenStreetMap kennt, plus was dieser Fahrer gelernt hat. Auf das
        // Gelernte kommt es an: die Kreuzung, die nur in der Praxis eine Ampel
        // ist, steht in keiner Karte.
        let signals = planned + settings.learnedSignals.map(\.coordinate)
        return RidePlan(subject: RideTracker.Subject(origin: settings.origin?.shortName ?? "Start",
                                                     destination: settings.destination?.shortName ?? "Ziel",
                                                     mode: option.mode.rawValue,
                                                     plannedSeconds: option.duration,
                                                     plannedMeters: option.totalDistance,
                                                     plannedSignals: planned.count,
                                                     motorcycle: option.mode == .car && settings.motorcycle),
                        signals: signals,
                        plannedSignals: planned,
                        route: route(of: options, selected: option.id),
                        roadPoints: option.bikeRoute?.roadPoints ?? [],
                        autoStopMinutes: settings.autoStopMinutes,
                        autoPauseMinutes: settings.autoPauseMinutes,
                        bikeProfile: option.bikeRoute?.source.profile ?? .trekking,
                        avoidCobbles: settings.avoidCobbles,
                        via: option.bikeRoute?.via ?? [])
    }

    /// The way that is actually ridden: the transit legs are somebody else's
    /// steering.
    static func route(of options: [TripOption], selected: TripOption.ID?) -> [CLLocationCoordinate2D] {
        guard let option = options.first(where: { $0.id == selected }) ?? options.first else { return [] }
        return option.legs.filter { !$0.isTransit }.flatMap(\.coordinates)
    }
}
