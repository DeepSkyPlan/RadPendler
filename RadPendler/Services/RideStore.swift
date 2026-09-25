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

    init(folder: URL? = nil, defaults: UserDefaults = .standard) {
        self.folder = folder ?? Self.defaultFolder()
        self.defaults = defaults
        try? FileManager.default.createDirectory(at: self.folder.appending(path: "tracks"),
                                                 withIntermediateDirectories: true)
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
        rides.sort { $0.started > $1.started }
        if rides.count > Self.maxRides { rides = Array(rides.prefix(Self.maxRides)) }
        guard let data = Self.encode(rides) else { return }
        defaults.set(data, forKey: CloudStore.ridesKey)
    }

    func add(_ ride: Ride, track: RideTrack) {
        rides.removeAll { $0.id == ride.id }
        rides.append(ride)
        tracks[ride.id] = track
        if let data = try? JSONEncoder().encode(track) {
            // Eine gefahrene Linie ist der Weg von der Haustür zur Arbeit.
            // Ohne Schutzklasse ist sie auf einem gesperrten, aber gebooteten
            // Gerät lesbar; `unlessOpen` und nicht `complete`, weil während
            // einer Aufzeichnung geschrieben wird, auch mit gesperrtem Schirm.
            try? data.write(to: trackFile(ride.id), options: [.atomic, .completeFileProtectionUnlessOpen])
        }
        write()
        // Und die Linie zu den anderen Geräten. Ohne Container ein stiller
        // Nichtstuer; die Fahrt ist hier schon abgelegt, bevor irgendetwas
        // reist.
        Task { await TrackCloud.shared.upload(track) }
    }

    func delete(_ ride: Ride) {
        rides.removeAll { $0.id == ride.id }
        tracks[ride.id] = nil
        try? FileManager.default.removeItem(at: trackFile(ride.id))
        write()
        Task { await TrackCloud.shared.delete(ride.id) }
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
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(RideTrack.self, from: data)
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
        if let data = try? JSONEncoder().encode(fetched) {
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        }
        return fetched
    }

    // MARK: Packing

    /// Compressed, because this goes into a store with a one-megabyte ceiling
    /// that the settings share. Uncompressed JSON is the fallback, so a value
    /// written by a version that could not compress still reads.
    nonisolated static func encode(_ rides: [Ride]) -> Data? {
        guard let json = try? JSONEncoder().encode(rides) else { return nil }
        return (try? (json as NSData).compressed(using: .zlib)) as Data? ?? json
    }

    nonisolated static func decode(_ data: Data) -> [Ride]? {
        if let raw = try? (data as NSData).decompressed(using: .zlib) as Data,
           let list = try? JSONDecoder().decode([Ride].self, from: raw) {
            return list.sorted { $0.started > $1.started }
        }
        return (try? JSONDecoder().decode([Ride].self, from: data))?.sorted { $0.started > $1.started }
    }

    /// Two devices' lists into one. A ride is the same ride wherever it is
    /// read, so its id decides and nothing is ever counted twice; a device
    /// that has not pulled yet must not be able to shorten the list it has
    /// not seen. Deleting therefore needs both devices to be reached — the
    /// price of a merge, and cheaper than a ride that vanishes.
    nonisolated static func merge(_ mine: [Ride], _ theirs: [Ride]) -> [Ride] {
        var out = mine
        var known = Set(mine.map(\.id))
        for ride in theirs where !known.contains(ride.id) {
            known.insert(ride.id)
            out.append(ride)
        }
        out.sort { $0.started > $1.started }
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
        return RideTrack(id: track.id, points: kept, stops: track.stops, planned: track.planned)
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
            guard let rideData = try? JSONEncoder().encode(ride),
                  let trackData = try? JSONEncoder().encode(track),
                  let blob = try? JSONEncoder().encode(Interrupted(ride: rideData, track: trackData)) else { return }
            try? blob.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        }
    }

    func clearInterrupted() {
        try? FileManager.default.removeItem(at: interruptedFile)
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
    func recoverInterrupted() async {
        let url = interruptedFile
        let recovered = await Task.detached(priority: .userInitiated) { () -> (Ride, RideTrack)? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            try? FileManager.default.removeItem(at: url)
            guard let saved = try? JSONDecoder().decode(Interrupted.self, from: data),
                  let ride = try? JSONDecoder().decode(Ride.self, from: saved.ride),
                  let track = try? JSONDecoder().decode(RideTrack.self, from: saved.track) else { return nil }
            return (ride, track)
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
