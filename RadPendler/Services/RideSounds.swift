import AVFoundation
import UIKit

/// Die Töne während einer Fahrt: Start, Ende, und vor jeder Abbiegung zwei —
/// einer beim Ankündigen, ein doppelter kurz davor.
///
/// Bis 1.5 gab es während der Fahrt gar keinen Ton. `AudioServicesPlaySystemSound`,
/// das der Countdown benutzt, schweigt bei stummgeschaltetem Telefon und
/// im Hintergrund; am Lenker ist beides der Normalfall. Deshalb spielt hier
/// ein `AVAudioPlayer` in der Kategorie `.playback` (hörbar trotz Stummschalter),
/// gemischt mit anderem Ton und ihn kurz absenkend — Musik oder Podcast laufen
/// weiter. Im Hintergrund braucht das den Hintergrundmodus `audio`.
///
/// Die Töne werden hier erzeugt, nicht mitgeliefert: ein paar Sinusstücke
/// mit weicher Hüllkurve, links und rechts unterschiedlich hoch — wer
/// Kopfhörer trägt, hört die Seite zusätzlich im Stereobild.
@MainActor
final class RideSounds {
    static let shared = RideSounds()

    enum Cue: Equatable {
        case start, stop
        /// `side`: -1 links, 0 geradeaus/Ziel, +1 rechts.
        case turnAhead(side: Int)
        case turnNow(side: Int)
    }

    var enabled = true
    private var player: AVAudioPlayer?
    private var cache: [String: Data] = [:]

    func play(_ cue: Cue) {
        guard enabled else { return }
        let (notes, pan) = Self.notes(cue)
        let key = notes.map { "\($0.hz)-\($0.seconds)" }.joined(separator: ",")
        let data = cache[key] ?? Self.wav(notes)
        cache[key] = data
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.mixWithOthers, .duckOthers])
        try? session.setActive(true)
        guard let p = try? AVAudioPlayer(data: data) else { return }
        p.pan = Float(pan)
        p.volume = 1
        p.play()
        player = p
        let length = p.duration
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(length + 0.3))
            guard self?.player === p else { return }
            // Die Musik wieder auf volle Lautstärke.
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        switch cue {
        case .turnNow, .stop: UINotificationFeedbackGenerator().notificationOccurred(.success)
        default: break
        }
    }

    struct Note { var hz: Double; var seconds: Double }

    /// Links tiefer, rechts höher; die Ankündigung ein Ton, „jetzt" zwei kurze.
    /// Start steigt, Ende fällt.
    nonisolated static func notes(_ cue: Cue) -> ([Note], Double) {
        func pitch(_ side: Int) -> Double { side < 0 ? 740 : side > 0 ? 988 : 880 }
        switch cue {
        case .start: return ([Note(hz: 660, seconds: 0.14), Note(hz: 0, seconds: 0.04), Note(hz: 990, seconds: 0.2)], 0)
        case .stop: return ([Note(hz: 990, seconds: 0.14), Note(hz: 0, seconds: 0.04), Note(hz: 660, seconds: 0.14),
                             Note(hz: 0, seconds: 0.04), Note(hz: 495, seconds: 0.24)], 0)
        case .turnAhead(let side): return ([Note(hz: pitch(side), seconds: 0.22)], Double(side) * 0.7)
        case .turnNow(let side): return ([Note(hz: pitch(side), seconds: 0.1), Note(hz: 0, seconds: 0.06),
                                          Note(hz: pitch(side), seconds: 0.1)], Double(side) * 0.7)
        }
    }

    /// 16-bit mono PCM. `hz == 0` ist Stille. Jede Note blendet 8 ms ein und aus,
    /// sonst knackt es.
    nonisolated static func wav(_ notes: [Note], rate: Double = 22_050) -> Data {
        var samples: [Int16] = []
        for note in notes {
            let n = Int(note.seconds * rate)
            let fade = Int(0.008 * rate)
            for i in 0..<n {
                guard note.hz > 0 else { samples.append(0); continue }
                let env = min(1, Double(i) / Double(fade), Double(n - i) / Double(fade))
                let s = sin(2 * .pi * note.hz * Double(i) / rate) * env * 0.6
                samples.append(Int16(s * Double(Int16.max)))
            }
        }
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes)
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(bytes)
        samples.forEach { withUnsafeBytes(of: $0.littleEndian) { d.append(contentsOf: $0) } }
        return d
    }
}

extension TurnGuide.Turn {
    /// Auf welcher Seite der Pfeil steht und woher der Ton kommt.
    var side: Int {
        switch self {
        case .sharpLeft, .left, .slightLeft: -1
        case .sharpRight, .right, .slightRight: 1
        case .straight, .arrive: 0
        }
    }
}
