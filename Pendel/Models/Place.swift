import CoreLocation

/// A named point the trip starts or ends at.
struct Place: Codable, Equatable, Hashable {
    var name: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Coordinates from Apple's geocoder. HAFAS knows no "Musterstraße 1" in
    /// 10000 — its nearest match is house 25 in 10557 — so the app always hands
    /// HAFAS coordinates, never the address text.
    static let office = Place(name: "Musterstraße 1, 10000 Berlin",
                              latitude: 52.5367319, longitude: 13.3605566)
    static let home = Place(name: "Beispielweg 2, 14000 Musterort",
                            latitude: 52.409412, longitude: 13.2306482)

    /// First line of the name, for tight rows.
    var shortName: String {
        name.split(separator: ",").first.map(String.init) ?? name
    }
}

extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}
