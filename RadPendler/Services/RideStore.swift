import CloudKit
import Foundation
import Observation

/// Where the recorded rides live: a short summary per ride in one file, the
/// line of each ride in a file of its own, and a copy of both in the user's
/// own private iCloud so the next phone starts with the history on it.
///
/// The split is what keeps the list cheap. Three hundred summaries are
/// seventy kilobytes; three hundred tracks are twenty megabytes, and the list
/// never needs one of them.
///
/// Like `CloudStore`, the cloud half is optional: without an iCloud account
/// every call is a quiet no-op and the rides stay on the device.
@MainActor
@Observable
final class RideStore {
    static let shared = RideStore()

    /// Newest first — the order the list shows them in.
    private(set) var rides: [Ride] = []
    /// True while the first pull from iCloud is running.
    private(set) var syncing = false

    private let folder: URL
    private let cloud: RideCloud?
    private var tracks: [UUID: RideTrack] = [:]

    init(folder: URL? = nil, cloud: RideCloud? = RideCloud()) {
        self.folder = folder ?? Self.defaultFolder()
        self.cloud = cloud
        try? FileManager.default.createDirectory(at: self.folder.appending(path: "tracks"),
                                                 withIntermediateDirectories: true)
        load()
    }

    private static func defaultFolder() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return base.appending(path: "Rides")
    }

    private var summaryFile: URL { folder.appending(path: "summaries.json") }
    private var interruptedFile: URL { folder.appending(path: "current.json") }
    private func trackFile(_ id: UUID) -> URL {
        folder.appending(path: "tracks").appending(path: "\(id.uuidString).json")
    }

    // MARK: Local

    private func load() {
        guard let data = try? Data(contentsOf: summaryFile),
              let list = try? JSONDecoder().decode([Ride].self, from: data) else { return }
        rides = list.sorted { $0.started > $1.started }
    }

    private func writeSummaries() {
        guard let data = try? JSONEncoder().encode(rides) else { return }
        try? data.write(to: summaryFile, options: .atomic)
    }

    func add(_ ride: Ride, track: RideTrack) {
        rides.removeAll { $0.id == ride.id }
        rides.append(ride)
        rides.sort { $0.started > $1.started }
        tracks[ride.id] = track
        if let data = try? JSONEncoder().encode(track) {
            try? data.write(to: trackFile(ride.id), options: .atomic)
        }
        writeSummaries()
        push(ride, track)
    }

    func delete(_ ride: Ride) {
        rides.removeAll { $0.id == ride.id }
        tracks[ride.id] = nil
        try? FileManager.default.removeItem(at: trackFile(ride.id))
        writeSummaries()
        if let cloud { Task { await cloud.delete(ride.id) } }
    }

    /// The line of one ride — from memory, from disk, or from iCloud, in that
    /// order. nil means it was recorded on another device and that device's
    /// copy has not arrived (or there is no iCloud); the detail view says so
    /// instead of drawing an empty map.
    func track(for ride: Ride) async -> RideTrack? {
        if let t = tracks[ride.id] { return t }
        if let data = try? Data(contentsOf: trackFile(ride.id)),
           let t = try? JSONDecoder().decode(RideTrack.self, from: data) {
            tracks[ride.id] = t
            return t
        }
        guard let cloud, let t = await cloud.track(ride.id) else { return nil }
        tracks[ride.id] = t
        if let data = try? JSONEncoder().encode(t) {
            try? data.write(to: trackFile(ride.id), options: .atomic)
        }
        return t
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

    // MARK: Cloud

    private func push(_ ride: Ride, _ track: RideTrack) {
        guard let cloud else { return }
        Task { await cloud.push(ride, track) }
    }

    /// Everything the private database has, merged into what is here. A ride
    /// is the same ride on every device, so its id decides; nothing is ever
    /// duplicated and nothing local is removed by a cloud that has not caught up.
    func syncFromCloud() async {
        guard let cloud else { return }
        syncing = true
        defer { syncing = false }
        // What did not get out last time goes first: a ride nobody can see on
        // the other phone is the one failure worth retrying before reading.
        for id in await cloud.pendingIDs() {
            guard let ride = rides.first(where: { $0.id == id }), let track = await track(for: ride) else {
                await cloud.forget(id)
                continue
            }
            await cloud.push(ride, track)
        }
        guard let incoming = await cloud.fetchSummaries() else { return }
        var known = Set(rides.map(\.id))
        var added = false
        for ride in incoming where !known.contains(ride.id) {
            known.insert(ride.id)
            rides.append(ride)
            added = true
        }
        if added {
            rides.sort { $0.started > $1.started }
            writeSummaries()
        }
    }
}

/// The private-database half. An actor because it is all network and none of
/// it belongs on the main thread; every error is swallowed on purpose — a ride
/// that did not reach iCloud is still a ride, and it is tried again next time.
actor RideCloud {
    static let containerID = "iCloud.de.keese.radpendler"
    static let recordType = "Ride"
    private static let pendingKey = "ridesPendingPush"

    private let database: CKDatabase

    init(container: CKContainer = CKContainer(identifier: RideCloud.containerID)) {
        database = container.privateCloudDatabase
    }

    func push(_ ride: Ride, _ track: RideTrack) async {
        do {
            _ = try await database.save(Self.record(ride, track))
            unmarkPending(ride.id)
        } catch {
            markPending(ride.id)
        }
    }

    func delete(_ id: UUID) async {
        _ = try? await database.deleteRecord(withID: CKRecord.ID(recordName: id.uuidString))
        unmarkPending(id)
    }

    /// Summaries only: the line of every ride would be megabytes for a list
    /// that shows dates and averages. Paged, because a year of commuting is
    /// more rides than one answer carries.
    func fetchSummaries() async -> [Ride]? {
        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
        var out: [Ride] = []
        var cursor: CKQueryOperation.Cursor?
        var pages = 0
        repeat {
            do {
                let page: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)],
                           queryCursor: CKQueryOperation.Cursor?)
                if let cursor {
                    page = try await database.records(continuingMatchFrom: cursor,
                                                      desiredKeys: Self.summaryKeys, resultsLimit: 200)
                } else {
                    page = try await database.records(matching: query,
                                                      desiredKeys: Self.summaryKeys, resultsLimit: 200)
                }
                for (_, result) in page.matchResults {
                    if let record = try? result.get(), let ride = Self.ride(record) { out.append(ride) }
                }
                cursor = page.queryCursor
            } catch {
                // Nothing there yet reads exactly like a failure; either way
                // the local list stands and the next start tries again.
                return out.isEmpty ? nil : out
            }
            pages += 1
        } while cursor != nil && pages < 50
        return out
    }

    func track(_ id: UUID) async -> RideTrack? {
        guard let record = try? await database.record(for: CKRecord.ID(recordName: id.uuidString)),
              let data = record["track"] as? Data else { return nil }
        return Self.decodeTrack(data)
    }

    /// Rides whose push failed once. The store hands the pairs back in,
    /// because the actor keeps no copy of anything.
    func pendingIDs() -> [UUID] { pending() }

    func forget(_ id: UUID) { unmarkPending(id) }

    // MARK: Record ↔ ride

    private static let summaryKeys = ["started", "ended", "origin", "destination", "mode", "meters",
                                      "movingSeconds", "maxKmh", "signalStops", "otherStops",
                                      "signalWaitTotal", "plannedSeconds", "pointCount"]

    static func record(_ ride: Ride, _ track: RideTrack) -> CKRecord {
        let r = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: ride.id.uuidString))
        r["started"] = ride.started as NSDate
        r["ended"] = ride.ended as NSDate
        r["origin"] = ride.origin as NSString
        r["destination"] = ride.destination as NSString
        r["mode"] = ride.mode as NSString
        r["meters"] = ride.meters as NSNumber
        r["movingSeconds"] = ride.movingSeconds as NSNumber
        r["maxKmh"] = ride.maxKmh as NSNumber
        r["signalStops"] = ride.signalStops as NSNumber
        r["otherStops"] = ride.otherStops as NSNumber
        r["signalWaitTotal"] = ride.signalWaitTotal as NSNumber
        r["pointCount"] = ride.pointCount as NSNumber
        if let planned = ride.plannedSeconds { r["plannedSeconds"] = planned as NSNumber }
        if let data = encodeTrack(track) { r["track"] = data as NSData }
        return r
    }

    static func ride(_ r: CKRecord) -> Ride? {
        guard let id = UUID(uuidString: r.recordID.recordName),
              let started = r["started"] as? Date, let ended = r["ended"] as? Date else { return nil }
        return Ride(id: id, started: started, ended: ended,
                    origin: r["origin"] as? String ?? "", destination: r["destination"] as? String ?? "",
                    mode: r["mode"] as? String ?? TravelMode.bike.rawValue,
                    meters: r["meters"] as? Double ?? 0,
                    movingSeconds: r["movingSeconds"] as? Double ?? 0,
                    maxKmh: r["maxKmh"] as? Double ?? 0,
                    signalStops: r["signalStops"] as? Int ?? 0,
                    otherStops: r["otherStops"] as? Int ?? 0,
                    signalWaitTotal: r["signalWaitTotal"] as? Double ?? 0,
                    plannedSeconds: r["plannedSeconds"] as? Double,
                    pointCount: r["pointCount"] as? Int ?? 0)
    }

    /// The line goes in compressed. A twenty-minute commute is some eighty
    /// kilobytes of JSON and a fifth of that zipped, which keeps a ride inside
    /// what a single record field may hold however long the commute gets.
    static func encodeTrack(_ track: RideTrack) -> Data? {
        guard let json = try? JSONEncoder().encode(track) else { return nil }
        return (try? (json as NSData).compressed(using: .zlib)) as Data? ?? json
    }

    static func decodeTrack(_ data: Data) -> RideTrack? {
        if let raw = try? (data as NSData).decompressed(using: .zlib) as Data,
           let track = try? JSONDecoder().decode(RideTrack.self, from: raw) {
            return track
        }
        return try? JSONDecoder().decode(RideTrack.self, from: data)
    }

    // MARK: The retry list

    private func pending() -> [UUID] {
        (UserDefaults.standard.array(forKey: Self.pendingKey) as? [String] ?? []).compactMap(UUID.init)
    }

    private func markPending(_ id: UUID) {
        var list = UserDefaults.standard.array(forKey: Self.pendingKey) as? [String] ?? []
        guard !list.contains(id.uuidString) else { return }
        list.append(id.uuidString)
        UserDefaults.standard.set(list, forKey: Self.pendingKey)
    }

    private func unmarkPending(_ id: UUID) {
        let list = (UserDefaults.standard.array(forKey: Self.pendingKey) as? [String] ?? [])
            .filter { $0 != id.uuidString }
        UserDefaults.standard.set(list, forKey: Self.pendingKey)
    }
}
