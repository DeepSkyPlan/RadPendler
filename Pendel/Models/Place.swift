import CoreLocation

/// A named point the trip starts or ends at.
struct Place: Codable, Equatable, Hashable {
    var name: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// The building is new: Apple files No. 26 under 10000 and HAFAS only knows
    /// No. 25, but the postal address is 10557. The coordinates are the user's
    /// own pin of the entrance; the app always hands HAFAS coordinates, never the text.
    static let office = Place(name: "Musterstraße 1, 10557 Berlin",
                              latitude: 52.5363163, longitude: 13.3610246)
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
