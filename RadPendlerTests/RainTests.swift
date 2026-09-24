import MapKit
import UniformTypeIdentifiers
import ImageIO
import CoreGraphics
import CoreLocation
import XCTest
@testable import RadPendler

final class RainTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_003_700)   // 2026-09-21 15:15 UTC

    func testSamplesAreStampedWithPassingTime() {
        let a = CLLocationCoordinate2D(latitude: 52.50, longitude: 13.30)
        let b = CLLocationCoordinate2D(latitude: 52.50 - 6000 / 111_320, longitude: 13.30)   // 6 km south
        let s = RainSampler.samples(along: [a, b], departure: t0, arrival: t0.addingTimeInterval(1200), spacing: 1500)
        XCTAssertEqual(s.count, 5)
        XCTAssertEqual(s.first?.time, t0)
        XCTAssertEqual(s.last!.time.timeIntervalSince(t0), 1200, accuracy: 1)
        XCTAssertEqual(s[2].time.timeIntervalSince(t0), 600, accuracy: 1)
        XCTAssertEqual(s[2].coordinate.distance(to: a), 3000, accuracy: 20)
    }

    func testPositionOnLeg() {
        let a = CLLocationCoordinate2D(latitude: 52.50, longitude: 13.30)
        let b = CLLocationCoordinate2D(latitude: 52.40, longitude: 13.30)
        let mid = RainSampler.position(on: [a, b], departure: t0, arrival: t0.addingTimeInterval(600),
                                       at: t0.addingTimeInterval(300))
        XCTAssertEqual(mid!.latitude, 52.45, accuracy: 1e-3)
        XCTAssertNil(RainSampler.position(on: [a, b], departure: t0, arrival: t0.addingTimeInterval(600),
                                          at: t0.addingTimeInterval(601)))
    }

    func testLevels() {
        XCTAssertEqual(RainLevel.of(millimetres: 0, probability: 10), .dry)
        XCTAssertEqual(RainLevel.of(millimetres: 0, probability: 50), .possible)
        XCTAssertEqual(RainLevel.of(millimetres: 0.1, probability: 80), .light)
        XCTAssertEqual(RainLevel.of(millimetres: 0.8, probability: 80), .rain)
        XCTAssertEqual(RainLevel.of(millimetres: 3, probability: 100), .heavy)
    }

    func testOpenMeteoMultiPointParseAndSlotLookup() throws {
        let json = """
        [{"latitude":52.54,"longitude":13.36,"minutely_15":{"time":["2026-09-21T15:15","2026-09-21T15:30","2026-09-21T15:45"],
          "precipitation":[0.0,0.4,1.1],"precipitation_probability":[5,60,90]}},
         {"latitude":52.40,"longitude":13.24,"minutely_15":{"time":["2026-09-21T15:15","2026-09-21T15:30","2026-09-21T15:45"],
          "precipitation":[0.0,0.0,null],"precipitation_probability":[0,0,null]}}]
        """
        let series = try RainService.parse(Data(json.utf8))
        XCTAssertEqual(series.count, 2)
        // 15:20 UTC lies in the slot that ends 15:30.
        let slot = series[0].slot(containing: t0.addingTimeInterval(300))
        XCTAssertEqual(slot?.mm, 0.4)
        XCTAssertEqual(slot?.probability, 60)
        // A `null` is "no forecast for this slot", not "no rain".
        let unknown = series[1].slot(containing: t0.addingTimeInterval(1500))
        XCTAssertNotNil(unknown, "the timestamp exists")
        XCTAssertNil(unknown?.mm, "and its value is unknown, not zero")
        XCTAssertEqual(series[1].slot(containing: t0.addingTimeInterval(300))?.mm, 0, "a real 0.0 stays 0.0")
    }

    func testARideTheForecastDoesNotReachIsUnknownNotDry() {
        let point = RainSample(coordinate: CLLocationCoordinate2D(latitude: 52.5, longitude: 13.4), time: t0)
        let nothing = RainAssessment(readings: [RainReading(sample: point, millimetres: nil, probability: nil)])
        XCTAssertFalse(nothing.hasData)
        XCTAssertEqual(nothing.summary, "keine Regendaten",
                       "the app must not report dry weather it never measured")
        XCTAssertEqual(nothing.level, .dry, "planning still has to pick something")
        XCTAssertEqual(nothing.maxMillimetres, 0)

        // One measured point among unmeasured ones is enough to judge.
        let some = RainAssessment(readings: [
            RainReading(sample: point, millimetres: nil, probability: nil),
            RainReading(sample: point, millimetres: 0.8, probability: 90),
        ])
        XCTAssertTrue(some.hasData)
        XCTAssertEqual(some.level, .rain)
        XCTAssertEqual(some.maxProbability, 90)
    }

    func testAShorterValueArrayThanTimestampsDoesNotCrash() {
        let json = """
        {"minutely_15":{"time":["2026-09-21T15:15","2026-09-21T15:30"],"precipitation":[0.2]}}
        """
        let series = try! RainService.parse(Data(json.utf8))
        // Second slot has a timestamp but no value — must read as unknown.
        XCTAssertNil(series[0].slot(containing: t0.addingTimeInterval(1200))?.mm)
        XCTAssertEqual(series[0].slot(containing: t0.addingTimeInterval(-1))?.mm, 0.2)
    }

    func testRadarFramesCoverPastAndNowcast() {
        let frames = RadarTileOverlay.frameTimes(around: t0)
        // On the 10-minute grid, from within the last half hour to ~2 h ahead.
        XCTAssertTrue(frames.allSatisfy { Int($0.timeIntervalSince1970) % 600 == 0 })
        XCTAssertEqual(frames.first, t0.addingTimeInterval(-1500))
        XCTAssertEqual(frames.last, t0.addingTimeInterval(6300))
        let url = RadarTileOverlay(time: t0).url(forTilePath: .init(x: 1100, y: 671, z: 11, contentScaleFactor: 2))
        XCTAssertTrue(url.absoluteString.contains("time=2026-09-21T15:15:00.000Z"), url.absoluteString)
        XCTAssertTrue(url.absoluteString.contains("crs=EPSG:3857"))
    }
}

/// The radar's own wording: which minute is on the map, in words.
final class RadarLabelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testRelativeWording() {
        XCTAssertEqual(RadarControls.relative(now, now: now), "jetzt")
        XCTAssertEqual(RadarControls.relative(now.addingTimeInterval(120), now: now), "jetzt")
        XCTAssertEqual(RadarControls.relative(now.addingTimeInterval(-600), now: now), "vor 10 min")
        XCTAssertEqual(RadarControls.relative(now.addingTimeInterval(1500), now: now), "in 25 min")
        XCTAssertEqual(RadarControls.relative(now.addingTimeInterval(3600), now: now), "in 1 h")
        XCTAssertEqual(RadarControls.relative(now.addingTimeInterval(5400), now: now), "in 1:30 h")
    }

    func testNearestFramePicksTheClosestMinute() {
        let frames = (0..<5).map { now.addingTimeInterval(Double($0) * 300 - 600) }
        XCTAssertEqual(RadarControls.nearest(now, in: frames), 2)
        XCTAssertEqual(RadarControls.nearest(now.addingTimeInterval(-590), in: frames), 0)
        XCTAssertEqual(RadarControls.nearest(now.addingTimeInterval(9999), in: frames), 4)
        XCTAssertEqual(RadarControls.nearest(now, in: []), 0)
    }

    func testOnlyThreeRadarFramesHangOnTheMapAtOnce() {
        let frames: [Date] = (0..<22).map { now.addingTimeInterval(Double($0) * 600) }
        // In the middle: the shown minute and one either side.
        let middle = RouteMapView.Coordinator.window(around: frames[10], in: frames)
        XCTAssertEqual(middle, Set<Date>([frames[9], frames[10], frames[11]]))
        // At the ends it stays inside the list.
        XCTAssertEqual(RouteMapView.Coordinator.window(around: frames[0], in: frames),
                       Set<Date>([frames[0], frames[1]]))
        XCTAssertEqual(RouteMapView.Coordinator.window(around: frames[21], in: frames),
                       Set<Date>([frames[20], frames[21]]))
        // A minute that is not in the list keeps only itself.
        XCTAssertEqual(RouteMapView.Coordinator.window(around: now.addingTimeInterval(5), in: frames),
                       Set<Date>([now.addingTimeInterval(5)]))
    }

    // MARK: Regenradar — die Klötzchen

    /// Das Komposit hat 1-km-Zellen. Auf der Zoomstufe, auf der man eine
    /// Pendelstrecke ansieht, sind das 26 Pixel je Zelle — darum sah die Karte
    /// aus wie ein Schachbrett.
    func testTheBlurFollowsTheCellSize() {
        XCTAssertEqual(RadarTileOverlay.cellPixels(z: 12), 26.2, accuracy: 0.3)
        XCTAssertEqual(RadarTileOverlay.blurRadius(z: 12), 8.7, accuracy: 0.3)
        XCTAssertEqual(RadarTileOverlay.cellPixels(z: 8), 1.6, accuracy: 0.2)
        XCTAssertEqual(RadarTileOverlay.blurRadius(z: 8), 0,
                       "wo eine Zelle kleiner als ein Pixel ist, gibt es nichts zu glätten")
        XCTAssertLessThanOrEqual(RadarTileOverlay.blurRadius(z: 12), 12, "und nie unbegrenzt")
    }

    /// Der Rand holt mehr Fläche bei **gleichem** Maßstab — sonst säße die
    /// geglättete Kachel versetzt auf der Karte. Geprüft an den Metern je Pixel
    /// und daran, dass der größere Ausschnitt den kleineren mittig enthält.
    func testTheMarginKeepsTheScaleAndStaysCentred() {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        func bbox(_ margin: Int) -> [Double] {
            let u = RadarTileOverlay.url(z: 12, x: 2200, y: 1350, time: t, margin: margin)
            let q = URLComponents(url: u, resolvingAgainstBaseURL: false)!.queryItems!
            return q.first { $0.name == "bbox" }!.value!.split(separator: ",").map { Double($0)! }
        }
        func pixels(_ margin: Int) -> Double {
            let u = RadarTileOverlay.url(z: 12, x: 2200, y: 1350, time: t, margin: margin)
            let q = URLComponents(url: u, resolvingAgainstBaseURL: false)!.queryItems!
            return Double(q.first { $0.name == "width" }!.value!)!
        }
        let plain = bbox(0), wide = bbox(RadarTileOverlay.margin)
        XCTAssertEqual(pixels(0), 256)
        XCTAssertEqual(pixels(RadarTileOverlay.margin), 384)
        let mppPlain = (plain[2] - plain[0]) / pixels(0)
        let mppWide = (wide[2] - wide[0]) / pixels(RadarTileOverlay.margin)
        XCTAssertEqual(mppPlain, mppWide, accuracy: 0.001, "gleiche Meter je Pixel, nur mehr davon")
        let over = mppPlain * Double(RadarTileOverlay.margin)
        XCTAssertEqual(wide[0], plain[0] - over, accuracy: 0.01)
        XCTAssertEqual(wide[3], plain[3] + over, accuracy: 0.01)
    }

    /// Geglättet wird auf den Rand, zurück kommt die Kachel ohne ihn — und die
    /// harten Kanten sind weg.
    func testSmoothingCropsTheMarginAndSoftensEdges() throws {
        let side = 256 + 2 * RadarTileOverlay.margin
        // Schachbrett mit 26-Pixel-Feldern, so grob wie das echte Komposit.
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for row in 0..<(side / 26 + 1) {
            for col in 0..<(side / 26 + 1) {
                ctx.setFillColor(gray: (row + col) % 2 == 0 ? 0 : 1, alpha: 1)
                ctx.fill(CGRect(x: col * 26, y: row * 26, width: 26, height: 26))
            }
        }
        let image = ctx.makeImage()!
        let buffer = CFDataCreateMutable(nil, 0)!
        let dest = CGImageDestinationCreateWithData(buffer, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))

        let out = try XCTUnwrap(RadarTileOverlay.smoothed(buffer as Data, radius: 8.7,
                                                          margin: RadarTileOverlay.margin))
        let src = try XCTUnwrap(CGImageSourceCreateWithData(out as CFData, nil))
        let got = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        XCTAssertEqual(got.width, 256, "der Rand ist wieder ab")
        XCTAssertEqual(got.height, 256)

        // Ohne Glätten bleibt die Kachel hart — dann ist der Unterschied
        // zwischen Nachbarpixeln an den Feldgrenzen voll da.
        let flat = try XCTUnwrap(RadarTileOverlay.smoothed(buffer as Data, radius: 0,
                                                           margin: RadarTileOverlay.margin))
        XCTAssertNotEqual(flat, out, "mit Radius 0 kommt etwas anderes heraus als mit 8,7")
    }
}
