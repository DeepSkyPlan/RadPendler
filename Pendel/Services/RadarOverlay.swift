import MapKit

/// One frame of the DWD precipitation radar (analysis for the past, RV nowcast
/// up to +2 h), served by the DWD GeoServer as WMS in Web Mercator.
final class RadarTileOverlay: MKTileOverlay {
    let time: Date

    /// Radar frames exist every 5 minutes; the last analysis is typically
    /// 5–10 minutes old and the nowcast reaches two hours beyond it.
    static func frameTimes(around now: Date = .now, step: TimeInterval = 600,
                           past: TimeInterval = 1800, future: TimeInterval = 6600) -> [Date] {
        let base = (now.timeIntervalSince1970 / 300).rounded(.down) * 300
        let first = ((base - past) / step).rounded(.up) * step
        return stride(from: first, through: base + future, by: step).map { Date(timeIntervalSince1970: $0) }
    }

    /// Frames covering a trip: from shortly before leaving to shortly after
    /// arriving, clipped to what the radar has (last half hour plus the 2 h
    /// nowcast). Pressing play then walks the ride and the rain together.
    static func frameTimes(forTripFrom leave: Date, to arrival: Date, now: Date = .now,
                           step: TimeInterval = 300) -> [Date] {
        let available = frameTimes(around: now, step: step)
        guard let first = available.first, let last = available.last else { return [] }
        let from = max(leave.addingTimeInterval(-600), first)
        let to = min(arrival.addingTimeInterval(600), last)
        guard from < to else { return available }
        let start = (from.timeIntervalSince1970 / step).rounded(.down) * step
        let end = (to.timeIntervalSince1970 / step).rounded(.up) * step
        return stride(from: start, through: end, by: step).map { Date(timeIntervalSince1970: $0) }
    }

    init(time: Date) {
        self.time = time
        super.init(urlTemplate: nil)
        canReplaceMapContent = false
        tileSize = CGSize(width: 256, height: 256)
        minimumZ = 5
        maximumZ = 12   // the composite has 1 km cells; finer tiles are just upscaled
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        let world = 20037508.342789244
        let n = Double(1 << path.z)
        let size = 2 * world / n
        let minX = -world + Double(path.x) * size
        let maxY = world - Double(path.y) * size
        let bbox = String(format: "%.3f,%.3f,%.3f,%.3f", minX, maxY - size, minX + size, maxY)

        var c = URLComponents(string: "https://maps.dwd.de/geoserver/dwd/wms")!
        c.queryItems = [
            .init(name: "service", value: "WMS"), .init(name: "version", value: "1.3.0"),
            .init(name: "request", value: "GetMap"), .init(name: "layers", value: "dwd:Niederschlagsradar"),
            .init(name: "styles", value: ""), .init(name: "format", value: "image/png"),
            .init(name: "transparent", value: "true"), .init(name: "crs", value: "EPSG:3857"),
            .init(name: "width", value: "256"), .init(name: "height", value: "256"),
            .init(name: "bbox", value: bbox),
            .init(name: "time", value: Self.isoTime(time)),
        ]
        return c.url!
    }

    private static func isoTime(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: d).replacingOccurrences(of: "Z", with: ".000Z")
    }
}
