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
    /// What the wrist picked: a category and which of its options. Kept as
    /// mode plus position, never as an id — every new plan brings new ids, and
    /// "the second bike route" survives a replan where an id does not.
    private(set) var chosenMode: String?
    private(set) var chosenIndex = 0

    private let link = PhoneLink()

    init() {
        snapshot = PhoneLink.cached()
        chosenMode = UserDefaults.standard.string(forKey: "chosenMode")
        chosenIndex = UserDefaults.standard.integer(forKey: "chosenIndex")
        link.onPlan = { [weak self] plan in
            Task { @MainActor in self?.snapshot = plan }
        }
        link.start()
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
    private static let key = "lastPlan"

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    static func cached() -> TripSnapshot? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(TripSnapshot.self, from: $0) }
    }

    private func accept(_ context: [String: Any]) {
        guard let data = context["plan"] as? Data,
              let plan = try? JSONDecoder().decode(TripSnapshot.self, from: data) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
        onPlan?(plan)
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        // Whatever was sent while the app was closed is waiting right here.
        accept(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        accept(context)
    }
}
