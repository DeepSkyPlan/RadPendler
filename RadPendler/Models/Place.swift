import CoreLocation

/// A named point the trip starts or ends at.
struct Place: Codable, Equatable, Hashable {
    /// Full text, e.g. "Musterstraße 1, 10557 Berlin".
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
