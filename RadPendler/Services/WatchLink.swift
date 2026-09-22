import Foundation
import UIKit
import WatchConnectivity

/// Ships the plan to the watch. `updateApplicationContext` is the right
/// channel: it keeps only the newest state, replaces whatever was queued and
/// arrives whether or not the watch app is running — exactly what a plan that
/// is recomputed every few minutes wants.
final class WatchLink: NSObject, WCSessionDelegate {
    static let shared = WatchLink()

    /// Held until the session is up, and sent again when the watch reconnects.
    private var latest: TripSnapshot?
    /// Called when the wrist picked a different trip.
    var onChoice: ((WatchChoice) -> Void)?

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ snapshot: TripSnapshot) {
        latest = snapshot
        flush()
    }

    private func flush() {
        guard WCSession.isSupported(), let snapshot = latest else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? session.updateApplicationContext(["plan": data])
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        flush()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Switching to another watch: activate again and hand the new one the plan.
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        flush()
    }

    // The watch sends its choice either way round: a message while the app is
    // reachable, a queued transfer when it is not.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        accept(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        accept(userInfo)
    }

    private func accept(_ payload: [String: Any]) {
        guard let data = payload["choice"] as? Data,
              let choice = try? JSONDecoder().decode(WatchChoice.self, from: data) else { return }
        DispatchQueue.main.async { [onChoice] in onChoice?(choice) }
    }
}

extension TripSnapshot {
    /// Reduces a finished plan to what the wrist needs.
    init(origin: String, destination: String, options: [TripOption],
         recommendedID: TripOption.ID?, countdownID: TripOption.ID?, computedAt: Date,
         arrivalSearch: Bool, order: [TravelMode]) {
        self.origin = origin
        self.destination = destination
        self.computedAt = computedAt
        self.options = options.map { option in
            // Same rule the phone's own countdown uses.
            let countsDown = arrivalSearch || !option.transitLegs.isEmpty
            // Short walks between two trains are the change, not a leg.
            let legs = option.legs.filter { $0.kind != .walk || ($0.length ?? 0) >= 150 }
            return Option(id: option.id.uuidString,
                          mode: option.mode.rawValue,
                          modeRank: order.firstIndex(of: option.mode) ?? 9,
                          modeTitle: option.mode.title,
                          symbol: option.mode.symbol,
                          colorHex: UIColor(option.mode.color).hexString,
                          caption: Self.caption(option),
                          leave: option.leave, arrival: option.arrival, getReady: option.getReady,
                          transfers: option.transfers,
                          meters: option.totalDistance,
                          rain: option.rain.flatMap { $0.level == .dry ? nil : $0.summary },
                          isRecommended: option.id == recommendedID,
                          countsDown: countsDown,
                          legs: legs.map {
                              Leg(symbol: $0.kind.symbol, line: $0.lineName,
                                  from: $0.fromName, to: $0.toName,
                                  departure: $0.departure, arrival: $0.arrival,
                                  meters: $0.length, colorHex: $0.kind.uiColor.hexString)
                          })
        }
        self.countdownID = countdownID?.uuidString
    }

    /// Same line the mode boxes carry on the phone.
    private static func caption(_ option: TripOption) -> String {
        if let bike = option.bikeRoute { return bike.variants.first?.title ?? "Route" }
        if let car = option.carRoute { return car.variants.first?.title ?? Fmt.km(option.totalDistance) }
        if option.transitLegs.isEmpty { return Fmt.km(option.totalDistance) }
        return option.transfers == 0 ? "ab \(Fmt.time(option.leave))"
                                     : "\(Fmt.time(option.leave)) · \(option.transfers)×"
    }
}

extension UIColor {
    /// "#1FA847" — how a colour travels to the watch.
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}
