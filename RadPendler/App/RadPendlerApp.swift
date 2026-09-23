import SwiftUI

@main
struct RadPendlerApp: App {
    @State private var settings = AppSettings()
    @State private var rides = RideStore.shared
    @State private var tracker = RideTracker()

    init() {
        // Up before the first plan lands, so the first search already reaches
        // the watch instead of waiting for the second.
        WatchLink.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(rides)
                .environment(tracker)
                .task {
                    // Addresses and preferences travel through iCloud, so the
                    // iPad starts with what the iPhone already knows.
                    CloudStore.shared.onPull = { settings.load() }
                    CloudStore.shared.start()
                    // A ride the app did not survive is still a ride; it is
                    // filed here, up to the last second it knew about.
                    rides.recoverInterrupted()
                    // The rides themselves are too big for the key-value store
                    // the settings travel in — they have their own private
                    // CloudKit database.
                    await rides.syncFromCloud()
                }
        }
    }
}
