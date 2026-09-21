import SwiftUI

@main
struct RadPendlerApp: App {
    @State private var settings = AppSettings()

    init() {
        // Up before the first plan lands, so the first search already reaches
        // the watch instead of waiting for the second.
        WatchLink.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .task {
                    // Addresses and preferences travel through iCloud, so the
                    // iPad starts with what the iPhone already knows.
                    CloudStore.shared.onPull = { settings.load() }
                    CloudStore.shared.start()
                }
        }
    }
}
