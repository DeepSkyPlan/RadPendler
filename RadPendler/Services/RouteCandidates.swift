import CoreLocation
import Foundation

/// Welche Linie welche Rolle bekommt — „schnellst", „kürzest", „optimal",
/// „ruhigst" — und was eine Linie an Zeit kostet.
///
/// Das ist die fachlich dichteste Stelle der App und die einzige, die ohne
/// Netz auskommt: reine Rechnung auf fertigen Routen. Sie lag in derselben
/// Datei wie die vier Modus-Funktionen, die nichts anderes tun, als Dienste zu
/// fragen; wer an der Bewertung etwas ändern wollte, scrollte an HAFAS vorbei.
struct CarCandidate {
    var route: StreetRoute
    var stats: BikeRouteStats?
    /// Dieselbe Linie ohne Verkehr — Apples Fahrzeit für nachts um drei.
    /// Nur fürs Motorrad gefragt; nil heißt unbekannt.
    var freeFlow: TimeInterval? = nil

    var signals: Int? { stats?.signals }

    /// Welcher Teil des Staus am Motorrad vorbeigeht.
    ///
    /// In der Stadt ist Stau fast immer die Schlange vor der Ampel, und an der
    /// rollt man vorbei bis an die Haltelinie — wie mit dem Rad. Bleibt, was
    /// sich nicht vorbeirollen lässt: die Ampel selbst, wenn sie rot ist, die
    /// Engstelle ohne Platz daneben, der stehende Verkehr auf der Autobahn.
    static let queueShare = 0.7

    /// Apples Fahrzeit mit Verkehrslage — fürs Motorrad ohne den Teil des
    /// Staus, an dem es vorbeirollt. Stau ist, was Apple jetzt mehr braucht
    /// als nachts; ohne die Nachtzahl gibt es keinen Abzug.
    func driveTime(_ s: PlanSettings) -> TimeInterval {
        (route.expectedTravelTime - queueSaving(s)).rounded()
    }

    /// Was das Motorrad gegenüber dem Auto im Stau spart. 0 fürs Auto.
    func queueSaving(_ s: PlanSettings) -> TimeInterval {
        guard s.motorcycle, let freeFlow else { return 0 }
        return Swift.max(0, route.expectedTravelTime - freeFlow) * Self.queueShare
    }

    /// Driving time with the waiting at the lights added, the way the bike
    /// routes count it — an Apple estimate already includes traffic, but not
    /// the difference between twelve junctions and forty.
    func time(_ s: PlanSettings) -> TimeInterval {
        driveTime(s) + Double((signals ?? 0) * s.signalWaitSeconds) * 0.5
    }

    /// Mittelweg: time plus half the waiting, so a line that is two minutes
    /// slower but crosses twenty fewer junctions can win it.
    func balancedScore(_ s: PlanSettings) -> Double {
        driveTime(s) + Double((signals ?? 0) * s.signalWaitSeconds)
    }

    /// Zu jeder Linie mit Verkehr die Fahrzeit ohne: die Nachtlinie gleicher
    /// Länge (auf 2 %, mindestens 150 m), sonst das Verhältnis der beiden
    /// schnellsten. Apple bietet nachts nicht immer dieselben Linien an —
    /// die Autobahn gewinnt, wenn sie frei ist —, aber wie stark der Verkehr
    /// gerade bremst, gilt für die Stadtlinie nebenan ungefähr genauso.
    /// Nie länger als mit Verkehr: schneller als nachts ist niemand, aber
    /// eine Schätzung, die das Motorrad langsamer macht, wäre Unsinn.
    static func freeFlow(day: [StreetRoute], night: [StreetRoute]) -> [TimeInterval?] {
        let ratio: Double? = {
            guard let d = day.map(\.expectedTravelTime).min(), d > 0,
                  let n = night.map(\.expectedTravelTime).min() else { return nil }
            return Swift.min(1, n / d)
        }()
        return day.map { r in
            let tolerance = Swift.max(150, r.distance * 0.02)
            let twin = night
                .filter { abs($0.distance - r.distance) <= tolerance }
                .min { abs($0.distance - r.distance) < abs($1.distance - r.distance) }
            if let twin { return Swift.min(r.expectedTravelTime, twin.expectedTravelTime) }
            return ratio.map { r.expectedTravelTime * $0 }
        }
    }

    /// schnellst = least driving time, kürzest = fewest metres, optimal = the
    /// best balance of time and lights, wenig Ampeln = fewest junctions.
    ///
    /// Every line Apple offered comes back, whether or not it won a role —
    /// showing only the fastest one made the car look like it had no choice.
    /// Roles are ordered the way the user put them.
    static func pick(_ all: [CarCandidate], settings s: PlanSettings = PlanSettings(),
                     order: [CarVariant] = CarVariant.defaultOrder) -> [(CarCandidate, [CarVariant])] {
        guard !all.isEmpty else { return [] }
        // One line wins everything by default; four labels on it say nothing.
        guard all.count > 1 else { return [(all[0], [.fastest])] }
        var roles: [Int: [CarVariant]] = [:]
        if let i = all.indices.min(by: { all[$0].driveTime(s) < all[$1].driveTime(s) }) {
            roles[i, default: []].append(.fastest)
        }
        if let i = all.indices.min(by: { all[$0].route.distance < all[$1].route.distance }) {
            roles[i, default: []].append(.shortest)
        }
        if all.contains(where: { $0.signals != nil }) {
            if let i = all.indices.min(by: { $0 == $1 ? false : all[$0].balancedScore(s) < all[$1].balancedScore(s) }) {
                roles[i, default: []].append(.balanced)
            }
            if let i = all.indices.min(by: { (all[$0].signals ?? .max) < (all[$1].signals ?? .max) }) {
                roles[i, default: []].append(.fewSignals)
            }
        }
        // A line without a role is still a line — aber nur, solange noch ein
        // Platz frei ist. Mehr als die eingestellte Zahl will niemand sehen.
        for i in all.indices where roles[i] == nil { roles[i] = [.alternative] }
        let rank = { (v: CarVariant) in order.firstIndex(of: v) ?? order.count }
        return roles
            .map { (all[$0.key], $0.value.sorted { rank($0) < rank($1) }) }
            .sorted { rank($0.1.first!) < rank($1.1.first!) }
            .prefix(Swift.max(1, s.optionsPerMode))
            .map { $0 }
    }
}

/// One bike route candidate and how it scores.
struct BikeCandidate {
    var source: String
    var route: StreetRoute
    var stats: BikeRouteStats?
    /// Die Höhenmeter, mit denen **gerechnet** wird — nicht unbedingt die
    /// gemessenen. Siehe `levelled`.
    var ascent: Double?

    /// Was ein Höhenmeter an Zeit kostet.
    ///
    /// Fünf Sekunden je Meter sind 720 Höhenmeter in der Stunde — das Tempo
    /// von jemandem, der in der Ebene 29 km/h rollt. Bergab wird nichts
    /// gutgeschrieben: man holt die Zeit, die ein Anstieg kostet, auf der
    /// anderen Seite nicht wieder herein, und eine Strecke mit hundert Metern
    /// hoch und hundert wieder runter ist anstrengender als eine flache, auch
    /// wenn sie am Ende gleich lang ist.
    static let climbSecondsPerMeter = 5.0

    var climbTime: TimeInterval { (ascent ?? 0) * Self.climbSecondsPerMeter }

    /// Apple Karten liefert keine Höhen. Eine Linie, deren Anstieg niemand
    /// kennt, darf dadurch weder gewinnen noch verlieren — sie bekommt für
    /// die Bewertung den Durchschnitt der bekannten. Angezeigt wird trotzdem
    /// nur, was wirklich gemessen ist.
    static func levelled(_ all: [BikeCandidate]) -> [BikeCandidate] {
        let known = all.compactMap(\.route.ascent)
        guard !known.isEmpty else { return all }
        let mean = known.reduce(0, +) / Double(known.count)
        return all.map { var c = $0; c.ascent = c.route.ascent ?? mean; return c }
    }

    /// Riding time at the configured speed, the expected wait at lights, and
    /// what the climbing costs — und darunter nie schneller, als dieser Fahrer
    /// laut seinen eigenen Fahrten wirklich ist.
    func time(_ s: PlanSettings) -> TimeInterval {
        s.realistic(computedTime(s), meters: route.distance)
    }

    /// Die reine Rechnung, ohne die Gegenprobe. Getrennt, damit sich zeigen
    /// lässt, welche der beiden Zahlen gewonnen hat.
    func computedTime(_ s: PlanSettings) -> TimeInterval {
        s.bikeTime(route.distance) + signalWait(s) + climbTime
    }

    /// Ob die Zeit aus der Messung kommt und nicht aus der Rechnung — dann
    /// steht das auch auf der Detailseite, sonst ist es eine Zahl ohne
    /// Herkunft. In beide Richtungen: der gemessene Schnitt darf auch
    /// schneller sein als die Rechnung.
    func measuredWins(_ s: PlanSettings) -> Bool {
        abs(time(s) - computedTime(s)) > 30
    }

    /// Was die Ampeln dieser Linie kosten — gemessen, wo gemessen wurde.
    func signalWait(_ s: PlanSettings) -> TimeInterval {
        s.signalWait(signals: stats?.signals ?? route.signals,
                     learned: stats?.learnedSignals ?? route.learnedSignals)
    }

    /// Mittelweg: time plus half the disturbance, converted to riding time.
    /// Wie bei `fastest` die gerechnete Zeit — hier wird verglichen, nicht
    /// angezeigt.
    func balancedScore(_ s: PlanSettings) -> Double {
        computedTime(s) + 0.5 * (stats?.disturbance ?? 0) / s.bikeSpeedMps
    }

    /// schnellst = least riding time (traffic lights included), ruhigst =
    /// least disturbance, verkehrsarm = fewest places where traffic makes one
    /// stop (lit junctions and main roads crossed), optimal = best balance of
    /// time and disturbance. A route winning several
    /// roles is listed once with all its labels. Without OpenStreetMap data
    /// only the time can be judged; BRouter's "safety" route then stands in
    /// for "ruhigst" and its low-traffic profile for "verkehrsarm".
    ///
    /// "ruhigst" and "verkehrsarm" are not the same question: the first counts
    /// lights and crossings too, the second only asks where the cars are.
    ///
    /// The list comes back in the order the user put the variants in, so the
    /// first route is the one the app suggests and the first the boxes show.
    /// Zwei Linien sind dieselbe, wenn die eine überall auf der anderen liegt.
    /// Geprüft an neun Punkten der einen gegen die ganze andere — das ist
    /// unempfindlich dagegen, dass zwei Profile dieselbe Straße mit
    /// verschieden vielen Stützpunkten beschreiben.
    static func sameLine(_ a: StreetRoute, _ b: StreetRoute, tolerance: Double = 25) -> Bool {
        guard a.coordinates.count > 1, b.coordinates.count > 1 else { return false }
        guard abs(a.distance - b.distance) <= 0.02 * Swift.max(a.distance, b.distance) else { return false }
        let step = Swift.max(1, (a.coordinates.count - 1) / 8)
        for i in stride(from: 0, to: a.coordinates.count, by: step) {
            guard let fix = OffRoute.nearest(to: a.coordinates[i], on: b.coordinates),
                  fix.meters <= tolerance else { return false }
        }
        return true
    }

    /// Neun Anfragen, aber oft nur drei verschiedene Wege: „trekking",
    /// „fastbike" und „safety" einigen sich auf einer Pendelstrecke gern auf
    /// dieselbe Straße. Doppelte müssen raus, bevor Rollen vergeben werden —
    /// sonst nehmen zwei gleiche Linien einander die Rollen weg und eine
    /// dritte, wirklich andere, fällt hinten herunter.
    static func distinct(_ all: [BikeCandidate]) -> [BikeCandidate] {
        var out: [BikeCandidate] = []
        for c in all where !out.contains(where: { sameLine($0.route, c.route) }) { out.append(c) }
        return out
    }

    /// schnellst = kürzeste Fahrzeit (Ampeln und Höhenmeter inbegriffen),
    /// ruhigst = am wenigsten Störung, verkehrsarm = am seltensten wegen des
    /// Verkehrs anhalten, optimal = bestes Verhältnis von Zeit und Störung.
    /// Eine Linie, die mehrere Rollen gewinnt, steht einmal da und trägt alle
    /// ihre Namen — ein Name muss wahr bleiben: „schnellst" ist die
    /// schnellste, nicht die zweitschnellste.
    ///
    /// **Und jede übrige Linie bleibt trotzdem wählbar.** Sie bekommt keinen
    /// Namen, weil sie in keiner Hinsicht die beste ist — aber sie ist ein
    /// anderer Weg, und den wegzuwerfen war der Grund, aus dem unter dem
    /// Rad-Kasten oft nur zwei Punkte standen, obwohl neun Routen angefragt
    /// wurden. Beim Auto gab es diesen Auffangfall immer („Alternative"),
    /// beim Rad nicht.
    ///
    /// Ohne OpenStreetMap-Daten lässt sich nur die Zeit beurteilen; dann steht
    /// BRouters „safety"-Route für „ruhigst" und sein Verkehrsarm-Profil für
    /// „verkehrsarm".
    ///
    /// Die Liste kommt in der Reihenfolge zurück, die der Nutzer eingestellt
    /// hat; die namenlosen Linien hängen hinten an, die schnellste zuerst.
    static func pick(_ candidates: [BikeCandidate], settings s: PlanSettings,
                     fill: Bool = true) -> [(BikeCandidate, [BikeVariant])] {
        let all = levelled(distinct(candidates))
        // `computedTime`, nicht `time`: die angezeigte Fahrzeit kommt aus dem
        // gemessenen Schnitt, und der kennt nur die Länge. Welche von drei
        // Linien die schnellste ist, entscheidet die Rechnung — sie ist die
        // einzige, die Ampeln und Höhenmeter auseinanderhält. Ohne das wäre
        // „schnellst" immer dieselbe Linie wie „kürzest".
        guard let fastest = all.indices.min(by: { all[$0].computedTime(s) < all[$1].computedTime(s) })
        else { return [] }
        let quiet: Int, balanced: Int, lowTraffic: Int
        if all.contains(where: { $0.stats != nil }) {
            quiet = all.indices.min { (all[$0].stats?.disturbance ?? .infinity) < (all[$1].stats?.disturbance ?? .infinity) }!
            balanced = all.indices.min { all[$0].balancedScore(s) < all[$1].balancedScore(s) }!
            // Fewest places where traffic makes one stop; metres beside main
            // roads only break the tie.
            lowTraffic = all.indices.min { a, b in
                let sa = all[a].stats, sb = all[b].stats
                let na = sa?.stops ?? .max, nb = sb?.stops ?? .max
                if na != nb { return na < nb }
                return (sa?.mainRoadMeters ?? .infinity) < (sb?.mainRoadMeters ?? .infinity)
            }!
        } else {
            quiet = all.firstIndex { $0.source == "safety" } ?? fastest
            balanced = all.firstIndex { $0.source == "trekking" } ?? fastest
            lowTraffic = all.firstIndex { $0.source == L("verkehrsarm") } ?? quiet
        }
        let shortest = all.indices.min { all[$0].route.distance < all[$1].route.distance }!
        let n = Swift.max(1, s.optionsPerMode)
        // Die obersten `n` Rollen der eigenen Reihenfolge — und gewinnt eine
        // Linie gleich mehrere davon, geht es die Liste weiter hinunter, bis
        // `n` **verschiedene** Wege dastehen (Nutzer, 28.09.2026: „nur eine
        // Route ist immer doof"). Jede Linie trägt die Namen, die sie dabei
        // gewonnen hat; ein Name bleibt wahr.
        let order = s.bikeVariantOrder.filter { $0 != .alternative }
        let winner: [BikeVariant: Int] = [.fastest: fastest, .shortest: shortest,
                                          .balanced: balanced, .quiet: quiet, .lowTraffic: lowTraffic]
        var boxes: [(key: Int, names: [BikeVariant])] = []
        for (i, v) in order.enumerated() {
            guard i < n || boxes.count < n else { break }
            let w = winner[v]!
            if let k = boxes.firstIndex(where: { $0.key == w }) {
                boxes[k].names.append(v)
            } else if boxes.count < n {
                boxes.append((w, [v]))
            }
        }
        // Und bringt auch die ganze Liste keinen weiteren Weg, füllt, was an
        // anderen Linien da ist, die freien Plätze — die ausgewogenste zuerst,
        // als „Alternative", ohne einen Namen, den sie nicht verdient.
        if fill, boxes.count < n {
            let used = Set(boxes.map(\.key))
            let spare = all.indices.filter { !used.contains($0) }
                .sorted { all[$0].balancedScore(s) < all[$1].balancedScore(s) }
            boxes += spare.prefix(n - boxes.count).map { (key: $0, names: [BikeVariant.alternative]) }
        }
        return boxes.map { (all[$0.key], $0.names) }
    }
}


/// Refuses every request. Lets a test run a real planner without a network.
