import XCTest
@testable import RadPendler

final class RideSoundsTests: XCTestCase {
    /// Ein gültiges WAV, so lang wie die Noten zusammen.
    func testTheToneIsAValidWave() {
        let data = RideSounds.wav([.init(hz: 880, seconds: 0.1), .init(hz: 0, seconds: 0.05)], rate: 22_050)
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(data.count, 44 + (2205 + 1102) * 2)
    }

    /// Links links, rechts rechts — im Stereobild und in der Tonhöhe.
    func testLeftAndRightSoundDifferent() {
        let (left, panL) = RideSounds.notes(.turnAhead(side: TurnGuide.Turn.left.side))
        let (right, panR) = RideSounds.notes(.turnAhead(side: TurnGuide.Turn.sharpRight.side))
        XCTAssertLessThan(panL, 0)
        XCTAssertGreaterThan(panR, 0)
        XCTAssertLessThan(left[0].hz, right[0].hz)
        XCTAssertEqual(TurnGuide.Turn.arrive.side, 0)
        XCTAssertEqual(RideSounds.notes(.turnNow(side: 1)).0.filter { $0.hz > 0 }.count, 2, "jetzt: doppelt")
    }
}
