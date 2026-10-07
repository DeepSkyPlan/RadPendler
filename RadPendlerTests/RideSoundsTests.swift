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

    /// Anhalten fällt, Weiterfahren steigt — und keins von beiden klingt wie
    /// Start oder Ende.
    func testPauseAndResumeAreTheirOwnSounds() {
        let tones = { (cue: RideSounds.Cue) in RideSounds.notes(cue).0.filter { $0.hz > 0 }.map(\.hz) }
        let (pause, resume) = (tones(.pause), tones(.resume))
        XCTAssertGreaterThan(pause.first!, pause.last!)
        XCTAssertLessThan(resume.first!, resume.last!)
        XCTAssertNotEqual(pause, tones(.stop))
        XCTAssertNotEqual(resume, tones(.start))
    }

    // MARK: Was die App mit dem Ton der anderen macht

    /// Der Hintergrundmodus `audio` ist für ein paar Hinweistöne beantragt,
    /// nicht fürs Abspielen. Dazu gehört: Musik und Podcast laufen weiter und
    /// werden nur kurz leiser. Ohne `mixWithOthers` hielte der erste Ton sie an.
    func testTheCuesMixWithWhateverIsPlaying() {
        XCTAssertEqual(RideSounds.category, .playback, "hörbar trotz Stummschalter, am Lenker der Normalfall")
        XCTAssertTrue(RideSounds.options.contains(.mixWithOthers))
        XCTAssertTrue(RideSounds.options.contains(.duckOthers))
    }

    /// Jeder Ton ist ein Hinweis, kein Stück: unter einer Sekunde. Danach gibt
    /// die App den Ton wieder frei (`setActive(false)`).
    func testEveryCueIsShorterThanASecond() {
        let cues: [RideSounds.Cue] = [.start, .stop, .pause, .resume,
                                      .turnAhead(side: -1), .turnAhead(side: 0), .turnAhead(side: 1),
                                      .turnNow(side: -1), .turnNow(side: 0), .turnNow(side: 1)]
        for cue in cues {
            let (notes, pan) = RideSounds.notes(cue)
            let seconds = notes.map(\.seconds).reduce(0, +)
            XCTAssertGreaterThan(seconds, 0.05, "\(cue)")
            XCTAssertLessThan(seconds, 1, "\(cue)")
            XCTAssertLessThanOrEqual(abs(pan), 1, "\(cue)")
            XCTAssertEqual(String(decoding: RideSounds.wav(notes).prefix(4), as: UTF8.self), "RIFF", "\(cue)")
        }
    }

    // Die Tonsitzung selbst wird hier nicht angefasst: ein Test, der im
    // Simulator wirklich abspielt, hält `xcodebuild` nach dem letzten Test
    // minutenlang offen (gemessen 07.10.2026). Das steht auf der Prüfliste
    // fürs Gerät.
}
