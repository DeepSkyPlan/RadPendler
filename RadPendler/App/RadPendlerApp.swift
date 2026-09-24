import SwiftUI

@main
struct RadPendlerApp: App {
    // Only there so UIKit has someone to ask which way up the app may be.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
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
                .onAppear { StallWatch.shared.start() }
                .environment(settings)
                .environment(rides)
                .environment(tracker)
                .task {
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
                    rides.recoverInterrupted()
                    // Whatever the user last chose, from this device or another.
                    settings.orientation.apply()
                }
        }
    }
}


/// Notices when the main thread does not get a turn. A run loop timer that
/// should fire ten times a second measures how late it actually is; anything
/// over half a second is a stall the user feels, and ten seconds is where the
/// system kills the app.
///
/// **Temporary, and deliberately shipped.** A hang that only happens on one
/// person's phone cannot be found in a simulator — 1.2 proved that twice. This
/// puts a number in front of the one person who can reproduce it.
@MainActor
@Observable
final class StallWatch {
    static let shared = StallWatch()

    private(set) var longest: TimeInterval = 0
    private(set) var count = 0
    private var started = false

    /// Below this nobody notices; above it, everybody does.
    static let threshold: TimeInterval = 0.5

    func start() {
        guard !started else { return }
        started = true
        var last = CFAbsoluteTimeGetCurrent()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            let now = CFAbsoluteTimeGetCurrent()
            let gap = now - last
            last = now
            guard gap > Self.threshold else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                self.count += 1
                self.longest = Swift.max(self.longest, gap)
            }
            NSLog("STALL %.2f s", gap)
        }
        // `.common`, or the timer stops counting during exactly the scrolling
        // and dragging where the stalls are worst.
        RunLoop.main.add(timer, forMode: .common)
    }

    /// "3 Hänger, längster 12,4 s" — nil while everything is smooth.
    var summary: String? {
        guard count > 0 else { return nil }
        return "\(count) Hänger, längster \(longest.formatted(.number.precision(.fractionLength(1)))) s"
    }

    func reset() {
        count = 0
        longest = 0
    }
}
