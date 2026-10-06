import CoreLocation
import Foundation

// Was die App aus den eigenen Fahrten lernt: Ampeln, Rolltempo, Schnitte.
// Lag bis 1.9.1 mitten in AppSettings.swift zwischen Laden und Adressen.

extension AppSettings {
    /// Was eine beendete Fahrt über die Kreuzungen auf ihr weiß: an welchen
    /// gewartet wurde, und an welchen eben nicht.
    ///
    /// Das zweite ist so wichtig wie das erste. Zählt man nur die Halte, ist
    /// der Mittelwert einer Ampel der Mittelwert der Male, an denen man
    /// gewartet hat — eine Ampel, die jede zweite Fahrt grün ist, kostete
    /// dann das Doppelte dessen, was sie wirklich kostet. Deshalb zählt jede
    /// Kreuzung, an der die aufgezeichnete Linie vorbeikam, eine Vorbeifahrt.
    ///
    /// `junctions` sind die Kreuzungen der geplanten Route — die aus
    /// OpenStreetMap und die schon gelernten.
    func learn(stops: [RideStop], track: [RidePoint] = [], junctions: [CLLocationCoordinate2D] = []) {
        var list = learnedSignals
        for stop in stops where stop.atSignal {
            list = LearnedSignal.recording(list, at: stop.coordinate, waited: stop.seconds)
        }
        // Eine Kreuzung, eine Vorbeifahrt. Die Liste kommt aus zwei Quellen —
        // den Ampeln der geplanten Route und den gelernten — und dieselbe
        // Kreuzung steht deshalb oft zweimal darin; zweimal gezählt hielte sie
        // für halb so teuer, wie sie ist.
        var counted = stops.filter(\.atSignal).map(\.coordinate)
        for j in junctions {
            // An dieser Kreuzung wurde gerade gehalten — der Halt hat seine
            // Vorbeifahrt schon mitgebracht.
            guard !counted.contains(where: { $0.distance(to: j) <= LearnedSignal.mergeRadius }) else { continue }
            guard track.contains(where: { $0.coordinate.distance(to: j) <= LearnedSignal.passRadius }) else { continue }
            counted.append(j)
            list = LearnedSignal.passing(list, at: j)
        }
        guard list != learnedSignals else { return }
        learnedSignals = list
    }

    /// So viele Fahrten müssen es sein, bevor gemessene Werte die
    /// eingestellten ablösen. Eine einzelne Fahrt ist Wetter, Wind und ein
    /// Zug, der vor der Schranke stand.
    static let calibrationRides = 3
    /// Und so viele werden angeschaut. Mehr wäre das Rad von vorletztem
    /// Winter; weniger schwankt mit jedem Regentag.
    static let calibrationWindow = 8

    /// Was die App über diesen Fahrer weiß, aus seinen eigenen Fahrten:
    /// rollendes Tempo und Tür-zu-Tür-Schnitt. Der Median, nicht der
    /// Mittelwert — eine Fahrt mit Platten darf den Schnitt nicht kippen.
    ///
    /// Das rollende Tempo landet in `calibratedBikeSpeedKmh`, der
    /// Tür-zu-Tür-Schnitt in `calibratedBikeOverallKmh` — beim Planen die
    /// Gegenprobe. Was der Nutzer von Hand gestellt hat (`…Override`), bleibt
    /// stehen: die Messung schreibt daneben, nicht darüber.
    func calibrate(from rides: [Ride], mode: TravelMode = .bike) {
        let relevant = rides
            .filter { $0.travelMode == mode && $0.meters >= 2_000 && $0.movingSeconds > 60 }
            .sorted { $0.started > $1.started }
            .prefix(Self.calibrationWindow)
        guard relevant.count >= Self.calibrationRides else { return }
        let moving = Self.median(relevant.map(\.movingKmh))
        let overall = Self.median(relevant.map(\.averageKmh))
        measuredRides = relevant.count
        measuredMovingKmh = moving
        measuredOverallKmh = overall
        calibratedBikeOverallKmh = Self.halfStep(overall)
        // Gerundet auf das, was der Stepper für den Wert von Hand hergibt.
        let speed = (moving).rounded()
        if speed >= 10, speed <= 45, speed != calibratedBikeSpeedKmh { calibratedBikeSpeedKmh = speed }
        // Und die Ampelwartezeit folgt dem, was an Ampeln wirklich gewartet
        // wurde — siehe `signalMeasurement`.
        if let m = signalMeasurement, m.passes >= Self.signalCalibrationPasses {
            let seconds = Int((m.wait / Double(m.passes) / 5).rounded() * 5)
            let clamped = Swift.min(90, Swift.max(0, seconds))
            if clamped != calibratedSignalWaitSeconds { calibratedSignalWaitSeconds = clamped }
        }
    }

    /// Dasselbe fürs Auto, ohne Rolltempo und Ampeln: nur der Tür-zu-Tür-
    /// Schnitt. Er ist beim Planen die Untergrenze für Apples Fahrzeit —
    /// Apple kennt den Verkehr, aber nicht den Parkplatz vor der Tür und
    /// nicht, wie dieser Fahrer fährt. Motorradfahrten zählen nicht mit: sie
    /// rollen am Stau vorbei und würden das Auto schneller machen, als es ist.
    ///
    /// Und der Faktor gegenüber Apple (`carAppleFactor`): aus den Fahrten, die
    /// Apples Ansage mitgebracht haben. Sobald es ihn gibt, löst er Schnitt
    /// und Parkplatzsuche beim Planen ab — siehe `CarCandidate.doorToDoor`.
    func calibrateCar(from rides: [Ride]) {
        let cars = rides
            .filter { $0.travelMode == .car && $0.motorcycle != true && $0.meters >= 2_000 && $0.movingSeconds > 60 }
            .sorted { $0.started > $1.started }
        let factors = cars.compactMap(\.appleFactor).prefix(Self.calibrationWindow)
        if factors.count >= Self.calibrationRides {
            let f = Swift.min(Self.carAppleFactorRange.upperBound,
                              Swift.max(Self.carAppleFactorRange.lowerBound, Self.median(Array(factors))))
            carAppleFactorRides = factors.count
            // Auf Hundertstel — mehr zeigt die Zeile nicht, und über iCloud
            // soll nicht jede Nachkommastelle reisen.
            carAppleFactor = (f * 100).rounded() / 100
        }
        let relevant = cars.prefix(Self.calibrationWindow)
        guard relevant.count >= Self.calibrationRides else { return }
        let overall = Self.median(relevant.map(\.averageKmh))
        measuredCarRides = relevant.count
        measuredCarKmh = overall
        calibratedCarOverallKmh = overall.rounded()
    }

    /// Weiter weg von Apple als das ist kein Fahrstil mehr, sondern ein
    /// Messfehler — eine Woche Baustelle soll die Planung nicht verdoppeln.
    static let carAppleFactorRange = 0.8...2.0

    /// Auf halbe km/h — so weit, wie der Stepper geht.
    static func halfStep(_ kmh: Double) -> Double { (kmh * 2).rounded() / 2 }

    static func median(_ values: [Double]) -> Double {
        let s = values.sorted()
        guard !s.isEmpty else { return 0 }
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    /// So viele Vorbeifahrten braucht es, bevor der gemessene Ampelschnitt den
    /// eingestellten ablöst. Zwei Pendelfahrten über zwanzig Kreuzungen.
    static let signalCalibrationPasses = 40

    /// Was an den Ampeln dieses Fahrers wirklich passiert: wie oft er an
    /// einer stand, wie oft er durchkam, und wie lange er zusammen gewartet
    /// hat. Aus den gelernten Kreuzungen — die zählen beides mit.
    var signalMeasurement: (passes: Int, stops: Int, wait: TimeInterval)? {
        guard !learnedSignals.isEmpty else { return nil }
        let passes = learnedSignals.reduce(0) { $0 + $1.passCount }
        guard passes > 0 else { return nil }
        return (passes, learnedSignals.reduce(0) { $0 + $1.stops },
                learnedSignals.reduce(0) { $0 + $1.totalWait })
    }
}
