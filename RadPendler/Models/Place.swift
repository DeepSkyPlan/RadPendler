import CoreLocation

/// A named point the trip starts or ends at.
struct Place: Codable, Equatable, Hashable {
    var name: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    // No addresses are built in: the app ships empty and keeps whatever the
    // user picks, so no private address is in the binary that goes to the store.

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
