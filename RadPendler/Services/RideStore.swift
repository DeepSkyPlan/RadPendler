import Foundation
import Observation

/// Where the recorded rides live: a short summary per ride in the settings
/// store — and therefore in iCloud, like everything else the app keeps — and
/// the line of each ride in a file of its own on the device.
///
/// The split is what makes this fit at all. The iCloud key-value store holds
/// **one megabyte in total** for the whole app; a summary is some two hundred
/// bytes, a line is eighty kilobytes. So the numbers travel and the drawing
/// stays where it was drawn: a ride recorded on the phone is in the list on the
/// iPad with every figure it has, and only its map says "not on this device".
///
/// Like `CloudStore`, the travelling half is optional: without an iCloud
/// account everything simply stays on the one device.
@MainActor
@Observable
final class RideStore {
    static let shared = RideStore()

    /// Newest first — the order the list shows them in.
    private(set) var rides: [Ride] = []

    /// More than a decade of commuting, and still far inside the budget: a
    /// thousand summaries are some two hundred kilobytes before compression.
    /// Over the limit the oldest go, because the recent months are what the
    /// list is read for.
    nonisolated static let maxRides = 1000

    private let folder: URL
    private let defaults: UserDefaults
    private var tracks: [UUID: RideTrack] = [:]

    /// Die gefahrenen Wege, aus denen die Planung lernt — neben den Linien.
    let habits: RiddenPaths

    init(folder: URL? = nil, defaults: UserDefaults = .standard) {
        self.folder = folder ?? Self.defaultFolder()
        self.defaults = defaults
        habits = folder.map { RiddenPaths(file: $0.appending(path: "ridden.json")) } ?? .shared
        let tracksFolder = self.folder.appending(path: "tracks")
        Log.attempt("Fahrtenordner anlegen") {
            try FileManager.default.createDirectory(at: tracksFolder, withIntermediateDirectories: true)
        }
        reload()
    }

    private static func defaultFolder() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return base.appending(path: "Rides")
    }

    private var interruptedFile: URL { folder.appending(path: "current.json") }
    private func trackFile(_ id: UUID) -> URL {
        folder.appending(path: "tracks").appending(path: "\(id.uuidString).json")
    }

    // MARK: The list

    /// Also the way back in after iCloud handed us another device's rides —
    /// `CloudStore` writes the key and calls this.
    func reload() {
        rides = defaults.data(forKey: CloudStore.ridesKey).flatMap(Self.decode) ?? []
    }

    private func write() {
        rides.sort(by: Self.newestFirst)
        if rides.count > Self.maxRides { rides = Array(rides.prefix(Self.maxRides)) }
        guard let data = Self.encode(rides) else { return }
        defaults.set(data, forKey: CloudStore.ridesKey)
    }

    func add(_ ride: Ride, track: RideTrack) {
        rides.removeAll { $0.id == ride.id }
        rides.append(ride)
        tracks[ride.id] = track
        if let data = Log.attempt("Linie kodieren", { try JSONEncoder().encode(track) }) {
            // Eine gefahrene Linie ist der Weg von der Haustür zur Arbeit.
            // Ohne Schutzklasse ist sie auf einem gesperrten, aber gebooteten
            // Gerät lesbar; `unlessOpen` und nicht `complete`, weil während
            // einer Aufzeichnung geschrieben wird, auch mit gesperrtem Schirm.
            let file = trackFile(ride.id)
            Log.attempt("Linie schreiben") {
                try data.write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
            }
        }
        write()
        // Und die Linie zu den anderen Geräten. Ohne Container ein stiller
        // Nichtstuer; die Fahrt ist hier schon abgelegt, bevor irgendetwas
        // reist.
        Task { await TrackCloud.shared.upload(track) }
        Task { [habits] in await habits.add(ride, track: track) }
    }

    func delete(_ ride: Ride) {
        rides.removeAll { $0.id == ride.id }
        tracks[ride.id] = nil
        let file = trackFile(ride.id)
        Log.attempt("Linie löschen", missingIsFine: true) { try FileManager.default.removeItem(at: file) }
        // Der Grabstein muss **vor** dem Schreiben stehen: `write()` schiebt die
        // gekürzte Liste in die Wolke, und das andere Gerät vereinigt sie sofort
        // — ohne Grabstein käme die Fahrt im selben Atemzug zurück.
        Tombstones.bury([Tombstones.key(ride: ride.id)], in: defaults)
        write()
        Task { await TrackCloud.shared.delete(ride.id) }
        Task { [habits] in await habits.remove(ride.id) }
    }

    /// The line of one ride, from memory or from disk. nil means it was
    /// recorded on another device: the numbers travelled, the drawing did not,
    /// and the detail view says so instead of showing an empty map.
    /// Reading and decoding happen off the main actor: a long ride is some
    /// eighty kilobytes of JSON, and decoding it while a list is scrolling is
    /// a stutter with a cause nobody can see.
    func track(for ride: Ride) async -> RideTrack? {
        if let t = tracks[ride.id] { return t }
        let url = trackFile(ride.id)
        let decoded = await Task.detached(priority: .userInitiated) { () -> RideTrack? in
            guard let data = Log.attempt("Linie lesen", missingIsFine: true, { try Data(contentsOf: url) })
            else { return nil }
            return Log.attempt("Linie dekodieren") { try JSONDecoder().decode(RideTrack.self, from: data) }
        }.value
        if let decoded {
            tracks[ride.id] = decoded
            return decoded
        }
        // Nicht auf dieser Platte: dann wurde sie auf einem anderen Gerät
        // gezeichnet. Die Zahlen sind über den Schlüssel-Wert-Speicher
        // gereist, die Linie liegt in CloudKit — und was von dort kommt, wird
        // hier abgelegt, damit die zweite Ansicht sie nicht noch einmal holt.
        guard let fetched = await TrackCloud.shared.download(ride.id) else { return nil }
        tracks[ride.id] = fetched
        if let data = Log.attempt("Linie kodieren", { try JSONEncoder().encode(fetched) }) {
            Log.attempt("Linie aus iCloud ablegen") {
                try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
            }
        }
        return fetched
    }

    // MARK: Packing

    /// Compressed, because this goes into a store with a one-megabyte ceiling
    /// that the settings share. Uncompressed JSON is the fallback, so a value
    /// written by a version that could not compress still reads.
    nonisolated static func encode(_ rides: [Ride]) -> Data? {
        guard let json = Stored.encode(rides) else { return nil }
        return (try? (json as NSData).compressed(using: .zlib)) as Data? ?? json
    }

    ///
    /// Der eine Eingang für beide Quellen, UserDefaults wie iCloud: eine
    /// Fahrt, die diese Fassung nicht lesen kann, fällt allein heraus, und was
    /// bleibt, ist begrenzt (`Ride.sanitized`).
    nonisolated static func decode(_ data: Data) -> [Ride]? {
        let raw = (try? (data as NSData).decompressed(using: .zlib) as Data) ?? data
        guard let list: [Ride] = Stored.list(from: raw) ?? Stored.list(from: data) else { return nil }
        return list.compactMap(\.sanitized).sorted(by: newestFirst)
    }

    /// Bei gleicher Startzeit entscheidet die Kennung — die Reihenfolge muss
    /// auf jedem Gerät dieselbe sein.
    nonisolated static func newestFirst(_ a: Ride, _ b: Ride) -> Bool {
        (a.started, a.id.uuidString) > (b.started, b.id.uuidString)
    }

    /// Two devices' lists into one. A ride is the same ride wherever it is
    /// read, so its id decides and nothing is ever counted twice; a device
    /// that has not pulled yet must not be able to shorten the list it has
    /// not seen. Deleting therefore needs both devices to be reached — the
    /// price of a merge, and cheaper than a ride that vanishes.
    ///
    /// Wo beide dieselbe Fahrt verschieden kennen, entscheidet `Ride.fuller`
    /// — auf beiden Geräten gleich, in welcher Reihenfolge auch immer.
    nonisolated static func merge(_ mine: [Ride], _ theirs: [Ride]) -> [Ride] {
        var byID: [UUID: Ride] = [:]
        for ride in mine + theirs {
            byID[ride.id] = byID[ride.id].map { Ride.fuller($0, ride) } ?? ride
        }
        let out = byID.values.sorted(by: newestFirst)
        return out.count > maxRides ? Array(out.prefix(maxRides)) : out
    }

    // MARK: A ride the app did not survive

    /// So viele Punkte gehen höchstens in die Zwischensicherung. Die Linie
    /// selbst darf so lang werden, wie die Fahrt dauert — diese Kopie hier
    /// nicht: sie wird im Minutentakt neu geschrieben und beim nächsten Start
    /// wieder eingelesen, und beides muss eine feste Obergrenze haben. Bei
    /// einem Punkt je Sekunde sind 20 000 gut fünfeinhalb Stunden Fahrt; was
    /// länger ist, wird ausgedünnt und verliert nichts als Zwischenpunkte.
    nonisolated static let maxInterruptedPoints = 20_000

    /// Jeden n-ten Punkt, Anfang und Ende immer. Die Halte bleiben vollzählig:
    /// es sind wenige, und sie sind der Grund, aus dem die Fahrt gezählt wird.
    nonisolated static func thinned(_ track: RideTrack) -> RideTrack {
        guard track.points.count > maxInterruptedPoints else { return track }
        let step = (track.points.count + maxInterruptedPoints - 1) / maxInterruptedPoints
        var kept = stride(from: 0, to: track.points.count, by: step).map { track.points[$0] }
        if let last = track.points.last, kept.last != last { kept.append(last) }
        // Die geplante Linie bleibt: sie ist ohnehin ausgedünnt, und gerade
        // bei einer abgebrochenen Fahrt ist der Vergleich „geplant gegen
        // gefahren" das Interessante.
        var out = track
        out.points = kept
        return out
    }

    /// Written while recording, so a ride does not die with the process.
    /// `clearInterrupted` removes it the moment the ride ends properly.
    ///
    /// Kodieren und Schreiben laufen **neben** dem Hauptthread. Vorher lag
    /// beides darauf: eine lange Fahrt ist einige Megabyte JSON, die Linie
    /// steckt zweimal kodiert darin, und das mitten in einer Fahrt, während
    /// die Karte mitläuft.
    func saveInterrupted(_ state: (Ride, RideTrack)) {
        let url = interruptedFile
        let ride = state.0, track = Self.thinned(state.1)
        Task.detached(priority: .utility) {
            guard let blob = Log.attempt("Zwischenstand kodieren", {
                try JSONEncoder().encode(Interrupted(ride: JSONEncoder().encode(ride),
                                                     track: JSONEncoder().encode(track)))
            }) else { return }
            Log.attempt("Zwischenstand schreiben") {
                try blob.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
            }
        }
    }

    func clearInterrupted() {
        let file = interruptedFile
        Log.attempt("Zwischenstand löschen", missingIsFine: true) { try FileManager.default.removeItem(at: file) }
    }

    /// Called at launch: whatever was being recorded when the app went away is
    /// filed as the ride it was, up to its last known second.
    ///
    /// **Erst löschen, dann dekodieren.** Vorher stand das Löschen hinter dem
    /// Dekodieren: dauerte das länger, als der Watchdog erlaubt, starb die App
    /// davor — und beim nächsten Start wieder, an derselben Datei. Eine
    /// Startschleife, aus der nur das Löschen der App herausführt. Jetzt sind
    /// die Bytes gelesen und die Datei weg, bevor irgendetwas ausgepackt wird;
    /// im schlimmsten Fall geht eine abgebrochene Aufzeichnung verloren, und
    /// das ist allemal besser als eine App, die nicht mehr startet.
    ///
    /// Lesen, Löschen und Auspacken laufen neben dem Hauptthread; nur das
    /// Ablegen in der Liste läuft auf ihm.
    /// Einmal nach einem Wechsel des CloudKit-Containers: was lokal liegt,
    /// wandert noch einmal hinauf.
    ///
    /// Ein Container ist ein eigener Speicher; wer den Namen ändert, fängt
    /// drüben bei null an. Die Linien sind aber nicht weg — sie liegen auf dem
    /// Gerät, das sie aufgezeichnet hat. Also schiebt dieses Gerät sie einmal
    /// nach, und danach steht der Name des Containers im Merker: passiert
    /// genau einmal je Container, nicht bei jedem Start.
    func reuploadTracksIfNeeded() async {
        let key = "tracksUploadedTo"
        guard defaults.string(forKey: key) != TrackCloud.containerID else { return }
        // Erst merken, dann hochladen: ein Abbruch mitten im Nachschieben darf
        // nicht dazu führen, dass beim nächsten Start alles wieder losgeht.
        // Was liegen bleibt, geht beim nächsten Aufzeichnen ohnehin mit.
        defaults.set(TrackCloud.containerID, forKey: key)
        let ids = rides.map(\.id)
        for id in ids {
            let file = trackFile(id)
            guard let data = Log.attempt("Linie lesen", missingIsFine: true, { try Data(contentsOf: file) }),
                  let track = Log.attempt("Linie dekodieren", { try JSONDecoder().decode(RideTrack.self, from: data) })
            else { continue }
            await TrackCloud.shared.upload(track)
        }
    }

    /// Einmal: die Radfahrten von vor 1.9 lernen nach. Was auf diesem Gerät
    /// keine Linie hat, bleibt draußen — es kommt dazu, sobald es gefahren wird.
    func learnHabitsIfNeeded() async {
        let key = "habitsLearned"
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        for ride in rides where ride.travelMode == .bike {
            guard let track = await track(for: ride) else { continue }
            await habits.add(ride, track: track)
        }
    }

    /// Einmal je Fahrt: das Stehen vor den Pausen älterer Fahrten wird zur
    /// Pause, so wie es neue Fahrten von selbst tun. Gerechnet wird aus der
    /// Linie; wo sie fehlt (auf einem anderen Gerät gezeichnet und noch nicht
    /// in CloudKit), bleibt die Fahrt, wie sie ist, und kommt beim nächsten
    /// Start wieder dran. Beim Zusammenführen gewinnt die reparierte Fassung
    /// (`Ride.fuller`), und der Merker an der Fahrt hält fest, dass nichts
    /// zweimal abgezogen wird.
    ///
    /// Bleibt, obwohl es aus 1.6 stammt: eine Fahrt, deren Linie erst noch
    /// aus CloudKit kommt, wartet hier auf ihre Reparatur — und wann das
    /// ist, weiß niemand. Kostet nach getaner Arbeit einen Filter beim Start.
    func repairStandingBeforePauses() async {
        let todo = rides.filter { $0.pausedSeconds > 0 && $0.standingInPause != true }
        guard !todo.isEmpty else { return }
        var changed = false
        for ride in todo {
            guard let track = await track(for: ride),
                  let k = rides.firstIndex(where: { $0.id == ride.id }) else { continue }
            let extra = Ride.standingBeforePauses(track.points, pausedSeconds: ride.pausedSeconds)
            // Nie mehr, als an Fahrzeit neben dem Rollen übrig ist.
            rides[k].pausedSeconds += min(extra, rides[k].standingSeconds)
            rides[k].standingInPause = true
            changed = true
        }
        if changed { write() }
    }

    func recoverInterrupted() async {
        let url = interruptedFile
        let recovered = await Task.detached(priority: .userInitiated) { () -> (Ride, RideTrack)? in
            guard let data = Log.attempt("Zwischenstand lesen", missingIsFine: true, { try Data(contentsOf: url) })
            else { return nil }
            Log.attempt("Zwischenstand löschen", missingIsFine: true) { try FileManager.default.removeItem(at: url) }
            return Log.attempt("Zwischenstand dekodieren") {
                let saved = try JSONDecoder().decode(Interrupted.self, from: data)
                return (try JSONDecoder().decode(Ride.self, from: saved.ride),
                        try JSONDecoder().decode(RideTrack.self, from: saved.track))
            }
        }.value
        guard let (ride, track) = recovered else { return }
        guard ride.seconds >= 60, ride.meters >= 100, !rides.contains(where: { $0.id == ride.id }) else { return }
        add(ride, track: track)
    }

    struct Interrupted: Codable {
        var ride: Data
        var track: Data
    }
}
