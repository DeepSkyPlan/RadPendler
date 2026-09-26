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
    static let settingsKeys = ["origin", "destination", "workPlace", "homePlace", "waypoints", "placeHistory",
                       "bikeLines", "timetableSource", "departurePresets2", "prepMinutes", "bikeMovingSpeedKmh",
                       "bikeStationBufferMinutes", "maxBikeToStationKm", "parkingMinutes",
                       "transferPenaltyMinutes", "signalWaitSeconds", "requireAllWaypoints",
                       "departureBufferMinutes", "arrivalBufferMinutes", "workArrivalMinutes",
                       "alertMinutes", "alertsOn",
                       "modeOrder", "bikeVariantOrder", "carVariantOrder", "rainSwitchLevel",
                       "signalStopSeconds", "learnedSignals", "orientationLock", "rideOrientationLock",
                       "replanOffRouteMeters", "replanOffRouteMinutes", "optionsPerMode",
                       "measuredOverallKmh", "measuredMovingKmh", "measuredRides",
                       "autoStopMinutes", "autoPauseMinutes", "rideStartsLandscape",
                       "rideDimSeconds", "language", "tombstones"]

    /// The recorded rides — summaries only, never their lines. Not a setting,
    /// which is why it stands apart from `settingsKeys`: that list is checked
    /// against everything `AppSettings` writes, and this key belongs to
    /// `RideStore`. It travels on exactly the same terms.
    static let ridesKey = "rides"

    static let keys = settingsKeys + [ridesKey]

    /// The keys that are merged instead of replaced: a device that has not
    /// pulled yet must not be able to shorten a list it has not seen.
    private static let mergedKeys: Set<String> = ["placeHistory", "learnedSignals", ridesKey, tombstonesKey]

    /// Was gelöscht wurde. Wird wie die drei Listen vereinigt — und entscheidet
    /// beim Vereinigen der drei, was hinausfliegt. Ohne ihn ist Löschen mit
    /// zwei Geräten unmöglich: siehe `Tombstones`.
    static let tombstonesKey = "tombstones"

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
    /// Über dem Kontingent nimmt der Dienst nichts mehr an, schickt den
    /// Serverstand zurück und meldet das als Änderung. Weiterzuschreiben hieße,
    /// mit ihm zu streiten — ab da wird nur noch gelesen.
    private var overQuota = false

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
        // Der Stand, gegen den später verglichen wird: was hier schon liegt.
        for key in Self.keys { pushed[key] = defaults.object(forKey: key) }
        // `synchronize()` geht auf die Platte, und dies ist der erste Bildlauf
        // der App — beides gehört nicht auf denselben Faden.
        queue.async { [weak self, cloud] in
            cloud.synchronize()
            // A store that has never been written gets this device's settings;
            // otherwise this device takes what the others agreed on.
            let empty = Self.keys.allSatisfy { cloud.object(forKey: $0) == nil }
            DispatchQueue.main.async {
                guard let self else { return }
                if empty { self.push(Self.keys) } else { self.pull(Self.keys) }
            }
        }
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
        var changed: [String] = []
        for key in keys {
            let value = defaults.object(forKey: key)
            guard !Self.same(value, pushed[key]) else { continue }
            pushed[key] = value
            changed.append(key)
        }
        send(changed)
    }

    /// Hinaus damit, ohne weitere Frage. Der Vergleich ist die Sache des
    /// Aufrufers: nach einem Zusammenführen steht in `pushed` schon das
    /// Ergebnis, und `push` würde nichts mehr zu tun finden.
    private func send(_ keys: [String]) {
        guard !keys.isEmpty, !overQuota else { return }
        let values: [String: Any?] = keys.reduce(into: [:]) { $0[$1] = defaults.object(forKey: $1) }
        queue.async { [cloud] in
            for (key, value) in values {
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
        if note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            == NSUbiquitousKeyValueStoreQuotaViolationChange {
            overQuota = true
        }
        let changed = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
        pull((changed ?? Self.keys).filter { Self.keys.contains($0) })
    }

    /// Was aus einem Schlüssel werden soll, wenn die Wolke sich gemeldet hat.
    private enum Resolution {
        case set(Any)
        case remove
        /// Nichts tun — was hier steht, ist das Bessere.
        case keep
    }

    /// Liest, was drüben steht, und führt es mit dem hiesigen Stand zusammen.
    ///
    /// Das Zusammenführen ist der teure Teil: zlib für die Fahrten, JSON für
    /// alles andere, und `LearnedSignal.merging` vergleicht jeden Eintrag mit
    /// jedem. Es läuft deshalb neben dem Hauptthread; auf ihm bleibt nur das
    /// Hinschreiben des Ergebnisses.
    private func pull(_ keys: [String]) {
        guard !keys.isEmpty else { return }
        let mine: [String: Data] = keys.filter(Self.mergedKeys.contains)
            .reduce(into: [:]) { $0[$1] = defaults.data(forKey: $1) }
        queue.async { [weak self, cloud] in
            var resolved: [String: Resolution] = [:]
            var had: [String: Any] = [:]
            // Zuerst die Grabsteine beider Seiten: sie entscheiden, was beim
            // Vereinigen der drei Listen hinausfliegt.
            let graves = Self.tombstones(local: mine[Self.tombstonesKey],
                                         cloud: cloud.data(forKey: Self.tombstonesKey))
            for key in keys {
                guard let value = cloud.object(forKey: key) else {
                    // Gone from the cloud means deleted somewhere, not "no news":
                    // an address removed on the phone stayed on the iPad forever.
                    // The merged list is the exception — it is never shortened.
                    resolved[key] = Self.mergedKeys.contains(key) ? .keep : .remove
                    continue
                }
                had[key] = value
                if Self.mergedKeys.contains(key), let incoming = value as? Data {
                    resolved[key] = .set(Self.merged(key, local: mine[key], cloud: incoming,
                                                     graves: graves) ?? incoming)
                } else {
                    resolved[key] = .set(value)
                }
            }
            DispatchQueue.main.async { self?.apply(resolved, cloudHad: had) }
        }
    }

    private func apply(_ resolved: [String: Resolution], cloudHad: [String: Any]) {
        applying = true
        for (key, what) in resolved {
            switch what {
            case .set(let value): defaults.set(value, forKey: key)
            case .remove: defaults.removeObject(forKey: key)
            case .keep: break
            }
        }
        onPull?()
        applying = false
        // Erst **jetzt** festhalten, was draußen steht — nach `onPull`, nicht
        // davor. `AppSettings.load()` normalisiert beim Lesen: eine Reihenfolge
        // ohne einen Eintrag, den diese Fassung kennt, bekommt ihn angehängt.
        // Stand hier der Stand von vor `onPull`, galt diese Normalisierung als
        // Änderung und ging zurück in die Wolke — wo das andere Gerät sie
        // wieder wegnahm und zurückschrieb. Zwischen zwei Geräten mit
        // verschiedenen Ständen ist das ein Pingpong ohne Ende.
        for key in resolved.keys { pushed[key] = defaults.object(forKey: key) }
        // Was das Zusammenführen dazugewonnen hat, muss dagegen hinaus, sonst
        // erfährt das andere Gerät nie von den Einträgen, die nur hier standen.
        // Das stand schon immer hier — nur wirkungslos, weil `pushed` damals
        // vor `onPull` gesetzt wurde und der Vergleich nie etwas fand.
        send(resolved.keys.filter {
            Self.mergedKeys.contains($0) && !Self.same(defaults.object(forKey: $0), cloudHad[$0])
        })
    }

    /// Both lists into one; nil when either side cannot be read, so the caller
    /// falls back to what came in.
    /// Die Grabsteine beider Seiten, für die Vereinigung der drei Listen.
    /// Sie kommen aus denselben zwei Quellen wie alles andere: was hier liegt
    /// und was in der Wolke steht.
    static func tombstones(local: Data?, cloud: Data?) -> Tombstones {
        let decoder = JSONDecoder()
        let mine = local.flatMap { try? decoder.decode(Tombstones.self, from: $0) } ?? Tombstones()
        let theirs = cloud.flatMap { try? decoder.decode(Tombstones.self, from: $0) } ?? Tombstones()
        return mine.merging(theirs)
    }

    static func merged(_ key: String, local: Data?, cloud: Data, graves: Tombstones = Tombstones()) -> Data? {
        guard let local else { return nil }
        let decoder = JSONDecoder()
        if key == Self.tombstonesKey {
            return try? JSONEncoder().encode(Self.tombstones(local: local, cloud: cloud))
        }
        if key == Self.ridesKey {
            guard let mine = RideStore.decode(local), let theirs = RideStore.decode(cloud) else { return nil }
            let all = RideStore.merge(mine, theirs)
                .filter { !graves.buried(Tombstones.key(ride: $0.id), newerThan: $0.started) }
            return RideStore.encode(all)
        }
        if key == "learnedSignals" {
            guard let mine = try? decoder.decode([LearnedSignal].self, from: local),
                  let theirs = try? decoder.decode([LearnedSignal].self, from: cloud) else { return nil }
            let all = LearnedSignal.merging(mine, theirs)
                .filter { !graves.buried(Tombstones.key(signal: $0.id), newerThan: $0.lastSeen) }
            return try? JSONEncoder().encode(all)
        }
        guard let mine = try? decoder.decode([PlaceUse].self, from: local),
              let theirs = try? decoder.decode([PlaceUse].self, from: cloud) else { return nil }
        let all = mine.merging(theirs)
            .filter { !graves.buried(Tombstones.key(place: $0.id), newerThan: $0.lastUsed) }
        return try? JSONEncoder().encode(all)
    }
}
