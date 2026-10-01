import CoreLocation

/// Where the timetable comes from: VBB inside Berlin and Brandenburg,
/// Transitous everywhere else. Bis 1.9.1 ließ sich das in den Einstellungen
/// festnageln; gebraucht hat das niemand, und falsch gewählt fand die App
/// außerhalb des VBB-Gebiets gar nichts.
enum TimetableSource: String {
    /// The VBB's own HAFAS: the best real-time data for the region, and the
    /// only one that states bike carriage per train.
    case vbb
    /// Transitous (MOTIS) on the nationwide DELFI dataset and beyond.
    case transitous

    /// Berlin and Brandenburg, generously drawn. Inside it the VBB knows more
    /// than a nationwide dataset does — outside it, it knows nothing.
    static let vbbArea = (south: 51.35, west: 11.26, north: 53.56, east: 14.77)

    static func covers(_ c: CLLocationCoordinate2D) -> Bool {
        c.latitude >= vbbArea.south && c.latitude <= vbbArea.north
            && c.longitude >= vbbArea.west && c.longitude <= vbbArea.east
    }

    /// The source that answers for this pair of places.
    static func resolved(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> TimetableSource {
        covers(from) && covers(to) ? .vbb : .transitous
    }
}
