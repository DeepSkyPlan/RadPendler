import CoreLocation

/// A named point the trip starts or ends at.
struct Place: Codable, Equatable, Hashable {
    /// Full text, e.g. "Musterstraße 1, 10115 Berlin".
    var name: String
    var latitude: Double
    var longitude: Double
    /// Kept apart from `name` so the rows can show the street big and the
    /// postal code small — and so two Hauptstraßen stay apart.
    var postalCode: String? = nil
    var locality: String? = nil

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    // No addresses are built in: the app ships empty and keeps whatever the
    // user picks, so no private address is in the binary that goes to the store.

    /// First line of the name, for tight rows.
    var shortName: String {
        name.split(separator: ",").first.map(String.init) ?? name
    }

    /// "10557 Berlin" — what belongs next to the street. Falls back to whatever
    /// stood after the first comma, for addresses saved before 0.9.
    var areaLine: String? {
        let known = [postalCode, locality].compactMap { $0 }.joined(separator: " ")
        if !known.isEmpty { return known }
        let rest = name.split(separator: ",").dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }
        // "Deutschland" alone says nothing; drop a lone country.
        let useful = rest.filter { $0 != "Deutschland" && $0 != "Germany" }
        return useful.isEmpty ? nil : useful.joined(separator: ", ")
    }

    /// Street and postal code in one line, for places that get only one.
    var withArea: String {
        areaLine.map { "\(shortName), \($0)" } ?? shortName
    }

    /// Same address picked twice must land on the same entry: ~10 m of slack.
    var key: String {
        String(format: "%.4f,%.4f", latitude, longitude)
    }
}

/// The two addresses that mean something by themselves — the commute runs
/// between them, and they get a mark wherever an address is shown.
enum PlaceRole: String, CaseIterable {
    case home, work

    var title: String { self == .home ? L("Zuhause") : L("Arbeit") }
    var symbol: String { self == .home ? "house.fill" : "briefcase.fill" }
}

/// One address that has been used before, with how often.
struct PlaceUse: Codable, Equatable, Identifiable {
    var place: Place
    var count: Int
    var lastUsed: Date

    var id: String { place.key }
}

extension Array where Element == PlaceUse {
    /// Most used first; where two are level, the more recent one wins.
    var ranked: [PlaceUse] {
        sorted { ($0.count, $0.lastUsed) > ($1.count, $1.lastUsed) }
    }

    /// Everything whose text contains the query, case and umlaut insensitive.
    func matching(_ query: String) -> [PlaceUse] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return ranked }
        return ranked.filter {
            $0.place.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// Two devices' lists into one: per address the higher count and the later
    /// use. Monotone on purpose — a device that has only just pulled from iCloud
    /// must not be able to shrink the list it did not see yet.
    func merging(_ other: [PlaceUse], limit: Int = 40) -> [PlaceUse] {
        var byKey: [String: PlaceUse] = [:]
        for use in self + other {
            guard let there = byKey[use.id] else { byKey[use.id] = use; continue }
            byKey[use.id] = PlaceUse(place: use.lastUsed >= there.lastUsed ? use.place : there.place,
                                     count: Swift.max(use.count, there.count),
                                     lastUsed: Swift.max(use.lastUsed, there.lastUsed))
        }
        return Array(Array(byKey.values).ranked.prefix(limit))
    }

    /// Counts a use, keeping the newest name and coordinates for the entry.
    func recording(_ place: Place, now: Date = .now, limit: Int = 40) -> [PlaceUse] {
        var out = self
        if let i = out.firstIndex(where: { $0.place.key == place.key }) {
            out[i] = PlaceUse(place: place, count: out[i].count + 1, lastUsed: now)
        } else {
            out.append(PlaceUse(place: place, count: 1, lastUsed: now))
        }
        // Over the limit the least used go first, the oldest among them.
        guard out.count > limit else { return out }
        return Array(out.ranked.prefix(limit))
    }
}

extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}

/// One transit line and what the user has decided about taking the bike on it.
/// The names come out of the routes the app has actually found — nothing is
/// invented, and nothing is assumed.
struct BikeLine: Codable, Equatable, Identifiable, Hashable {
    /// "S7", "RE1", "M11" — as the timetable names it.
    var name: String
    /// nil until the user has said; that is what the warning is about.
    var allowed: Bool?
    /// When this line was last part of a found route, for sorting.
    var lastSeen: Date

    var id: String { name }

    var status: BikeCarriage {
        guard let allowed else { return .unknown }
        return allowed ? .yes : .no
    }
}

extension Array where Element == BikeLine {
    /// Decided lines first (allowed before refused), then the open ones, each
    /// group alphabetically — the open ones are the list's actual job.
    var sortedForList: [BikeLine] {
        sorted {
            if ($0.allowed == nil) != ($1.allowed == nil) { return $1.allowed == nil }
            if $0.allowed != $1.allowed { return $0.allowed == true }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Notes the lines a plan used. A line that is already decided keeps its
    /// decision; a new one arrives open. `known` pre-fills what the timetable
    /// itself vouched for, so the user only has to judge the rest.
    func noting(_ seen: [(name: String, known: BikeCarriage)], now: Date = .now) -> [BikeLine] {
        var out = self
        for line in seen where !line.name.isEmpty {
            if let i = out.firstIndex(where: { $0.name == line.name }) {
                out[i].lastSeen = now
                if out[i].allowed == nil, line.known == .yes { out[i].allowed = true }
            } else {
                out.append(BikeLine(name: line.name,
                                    allowed: line.known == .yes ? true : nil,
                                    lastSeen: now))
            }
        }
        return out
    }

    /// name → decision, for handing into a planning run.
    var status: [String: Bool] {
        reduce(into: [:]) { out, line in
            if let allowed = line.allowed { out[line.name] = allowed }
        }
    }
}
