import AudioToolbox
import UIKit
import UserNotifications

/// The countdown's warning: a short system sound plus a nudge while the app is
/// open, and real notifications for the times one is not looking at it.
enum Alarm {
    static func beep() {
        AudioServicesPlaySystemSound(1057)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    // MARK: Notifications

    /// Every request this app schedules carries this prefix, so replanning can
    /// drop its own pending ones without touching anything else.
    private static let prefix = "radpendler.alarm."

    static var center: UNUserNotificationCenter { .current() }

    enum Permission { case unknown, granted, denied }

    static func permission() async -> Permission {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .unknown
        case .denied: .denied
        default: .granted
        }
    }

    /// Ask once; afterwards the stored answer counts. Returns whether we may
    /// post — the caller stays silent rather than nagging when we may not.
    @discardableResult static func requestPermission() async -> Bool {
        switch await permission() {
        case .granted: return true
        case .denied: return false
        case .unknown:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    /// Replace the pending warnings with the ones for this trip: one per alert
    /// minute before getting ready, plus one at the moment to leave.
    ///
    /// `minutes` counts down to `getReady`, not to the departure — the same
    /// moment the red box and the "los …" chip name.
    ///
    /// Called after every replan, so pulling the screen down re-arms the
    /// warnings against the timetable that just came in. A plan that found
    /// nothing — the connection failed, the phone is offline — leaves the
    /// warnings that are already armed alone: better a warning from five
    /// minutes ago than none at all.
    static func schedule(for option: TripOption?, alerts minutes: [Int], now: Date = .now) async {
        guard !minutes.isEmpty else { return await clear() }
        guard let option, await requestPermission() else { return }
        // Clearing first and awaiting it: the new requests reuse the same
        // identifiers, and a clear that finished late would take them with it.
        await clear()
        for request in requests(for: option, alerts: minutes, now: now) {
            try? await center.add(request)
        }
    }

    static func clear() async {
        let mine = await center.pendingNotificationRequests()
            .map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: mine)
    }

    /// The warnings for one trip, in the order they will fire. Pure, so the
    /// wording and the timing can be tested without the notification centre.
    static func requests(for option: TripOption, alerts minutes: [Int],
                         now: Date = .now) -> [UNNotificationRequest] {
        let go = option.getReady
        let offsets = (minutes.filter { $0 > 0 } + [0]).sorted(by: >)
        return offsets.compactMap { m -> UNNotificationRequest? in
            let fire = go.addingTimeInterval(-Double(m) * 60)
            guard fire.timeIntervalSince(now) > 1 else { return nil }
            let content = UNMutableNotificationContent()
            content.title = m == 0 ? "Jetzt los" : "In \(m) min los"
            content.body = body(option)
            content.sound = .default
            content.interruptionLevel = m == 0 ? .timeSensitive : .active
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, fire.timeIntervalSince(now)), repeats: false)
            return UNNotificationRequest(identifier: "\(prefix)\(m)", content: content, trigger: trigger)
        }
    }

    /// What the notification says once it is open: the mode, when it leaves and
    /// arrives, and the train one would be running for.
    static func body(_ option: TripOption) -> String {
        var text = "\(option.mode.title) \(Fmt.time(option.leave)) → \(Fmt.time(option.arrival))"
        if let leg = option.transitLegs.first {
            let line = leg.lineName.map { "\($0) " } ?? ""
            text += " · \(line)ab \(leg.fromName) \(Fmt.time(leg.departure))"
        }
        return text
    }
}
