import CoreLocation
import XCTest
@testable import Pendel

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
        XCTAssertEqual(series[1].slot(containing: t0.addingTimeInterval(1500))?.mm, 0)
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
}
