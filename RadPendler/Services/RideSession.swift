import Foundation

/// Was vor und nach einer Fahrt passiert und keine Ansicht braucht: die
/// Ausrichtung am Lenker, die Töne, und hinterher dazulernen und nachmessen.
///
/// Stand bis zum Aufräumen nach 1.9.1 in `ContentView` (`record()` und
/// `afterRide()`). Dort hing es an einer Ansicht, obwohl es auch dann laufen
/// muss, wenn die Fahrt sich bei ausgeschaltetem Bildschirm selbst beendet
/// (`RideTracker.onAutoStop`).
@MainActor
enum RideSession {
    /// Startet die Aufzeichnung der Fahrt, die auf dem Bildschirm steht.
    static func start(_ option: TripOption, options: [TripOption],
                      settings: AppSettings, tracker: RideTracker) {
        // Am Lenker gilt, was am Lenker zuletzt galt — nicht, wie die App
        // sich sonst dreht.
        settings.rideOrientation.apply()
        RideSounds.shared.enabled = settings.rideSounds
        tracker.start(RidePlan.make(option: option, options: options, settings: settings))
    }

    /// Der Knopf „Fahrt beenden".
    static func stop(tracker: RideTracker, settings: AppSettings, rides: RideStore) {
        tracker.stop()
        finish(tracker: tracker, settings: settings, rides: rides)
    }

    /// Was nach jeder Fahrt passiert, egal wer sie beendet hat: nachmessen,
    /// dazulernen, die eigene Ausrichtung wiederherstellen.
    static func finish(tracker: RideTracker, settings: AppSettings, rides: RideStore) {
        // Hell, bevor irgendetwas anderes passiert — die Zusammenfassung will
        // gelesen werden.
        ScreenDim.shared.wake()
        // Where this ride stood — and where it rolled straight through — is
        // what the next one knows: the junctions no map has, and what the
        // known ones really cost.
        settings.learn(stops: tracker.meter.stops,
                       track: tracker.meter.points,
                       junctions: tracker.meter.signals)
        // Und was sie über das Tempo dieses Fahrers weiß, steht ab jetzt in
        // den Einstellungen.
        settings.calibrate(from: rides.rides)
        settings.calibrateCar(from: rides.rides)
        // Die Fahrt ist vorbei: es gilt wieder die Ausrichtung aus den
        // Einstellungen. Bis 1.9.1 ging sie hier auf „Automatisch" — aus der
        // Zeit, als die Fahrt dieselbe Einstellung verstellte; seit es
        // `rideOrientation` gibt, löschte das nur die Wahl des Nutzers.
        settings.orientation.apply()
    }
}
