import CoreLocation

/// Where the timetable comes from: VBB inside Berlin and Brandenburg,
/// Transitous everywhere else. Bis 1.9.1 ließ sich das in den Einstellungen
/// festnageln; gebraucht hat das niemand, und falsch gewählt fand die App
/// außerhalb des VBB-Gebiets gar nichts.
enum TimetableSource: String {
    /// The VBB's own HAFAS, through the official VBB-API: the best real-time
    /// data for the region, and the only one that states bike carriage per train.
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

    /// The source that answers for this pair of places. Without an access id
    /// for the VBB-API (a build from the public repository) there is no VBB
    /// to ask, and Transitous answers everywhere.
    static func resolved(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
                         vbbAvailable: Bool = VbbAccess.id != nil) -> TimetableSource {
        vbbAvailable && covers(from) && covers(to) ? .vbb : .transitous
    }
}
