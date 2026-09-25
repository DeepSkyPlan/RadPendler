import CoreImage
import ImageIO
import MapKit
import Observation
import UniformTypeIdentifiers

/// How many radar tiles are in flight right now, so the map can say that the
/// rain is still arriving instead of quietly showing an empty sky.
@MainActor @Observable final class RadarLoads {
    static let shared = RadarLoads()
    private(set) var pending = 0
    var isLoading: Bool { pending > 0 }

    func began() { pending += 1 }
    func ended() { pending = max(0, pending - 1) }
}

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

    static let world = 20037508.342789244

    /// Kantenlänge einer Kachel in Metern.
    static func tileSize(z: Int) -> Double { 2 * world / Double(1 << z) }

    /// Wie viele Pixel eine Zelle des Komposits in einer 256er-Kachel belegt.
    /// Das Komposit hat 1-km-Zellen; auf Stufe 12 sind das 26 Pixel — daher
    /// die Klötzchen.
    static func cellPixels(z: Int) -> Double { 1000 / (tileSize(z: z) / 256) }

    /// Wie stark geglättet wird: ein Drittel der Zellenbreite. Darunter bleiben
    /// die Kanten hart, darüber verschwimmt die Struktur — und wo eine Zelle
    /// ohnehin kleiner als ein Pixel ist (kleine Zoomstufen), wird gar nicht
    /// geglättet, denn dort gibt es nichts zu glätten.
    static func blurRadius(z: Int) -> Double {
        let r = cellPixels(z: z) / 3
        return r < 1.5 ? 0 : Swift.min(r, 12)
    }

    /// Wie viel über die Kachel hinaus geholt wird, damit der Weichzeichner
    /// Nachbarschaft hat. Ohne diesen Rand rechnet jede Kachel nur mit sich
    /// selbst, und an den Kachelgrenzen stehen sichtbare Nähte.
    ///
    /// Zwei Radien reichen dafür, und der Radius ist gedeckelt auf 12
    /// (`blurRadius`). 64 waren 384 × 384 statt 256 × 256 — zweieinviertelfache
    /// Fläche je Kachel, für einen Rand, den kein Weichzeichner erreicht.
    static let margin = 24

    /// Die Anfrage an den DWD. `margin > 0` holt einen größeren Ausschnitt bei
    /// gleichem Maßstab — dieselben Meter je Pixel, nur mehr davon.
    static func url(z: Int, x: Int, y: Int, time: Date, margin: Int = 0) -> URL {
        let size = tileSize(z: z)
        let over = size * Double(margin) / 256      // Rand in Metern
        let minX = -world + Double(x) * size - over
        let maxY = world - Double(y) * size + over
        let side = size + 2 * over
        let bbox = String(format: "%.3f,%.3f,%.3f,%.3f", minX, maxY - side, minX + side, maxY)
        let px = String(256 + 2 * margin)

        var c = URLComponents(string: "https://maps.dwd.de/geoserver/dwd/wms")!
        c.queryItems = [
            .init(name: "service", value: "WMS"), .init(name: "version", value: "1.3.0"),
            .init(name: "request", value: "GetMap"), .init(name: "layers", value: "dwd:Niederschlagsradar"),
            .init(name: "styles", value: ""), .init(name: "format", value: "image/png"),
            .init(name: "transparent", value: "true"), .init(name: "crs", value: "EPSG:3857"),
            .init(name: "width", value: px), .init(name: "height", value: px),
            .init(name: "bbox", value: bbox),
            .init(name: "time", value: isoTime(time)),
        ]
        return c.url!
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        Self.url(z: path.z, x: path.x, y: path.y, time: time)
    }

    /// Holt die Kachel mit Rand, glättet sie und schneidet den Rand wieder ab.
    ///
    /// Das Komposit hat 1-km-Zellen. Auf der Zoomstufe, auf der man eine
    /// Pendelstrecke ansieht, sind das 26 Pixel je Zelle — und weil der Dienst
    /// sie als Rechtecke ausmalt, liegt über der Karte ein Schachbrett. Der
    /// Weichzeichner erfindet nichts, er hört nur auf, die Zellgrenzen als
    /// Kanten zu zeichnen; eine Messung mit 1 km Auflösung sieht danach aus
    /// wie das, was sie ist — ein Feld, kein Raster.
    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        Task { @MainActor in RadarLoads.shared.began() }
        let url = Self.url(z: path.z, x: path.x, y: path.y, time: time, margin: Self.margin)
        let radius = Self.blurRadius(z: path.z)
        URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 20)) { data, _, error in
            Task { @MainActor in RadarLoads.shared.ended() }
            guard let data else { return result(nil, error) }
            // Misslingt das Glätten, ist eine klötzchenhafte Kachel immer noch
            // besser als keine.
            result(Self.smoothed(data, radius: radius, margin: Self.margin) ?? data, nil)
        }.resume()
    }

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Weichzeichnen und den Rand abschneiden. nil, wenn irgendetwas daran
    /// scheitert — der Aufrufer nimmt dann die Kachel, wie sie kam.
    static func smoothed(_ data: Data, radius: Double, margin: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let full = CIImage(cgImage: cg)
        let inner = full.extent.insetBy(dx: CGFloat(margin), dy: CGFloat(margin))
        guard inner.width > 0, inner.height > 0 else { return nil }
        let image: CIImage
        if radius > 0, let blur = CIFilter(name: "CIGaussianBlur",
                                           parameters: [kCIInputImageKey: full.clampedToExtent(),
                                                        kCIInputRadiusKey: radius])?.outputImage {
            image = blur
        } else {
            image = full
        }
        guard let out = ciContext.createCGImage(image, from: inner),
              let buffer = CFDataCreateMutable(nil, 0),
              let dest = CGImageDestinationCreateWithData(buffer, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, out, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return buffer as Data
    }

    static func isoTime(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: d).replacingOccurrences(of: "Z", with: ".000Z")
    }
}
