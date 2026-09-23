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
            try? data.write(to: trackFile(ride.id), options: .atomic)
        }
        write()
    }

    func delete(_ ride: Ride) {
        rides.removeAll { $0.id == ride.id }
        tracks[ride.id] = nil
        try? FileManager.default.removeItem(at: trackFile(ride.id))
        write()
    }

    /// The line of one ride, from memory or from disk. nil means it was
    /// recorded on another device: the numbers travelled, the drawing did not,
    /// and the detail view says so instead of showing an empty map.
    func track(for ride: Ride) -> RideTrack? {
        if let t = tracks[ride.id] { return t }
        guard let data = try? Data(contentsOf: trackFile(ride.id)),
              let t = try? JSONDecoder().decode(RideTrack.self, from: data) else { return nil }
        tracks[ride.id] = t
        return t
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

    /// Written every half minute while recording, so a ride does not die with
    /// the process. `clearInterrupted` removes it the moment the ride ends
    /// properly.
    func saveInterrupted(_ state: (Ride, RideTrack)) {
        guard let ride = try? JSONEncoder().encode(state.0),
              let track = try? JSONEncoder().encode(state.1) else { return }
        try? JSONEncoder().encode(Interrupted(ride: ride, track: track))
            .write(to: interruptedFile, options: .atomic)
    }

    func clearInterrupted() {
        try? FileManager.default.removeItem(at: interruptedFile)
    }

    /// Called at launch: whatever was being recorded when the app went away is
    /// filed as the ride it was, up to its last known second.
    func recoverInterrupted() {
        guard let data = try? Data(contentsOf: interruptedFile),
              let saved = try? JSONDecoder().decode(Interrupted.self, from: data),
              let ride = try? JSONDecoder().decode(Ride.self, from: saved.ride),
              let track = try? JSONDecoder().decode(RideTrack.self, from: saved.track) else { return }
        clearInterrupted()
        guard ride.seconds >= 60, ride.meters >= 100, !rides.contains(where: { $0.id == ride.id }) else { return }
        add(ride, track: track)
    }

    private struct Interrupted: Codable {
        var ride: Data
        var track: Data
    }
}
