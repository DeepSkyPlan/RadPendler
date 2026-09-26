import Foundation
import Observation
import WatchConnectivity

/// Holds the last plan the phone sent. It is kept on disk as well, so opening
/// the app out of range shows the last known departure instead of nothing —
/// with its age on screen, because an old plan is worth exactly as much as one
/// knows it is old.
@MainActor
@Observable
final class WatchModel {
    private(set) var snapshot: TripSnapshot?
    /// The ride the phone is recording, or the summary of the one it just
    /// finished. The watch records nothing itself — it has no track, no
    /// junctions and no business starting a second recording of the same ride.
    private(set) var live: RideLive?
    /// What the wrist picked: a category and which of its options. Kept as
    /// mode plus position, never as an id — every new plan brings new ids, and
    /// "the second bike route" survives a replan where an id does not.
    private(set) var chosenMode: String?
    private(set) var chosenIndex = 0

    /// A finished ride stays on the wrist for an hour: long enough to look at
    /// after arriving, short enough not to be there next morning.
    static let summaryLifetime: TimeInterval = 3600

    private let link = PhoneLink()

    /// Die Uhr hat keine eigene Sprachwahl: sie zeigt den Plan des Telefons
    /// und spricht deshalb dessen Sprache. Ohne Angabe (ältere Fassung auf dem
    /// Telefon) bleibt es bei dem, was die Uhr selbst eingestellt hat.
    private static func speak(_ language: String?) {
        AppLanguage.current = language.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    init() {
        snapshot = PhoneLink.cached()
        live = Self.fresh(PhoneLink.cachedRide())
        chosenMode = UserDefaults.standard.string(forKey: "chosenMode")
        chosenIndex = UserDefaults.standard.integer(forKey: "chosenIndex")
        Self.speak(snapshot?.language)
        link.onPlan = { [weak self] plan in
            Task { @MainActor in
                Self.speak(plan.language)
                self?.accept(plan)
            }
        }
        link.onRide = { [weak self] ride in
            Task { @MainActor in self?.live = Self.fresh(ride) }
        }
        link.start()
    }

    /// A ride worth a page: one that is running, or one that ended within the
    /// hour. Anything older is history, and history lives on the phone.
    static func fresh(_ ride: RideLive?, now: Date = .now) -> RideLive? {
        guard let ride else { return nil }
        if ride.running { return ride }
        return now.timeIntervalSince(ride.at) < summaryLifetime ? ride : nil
    }

    /// Sweeps away a summary that has sat there long enough; called by the view
    /// as it redraws, so the page goes away on its own.
    func expireSummary(now: Date = .now) {
        if live != nil, Self.fresh(live, now: now) == nil { live = nil }
    }

    /// Ein **neuer** Plan setzt die Wahl am Handgelenk zurück — genau wie auf
    /// dem Telefon, wo `selection` nach jedem Lauf geleert wird.
    ///
    /// Vorher behielt die Uhr ihre Wahl über jede Neuplanung hinweg, und
    /// danach zeigten die beiden Bildschirme Verschiedenes, bis jemand
    /// irgendwo tippte. Die Uhr ist aber kein zweiter Planer, sondern ein
    /// zweiter Blick auf denselben Plan.
    ///
    /// Am Zeitpunkt der Berechnung, nicht an der Ankunft: tippt man auf der
    /// Uhr eine andere Fahrt an, schickt sie die Wahl zum Telefon, und das
    /// Telefon schickt denselben Plan zurück. Der darf die Wahl nicht wieder
    /// wegnehmen.
    private func accept(_ plan: TripSnapshot) {
        if plan.computedAt != snapshot?.computedAt, chosenMode != nil { followPhone() }
        snapshot = plan
    }

    /// The trip everything on the watch is about: what the wrist picked, or —
    /// until it picks something — what the phone recommended.
    var selected: TripSnapshot.Option? {
        guard let plan = snapshot else { return nil }
        guard let mode = chosenMode else { return plan.countdown ?? plan.recommended ?? plan.options.first }
        let own = plan.options(in: mode)
        guard !own.isEmpty else { return plan.countdown ?? plan.recommended ?? plan.options.first }
        return own[min(chosenIndex, own.count - 1)]
    }

    /// Which category is on screen, even before anything was picked.
    var activeMode: String? { chosenMode ?? selected?.mode }

    func choose(mode: String, index: Int = 0) {
        chosenMode = mode
        chosenIndex = index
        UserDefaults.standard.set(mode, forKey: "chosenMode")
        UserDefaults.standard.set(index, forKey: "chosenIndex")
        // The phone follows: the same trip should be on both screens, and the
        // warnings come from the phone.
        link.send(WatchChoice(mode: mode, index: index))
    }

    /// Back to what the phone thinks is best.
    func followPhone() {
        chosenMode = nil
        chosenIndex = 0
        UserDefaults.standard.removeObject(forKey: "chosenMode")
        UserDefaults.standard.removeObject(forKey: "chosenIndex")
    }

    func isChosen(_ option: TripSnapshot.Option) -> Bool { selected?.id == option.id }
}

/// The receiving half of `WatchLink` on the phone.
final class PhoneLink: NSObject, WCSessionDelegate {
    var onPlan: ((TripSnapshot) -> Void)?
    var onRide: ((RideLive) -> Void)?
    private static let key = "lastPlan"
    private static let rideKey = "lastRide"

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Straight over when the phone is reachable, queued when it is not.
    func send(_ choice: WatchChoice) {
        guard WCSession.isSupported(), let data = try? JSONEncoder().encode(choice) else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(["choice": data], replyHandler: nil) { _ in
                session.transferUserInfo(["choice": data])
            }
        } else {
            session.transferUserInfo(["choice": data])
        }
    }

    static func cached() -> TripSnapshot? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(TripSnapshot.self, from: $0) }
    }

    static func cachedRide() -> RideLive? {
        UserDefaults.standard.data(forKey: rideKey).flatMap { try? JSONDecoder().decode(RideLive.self, from: $0) }
    }

    /// Both channels end here: the plan arrives in the application context,
    /// the running ride as a message once a second and in the context every
    /// now and then.
    private func accept(_ payload: [String: Any]) {
        if let data = payload["plan"] as? Data,
           let plan = try? JSONDecoder().decode(TripSnapshot.self, from: data) {
            UserDefaults.standard.set(data, forKey: Self.key)
            onPlan?(plan)
        }
        if let data = payload["ride"] as? Data,
           let ride = try? JSONDecoder().decode(RideLive.self, from: data) {
            UserDefaults.standard.set(data, forKey: Self.rideKey)
            onRide?(ride)
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        // Whatever was sent while the app was closed is waiting right here.
        accept(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        accept(context)
    }

    /// The running ride, once a second, while the watch is reachable.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        accept(message)
    }
}
