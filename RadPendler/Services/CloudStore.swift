import Foundation

/// Carries the settings — addresses, the list of addresses already used, every
/// preference — between the user's own devices through iCloud's key-value
/// store. UserDefaults stays the local truth; iCloud is the copy that travels.
///
/// Nothing here is required. Without an iCloud account every call is a quiet
/// no-op and the app behaves exactly as it did before.
///
/// Changes are picked up by watching `UserDefaults.didChangeNotification`
/// rather than by touching every setter in `AppSettings`: one place that knows
/// about the cloud instead of twenty.
final class CloudStore {
    static let shared = CloudStore()

    /// Exactly what is worth carrying — never everything UserDefaults holds.
    /// The watch's own keys (the last plan, what the wrist picked) are not in
    /// here: that state belongs to the watch it was made on.
    /// `testEverySettingTheAppSavesAlsoTravelsThroughICloud` fails when a new
    /// setting is added to `AppSettings` and forgotten here — which is how the
    /// four preference lists missed the boat between 0.10.0 and 0.12.1.
    static let keys = ["origin", "destination", "workPlace", "homePlace", "waypoints", "placeHistory",
                       "bikeLines", "timetableSource", "departurePresets2", "prepMinutes", "bikeMovingSpeedKmh",
                       "bikeStationBufferMinutes", "maxBikeToStationKm", "parkingMinutes",
                       "transferPenaltyMinutes", "signalWaitSeconds", "requireAllWaypoints",
                       "departureBufferMinutes", "arrivalBufferMinutes", "workArrivalMinutes",
                       "alertMinutes", "alertsOn",
                       "modeOrder", "bikeVariantOrder", "carVariantOrder", "rainSwitchLevel"]

    /// The one key that is merged instead of replaced: a device that has not
    /// pulled yet must not be able to shorten the list it has not seen.
    private static let mergedKey = "placeHistory"

    /// Called after values came in from another device.
    var onPull: (() -> Void)?

    private let cloud = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard
    /// True while incoming values are being written locally, so the write-back
    /// does not echo them straight out again.
    private var applying = false
    private var pushWork: DispatchWorkItem?
    private var started = false
    /// What was last handed to iCloud. `UserDefaults.didChangeNotification`
    /// fires for every write anywhere in the process, most of which have
    /// nothing to do with us; without this the store was rewritten and flushed
    /// every half second, and the settings list stuttered while scrolling.
    private var pushed: [String: Any] = [:]
    private let queue = DispatchQueue(label: "de.keese.radpendler.cloud", qos: .utility)

    /// Whether iCloud is doing anything at all — for the line in the settings.
    private(set) var available = false

    func start() {
        guard !started else { return }
        started = true
        available = FileManager.default.ubiquityIdentityToken != nil
        NotificationCenter.default.addObserver(self, selector: #selector(cloudChanged(_:)),
                                               name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                               object: cloud)
        NotificationCenter.default.addObserver(self, selector: #selector(localChanged),
                                               name: UserDefaults.didChangeNotification,
                                               object: defaults)
        cloud.synchronize()
        // A store that has never been written gets this device's settings;
        // otherwise this device takes what the others agreed on.
        if Self.keys.allSatisfy({ cloud.object(forKey: $0) == nil }) {
            push(Self.keys)
        } else {
            pull(Self.keys)
        }
        for key in Self.keys where pushed[key] == nil { pushed[key] = defaults.object(forKey: key) }
    }

    // MARK: Out

    @objc private func localChanged() {
        guard !applying else { return }
        // Settings arrive in bursts (a sheet closing writes several); one look
        // just after the burst instead of one per notification.
        pushWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.push(Self.keys) }
        pushWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// Writes only what actually differs from what iCloud already has, and
    /// writes it off the main thread — `synchronize()` touches the disk.
    private func push(_ keys: [String]) {
        var changed: [String: Any?] = [:]
        for key in keys {
            let value = defaults.object(forKey: key)
            guard !Self.same(value, pushed[key]) else { continue }
            changed[key] = value
            if let value { pushed[key] = value } else { pushed[key] = nil }
        }
        guard !changed.isEmpty else { return }
        queue.async { [cloud] in
            for (key, value) in changed {
                if let value { cloud.set(value, forKey: key) } else { cloud.removeObject(forKey: key) }
            }
            cloud.synchronize()
        }
    }

    /// Property-list values compare by content, not by identity.
    static func same(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case (nil, _), (_, nil): false
        default: NSDictionary(dictionary: ["v": a!]).isEqual(to: ["v": b!])
        }
    }

    // MARK: In

    @objc private func cloudChanged(_ note: Notification) {
        let changed = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
        pull((changed ?? Self.keys).filter { Self.keys.contains($0) })
    }

    private func pull(_ keys: [String]) {
        guard !keys.isEmpty else { return }
        applying = true
        for key in keys {
            guard let value = cloud.object(forKey: key) else {
                // Gone from the cloud means deleted somewhere, not "no news":
                // an address removed on the phone stayed on the iPad forever.
                // The merged list is the exception — it is never shortened.
                if key != Self.mergedKey { defaults.removeObject(forKey: key) }
                continue
            }
            if key == Self.mergedKey, let incoming = value as? Data {
                defaults.set(Self.mergedHistory(local: defaults.data(forKey: key), cloud: incoming) ?? incoming,
                             forKey: key)
            } else {
                defaults.set(value, forKey: key)
            }
        }
        for key in keys { pushed[key] = defaults.object(forKey: key) }
        onPull?()
        applying = false
        // Whatever the merge produced has to go back out, or the other device
        // never learns about the entries only this one had.
        if keys.contains(Self.mergedKey) { push([Self.mergedKey]) }
    }

    /// Both lists into one; nil when either side cannot be read, so the caller
    /// falls back to what came in.
    static func mergedHistory(local: Data?, cloud: Data) -> Data? {
        let decoder = JSONDecoder()
        guard let local, let mine = try? decoder.decode([PlaceUse].self, from: local),
              let theirs = try? decoder.decode([PlaceUse].self, from: cloud) else { return nil }
        return try? JSONEncoder().encode(mine.merging(theirs))
    }
}
