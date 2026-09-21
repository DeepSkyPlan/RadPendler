import SwiftUI

/// RadPendler on the wrist. The watch plans nothing: it shows the plan the
/// phone computed last, and counts down to it. Everything that needs a network,
/// a map or a timetable stays on the phone.
@main
struct RadPendlerWatchApp: App {
    @State private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            WatchHome()
                .environment(model)
        }
    }
}
