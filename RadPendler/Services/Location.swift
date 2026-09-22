import CoreLocation
import Observation

/// Where the rider is, once, when they ask. The app never follows anyone: it
/// takes a single fix when "Mein Standort" is tapped, turns it into an address
/// and forgets the manager again. No background use, no significant-change
/// monitoring, nothing that keeps running.
@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    enum Permission { case unknown, allowed, denied }

    private let manager = CLLocationManager()
    private var waiting: [CheckedContinuation<CLLocation, Error>] = []
    private var askedThisTime = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    var permission: Permission {
        switch manager.authorizationStatus {
        case .notDetermined: .unknown
        case .denied, .restricted: .denied
        default: .allowed
        }
    }

    /// One fix. Asks for permission the first time; throws if it is refused, so
    /// the caller can say why nothing happened instead of spinning.
    func current() async throws -> CLLocation {
        if permission == .unknown {
            askedThisTime = true
            manager.requestWhenInUseAuthorization()
        }
        guard permission != .denied else { throw LocationError.refused }
        return try await withCheckedThrowingContinuation { continuation in
            waiting.append(continuation)
            manager.requestLocation()
        }
    }

    /// The address behind a fix. Without it the place would be a pair of
    /// numbers, and the history would fill up with points nobody recognises.
    func place(for location: CLLocation) async -> Place {
        let c = location.coordinate
        guard let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first else {
            return Place(name: "Mein Standort", latitude: c.latitude, longitude: c.longitude)
        }
        return Self.place(from: mark, at: c)
    }

    /// Placemark → Place, kept apart from the geocoder so it can be tested.
    nonisolated static func place(from mark: CLPlacemark, at c: CLLocationCoordinate2D) -> Place {
        let street = [mark.thoroughfare, mark.subThoroughfare].compactMap { $0 }.joined(separator: " ")
        let title = street.isEmpty ? (mark.name ?? mark.locality ?? "Mein Standort") : street
        return Place(name: [title, [mark.postalCode, mark.locality].compactMap { $0 }.joined(separator: " ")]
                        .filter { !$0.isEmpty }.joined(separator: ", "),
                     latitude: c.latitude, longitude: c.longitude,
                     postalCode: mark.postalCode, locality: mark.locality)
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last else { return }
        Task { @MainActor in resume(.success(fix)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in resume(.failure(error)) }
    }

    /// The answer to the permission sheet arrives here, not at the call site.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard askedThisTime else { return }
            switch permission {
            case .denied: resume(.failure(LocationError.refused))
            case .allowed: manager.requestLocation()
            case .unknown: break
            }
        }
    }

    private func resume(_ result: Result<CLLocation, Error>) {
        askedThisTime = false
        let pending = waiting
        waiting = []
        for continuation in pending { continuation.resume(with: result) }
    }

    enum LocationError: LocalizedError {
        case refused
        var errorDescription: String? {
            "Ortung ist für RadPendler nicht erlaubt — in den iOS-Einstellungen unter Datenschutz freigeben."
        }
    }
}
