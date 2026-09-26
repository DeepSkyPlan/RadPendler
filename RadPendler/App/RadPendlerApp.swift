import SwiftUI

@main
struct RadPendlerApp: App {
    // Only there so UIKit has someone to ask which way up the app may be.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var settings = AppSettings()
    @State private var rides = RideStore.shared
    @State private var tracker = RideTracker()
    @Environment(\.scenePhase) private var phase

    init() {
        // Up before the first plan lands, so the first search already reaches
        // the watch instead of waiting for the second.
        WatchLink.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Wechselt die Sprache, baut SwiftUI den Baum neu auf — und
                // `L(…)` liest dann aus dem anderen Verzeichnis.
                .id(settings.language)
                .environment(settings)
                .environment(rides)
                .environment(tracker)
                .task {
                    // Die im Hintergrund geweckte App fragt diese Einstellungen,
                    // statt sich zweite zu bauen, die dieselben Schlüssel noch
                    // einmal schreiben.
                    BackgroundReplan.live = { settings }
                    // Addresses and preferences travel through iCloud, so the
                    // iPad starts with what the iPhone already knows.
                    CloudStore.shared.onPull = {
                        settings.load()
                        // The rides ride along in the same store: the numbers
                        // of a ride, never its line.
                        rides.reload()
                    }
                    CloudStore.shared.start()
                    // A ride the app did not survive is still a ride; it is
                    // filed here, up to the last second it knew about.
                    await rides.recoverInterrupted()
                    // Der CloudKit-Container heißt seit 26.09.2026 wie die App;
                    // was im alten liegt, zieht nicht mit. Dieses Gerät schiebt
                    // seine Linien einmal nach.
                    await rides.reuploadTracksIfNeeded()
                    // Whatever the user last chose, from this device or another.
                    settings.orientation.apply()
                }
                // Beim Schließen anmelden: ab hier kann die App nicht mehr
                // selbst nachplanen, und genau dafür ist die Aufgabe da. Eine
                // App mit Szenen bekommt `applicationDidEnterBackground` nie
                // zu sehen — `scenePhase` ist der Weg, der wirklich feuert.
                .onChange(of: phase) { _, now in
                    if now == .background { BackgroundReplan.schedule() }
                }
        }
    }
}



