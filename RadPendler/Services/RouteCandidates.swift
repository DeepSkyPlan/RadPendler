import CoreLocation
import Foundation

// Welche Linie welche Rolle bekommt — „schnellst", „kürzest", „optimal",
// „wenig Autos", „wenig Halts" — und was eine Linie an Zeit kostet.
//
// Das ist die fachlich dichteste Stelle der App und die einzige, die ohne
// Netz auskommt: reine Rechnung auf fertigen Routen. Sie lag in derselben
// Datei wie die vier Modus-Funktionen, die nichts anderes tun, als Dienste zu
// fragen; wer an der Bewertung etwas ändern wollte, scrollte an HAFAS vorbei.

/// One car line and how it scores. Apple gives the times; the lights come
/// from OpenStreetMap, and without them only speed and length can be judged.
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

    /// So viel schneller als der eigene Schnitt darf Apple eine Linie fahren,
    /// bevor der Schnitt für sie nichts mehr sagt. Er ist auf dem Arbeitsweg
    /// gemessen, durch die Stadt; eine Linie, die Apple mehr als anderthalbmal
    /// so schnell fährt, ist eine andere Art Straße. Zum Flughafen über die
    /// Autobahn wurden so aus 37 min 1:05 h (Fahrt 06.10.2026).
    static let ownPaceReach = 1.5

    /// Fahrzeit nach dem eigenen Tür-zu-Tür-Schnitt — nil, wo er nicht gilt:
    /// kein Schnitt gemessen, oder Apple fährt die Linie deutlich schneller.
    func ownPaceTime(kmh: Double?, _ s: PlanSettings) -> TimeInterval? {
        guard let kmh, kmh > 0 else { return nil }
        let own = route.distance / (kmh / 3.6)
        guard own <= driveTime(s) * Self.ownPaceReach else { return nil }
        return own.rounded()
    }

    /// Woher die angezeigte Fahrzeit kommt.
    enum Basis: Equatable { case learned, ownPace, parking, apple }

    /// Tür zu Tür. Am liebsten Apples Zeit mal dem, was dieser Fahrer
    /// gegenüber Apple wirklich braucht — das passt auf Stadt und Autobahn
    /// gleichermaßen, und Parkplatzsuche wie eigener Fahrstil stecken schon
    /// darin. Solange der Faktor nicht gelernt ist: Apple plus Parkplatzsuche,
    /// und der eigene Schnitt als Untergrenze, wo er gilt. Das Motorrad
    /// bekommt nichts davon — es steht vor der Tür, und alles Gemessene ist
    /// mit dem Auto gemessen.
    func doorToDoor(_ s: PlanSettings) -> (seconds: TimeInterval, basis: Basis) {
        let drive = driveTime(s)
        guard !s.motorcycle else { return (drive, .apple) }
        if let f = s.carAppleFactor, f > 0 { return ((drive * f).rounded(), .learned) }
        let apple = drive + TimeInterval(s.parkingMinutes * 60)
        if let own = ownPaceTime(kmh: s.carOverallKmh, s), own > apple { return (own, .ownPace) }
        return (apple, s.parkingMinutes > 0 ? .parking : .apple)
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
        let known = all.contains { $0.signals != nil }
        let winner: [CarVariant: Int] = [
            .fastest: all.indices.min { all[$0].driveTime(s) < all[$1].driveTime(s) },
            .shortest: all.indices.min { all[$0].route.distance < all[$1].route.distance },
            // Ohne Ampeln aus OpenStreetMap gibt es nichts abzuwägen.
            .balanced: known ? all.indices.min { all[$0].balancedScore(s) < all[$1].balancedScore(s) } : nil,
            .fewSignals: known ? all.indices.min { (all[$0].signals ?? .max) < (all[$1].signals ?? .max) } : nil,
        ].compactMapValues { $0 }
        // Was keine Rolle gewinnt, füllt freie Plätze als „Alternative" — die
        // ausgewogenste zuerst, wie beim Rad.
        let spare = all.indices.sorted { all[$0].balancedScore(s) < all[$1].balancedScore(s) }
        // Anders als beim Rad trägt eine gezeigte Linie jeden Namen, den sie
        // gewinnt, auch weiter unten in der Liste: Apple bietet meist nur zwei,
        // drei Linien an, und „optimal · wenig Ampeln" sagt dann mehr als
        // „optimal" allein.
        return RoleAssignment.assign(order: order.filter { $0 != .alternative }, winner: { winner[$0] },
                                     count: Swift.max(1, s.optionsPerMode), spare: spare,
                                     filler: .alternative, namesBeyond: true)
            .map { (all[$0.index], $0.roles) }
    }
}

/// Wer welche Rolle bekommt — für Rad und Auto nach derselben Regel.
///
/// Die obersten `count` Rollen der eigenen Reihenfolge, jede an die Linie, die
/// sie gewinnt. Gewinnt eine Linie gleich mehrere davon, steht sie einmal da
/// mit allen diesen Namen, und es geht die Liste weiter hinunter, bis `count`
/// **verschiedene** Wege dastehen (Nutzer, 28.09.2026: „nur eine Route ist
/// immer doof"). Bringt auch die ganze Liste keinen weiteren Weg, füllen die
/// übrigen Linien die freien Plätze, in der Reihenfolge von `spare`, unter
/// `filler` — ohne einen Namen, den sie nicht verdient haben.
///
/// Bis 1.9.1 hatten Rad und Auto je eine eigene Fassung davon: das Auto
/// vergab alle Rollen und schnitt dann ab, das Rad ging die Liste hinunter
/// und füllte auf.
enum RoleAssignment {
    /// - Parameters:
    ///   - winner: die Linie, die eine Rolle gewinnt; nil, wo sich die Rolle
    ///     nicht beurteilen lässt.
    ///   - namesBeyond: auch Namen, die eine schon gezeigte Linie weiter unten
    ///     in der Liste gewinnt, an sie hängen, nachdem alle Plätze voll sind.
    static func assign<Role: Equatable>(order: [Role], winner: (Role) -> Int?, count n: Int,
                                        spare: [Int], filler: Role,
                                        namesBeyond: Bool = false) -> [(index: Int, roles: [Role])] {
        var boxes: [(index: Int, roles: [Role])] = []
        for (i, role) in order.enumerated() {
            let open = i < n || boxes.count < n
            guard open || namesBeyond else { break }
            guard let w = winner(role) else { continue }
            if let k = boxes.firstIndex(where: { $0.index == w }) {
                boxes[k].roles.append(role)
            } else if open, boxes.count < n {
                boxes.append((w, [role]))
            }
        }
        if boxes.count < n {
            let used = Set(boxes.map(\.index))
            boxes += spare.filter { !used.contains($0) }.prefix(n - boxes.count).map { ($0, [filler]) }
        }
        return boxes
    }
}

/// One bike route candidate and how it scores.
struct BikeCandidate {
    var source: BikeLineSource
    var route: StreetRoute
    var stats: BikeRouteStats?
    /// Die Höhenmeter, mit denen **gerechnet** wird — nicht unbedingt die
    /// gemessenen. Siehe `levelled`.
    var ascent: Double?
    /// Anteil der Meter auf Wegen, die dieser Fahrer schon gefahren ist
    /// (`RiddenPaths`), 0…1.
    var familiar: Double = 0

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
        s.rideTime(meters: route.distance, signals: signals, learned: learned, ascent: ascent, measured: .wins)
    }

    /// Die reine Rechnung, ohne die Gegenprobe. Getrennt, damit sich zeigen
    /// lässt, welche der beiden Zahlen gewonnen hat.
    func computedTime(_ s: PlanSettings) -> TimeInterval {
        s.computedRideTime(meters: route.distance, signals: signals, learned: learned, ascent: ascent)
    }

    /// Ampeln dieser Linie: aus OpenStreetMap, wo analysiert, sonst vom Router.
    private var signals: Int { stats?.signals ?? route.signals }
    private var learned: [LearnedSignal] { stats?.learnedSignals ?? route.learnedSignals }

    /// Ob die Zeit aus der Messung kommt und nicht aus der Rechnung — dann
    /// steht das auch auf der Detailseite, sonst ist es eine Zahl ohne
    /// Herkunft. In beide Richtungen: der gemessene Schnitt darf auch
    /// schneller sein als die Rechnung.
    func measuredWins(_ s: PlanSettings) -> Bool {
        abs(time(s) - computedTime(s)) > 30
    }

    /// Was die Ampeln dieser Linie kosten — gemessen, wo gemessen wurde.
    func signalWait(_ s: PlanSettings) -> TimeInterval {
        s.signalWait(signals: signals, learned: learned)
    }

    /// So viel länger in Metern darf „optimal" sein als die kürzeste Linie,
    /// wenn der Umweg nichts bringt. Wie viel länger in gerechneter Zeit als
    /// die schnellste, stellt der Nutzer ein: `PlanSettings.quietExtraTime`.
    static let detourLimit = 0.10
    /// Und so viel länger in **echten** Metern, was immer der Umweg an Ruhe
    /// bringt. 17 % für 10 km weniger Hauptstraße waren zu viel (30.09.2026),
    /// 13 % für 3 km weniger sollen gehen (06.10.2026).
    static let hardDetourLimit = 0.15
    /// Ein Meter neben einer Hauptstraße — auf ihr oder auf dem Radweg an
    /// ihr — zählt wie zwei auf der ruhigen Nebenstraße (Nutzer, 06.10.2026:
    /// „ruhige Nebenstraße höher bewerten als Radwege neben Hauptstraßen").
    /// Bis 1.14 zählte er wie anderthalb, und nur in der Wertung, nicht beim
    /// Umweg: die kürzeste Linie mit 6,4 km Hauptstraße blieb „optimal",
    /// weil die ruhige mit 3,2 km schon an der Länge scheiterte.
    static let besideMainRoad = 1.0

    func isReasonable(among all: [BikeCandidate], _ s: PlanSettings) -> Bool {
        // Was man ohnehin fährt, ist kein Umweg, sondern eine Entscheidung.
        if familiar >= Self.habitual { return true }
        guard let shortest = all.min(by: { $0.route.distance < $1.route.distance }),
              let fastest = all.map({ $0.computedTime(s) }).min() else { return true }
        // Ein Umweg, der nichts bringt, bleibt bei 10 %. Einer, der von der
        // Hauptstraße wegführt, darf dazu so viele Meter kosten, wie er
        // gegenüber der kürzesten Linie an ihr spart — aber nicht beliebig
        // viele.
        let spared = Swift.max(0, (shortest.stats?.mainRoadMeters ?? 0) - (stats?.mainRoadMeters ?? .infinity))
        let least = shortest.route.distance
        return route.distance <= least * (1 + Self.detourLimit) + Self.besideMainRoad * spared
            && route.distance <= least * (1 + Self.hardDetourLimit)
            && computedTime(s) <= fastest * (1 + s.quietExtraTime)
    }

    /// Mittelweg: time plus half the disturbance, converted to riding time.
    /// Wie bei `fastest` die gerechnete Zeit — hier wird verglichen, nicht
    /// angezeigt.
    /// Vertraute Meter stören nicht: wer eine Straße immer wieder fährt,
    /// hat sie für gut befunden, was immer die Karte über sie sagt. Eine
    /// ganz gefahrene Linie wird so allein nach der Zeit bewertet.
    func balancedScore(_ s: PlanSettings) -> Double {
        // Ampeln und Querungen zur Hälfte wie bisher; die Meter neben der
        // Hauptstraße voll (`besideMainRoad`).
        let main = stats?.mainRoadMeters ?? 0
        let rest = (stats?.disturbance ?? 0) - main
        return computedTime(s) + (1 - familiar) * (Self.besideMainRoad * main + 0.5 * rest) / s.bikeSpeedMps
    }

    /// Ab diesem Anteil fährt man die Linie ohnehin.
    static let habitual = 0.8

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
            // „optimal" ist ein Kompromiss, kein Umweg: nur unter den Linien,
            // die höchstens `detourLimit` länger und `quietExtraTime`
            // langsamer sind als die kürzeste und die schnellste (Nutzer, 30.09.2026: „optimal mit
            // 5 km länger nicht gut"). Wer den Umweg für Ruhe will, hat
            // „wenig Autos".
            let reasonable = all.indices.filter { all[$0].isReasonable(among: all, s) }
            balanced = (reasonable.isEmpty ? Array(all.indices) : reasonable)
                .min { all[$0].balancedScore(s) < all[$1].balancedScore(s) }!
            // Fewest places where traffic makes one stop; metres beside main
            // roads only break the tie.
            lowTraffic = all.indices.min { a, b in
                let sa = all[a].stats, sb = all[b].stats
                let na = sa?.stops ?? .max, nb = sb?.stops ?? .max
                if na != nb { return na < nb }
                return (sa?.mainRoadMeters ?? .infinity) < (sb?.mainRoadMeters ?? .infinity)
            }!
        } else {
            quiet = all.firstIndex { $0.source == .brouter(.quiet) } ?? fastest
            balanced = all.firstIndex { $0.source == .brouter(.trekking) } ?? fastest
            lowTraffic = all.firstIndex { $0.source == .brouter(.lowTraffic) } ?? quiet
        }
        let shortest = all.indices.min { all[$0].route.distance < all[$1].route.distance }!
        let winner: [BikeVariant: Int] = [.fastest: fastest, .shortest: shortest,
                                          .balanced: balanced, .quiet: quiet, .lowTraffic: lowTraffic]
        // Und bringt auch die ganze Liste keinen weiteren Weg, füllt, was an
        // anderen Linien da ist, die freien Plätze — die ausgewogenste zuerst.
        let spare = fill ? all.indices.sorted { all[$0].balancedScore(s) < all[$1].balancedScore(s) } : []
        return RoleAssignment.assign(order: s.bikeVariantOrder.filter { $0 != .alternative },
                                     winner: { winner[$0] }, count: Swift.max(1, s.optionsPerMode),
                                     spare: spare, filler: .alternative)
            .map { (all[$0.index], $0.roles) }
    }
}
