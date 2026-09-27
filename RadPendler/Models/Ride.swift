import CoreLocation
import Foundation

/// One fix of a recorded ride. The names are short because a ride holds
/// thousands of them and every one of them is written out as JSON: "lat"
/// instead of "latitude" is a quarter of the file.
struct RidePoint: Codable, Equatable {
    var lat: Double
    var lon: Double
    var t: Date
    /// Metres per second — what the receiver said, or the step divided by its
    /// seconds where it said nothing.
    var v: Double
    /// Höhe über dem Meer, in Metern. nil heißt **unbekannt**, nicht flach:
    /// der Empfänger sagt sie nur, wenn er sie hat, und die Fassungen vor dem
    /// Höhenprofil haben sie nie mitgeschrieben.
    var h: Double?

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    var kmh: Double { v * 3.6 }
}

/// Eine Ecke einer geplanten Linie. Zwei Zahlen, weil mehr nicht gebraucht
/// wird: die geplante Route liegt neben der gefahrenen auf der Karte, damit man
/// sieht, wo man anders gefahren ist.
struct TrackPoint: Codable, Equatable {
    var lat: Double
    var lon: Double

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }

    init(lat: Double, lon: Double) { (self.lat, self.lon) = (lat, lon) }
    init(_ c: CLLocationCoordinate2D) { self.init(lat: c.latitude, lon: c.longitude) }
}

/// A standstill long enough to be worth counting. Whether it was a red light
/// is decided here, once, against the lit junctions the route analysis found —
/// not later against whatever OpenStreetMap happens to say next month.
struct RideStop: Codable, Equatable, Identifiable {
    var id = UUID()
    var lat: Double
    var lon: Double
    var start: Date
    var seconds: TimeInterval
    var atSignal: Bool

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

/// The line and the stops of one ride. Kept apart from the summary on purpose:
/// a list of three hundred rides must not pull three hundred tracks into
/// memory to draw a table of dates and averages.
struct RideTrack: Codable, Equatable {
    var id: UUID
    var points: [RidePoint] = []
    var stops: [RideStop] = []
    /// Die Linie, die geplant war, als die Fahrt begann — ausgedünnt auf das,
    /// was man auf einer Karte unterscheiden kann. Sie liegt hinterher dünn
    /// neben der gefahrenen: der Unterschied ist die eigentliche Auskunft.
    var planned: [TrackPoint] = []

    var coordinates: [CLLocationCoordinate2D] { points.map(\.coordinate) }
    var plannedCoordinates: [CLLocationCoordinate2D] { planned.map(\.coordinate) }
}

/// A ride that happened, as the list remembers it. Everything here is a fact
/// that was measured; what can be derived from those facts is computed, so a
/// file written by an older version cannot disagree with itself.
struct Ride: Codable, Identifiable, Equatable {
    var id = UUID()
    var started: Date
    var ended: Date
    var origin: String
    var destination: String
    /// `TravelMode.rawValue` of the trip that was planned when the ride began.
    var mode: String
    var meters: Double
    var movingSeconds: TimeInterval
    var maxKmh: Double
    var signalStops: Int
    var otherStops: Int
    var signalWaitTotal: TimeInterval
    /// How long the plan said it would take, for the one comparison that is
    /// actually interesting: was the app right? nil when nothing was planned.
    var plannedSeconds: TimeInterval?
    /// Wie lang die geplante Strecke war und wie viele Ampeln auf ihr gezählt
    /// wurden. Beides nil, wenn nichts geplant war — und beides hier
    /// festgehalten, weil die Planung von morgen eine andere ist.
    var plannedMeters: Double?
    var plannedSignals: Int?
    /// Gewollte Pausen: was zwischen „Pause" und „Weiter" lag. Zählt weder
    /// zur Fahrzeit noch in den Schnitt — sonst wäre jede Einkehr eine
    /// langsame Fahrt. Ältere Dateien kennen das Feld nicht; dort ist es 0.
    var pausedSeconds: TimeInterval = 0
    /// Ob das Stehen **vor** einer Pause schon in `pausedSeconds` steckt. Bis
    /// 1.5 begann die Pause erst beim Tippen, die Minuten Stillstand davor
    /// zählten als Fahrzeit. Neue Fahrten tragen true; ältere rechnet
    /// `RideStore.repairStandingBeforePauses` einmal aus ihrer Linie nach und
    /// setzt es dann — damit es auf keinem Gerät zweimal abgezogen wird.
    var standingInPause: Bool?
    /// Womit sie aufgezeichnet wurde — „1.4 (38)". Wer eine alte Fahrt ansieht
    /// und sich über eine Zahl wundert, sieht so, ob sie aus einer Fassung
    /// stammt, die anders gerechnet hat. Ältere Dateien kennen das Feld nicht.
    var appVersion: String?
    var pointCount: Int = 0
    /// Metres per kind of road, attributed to the route that was planned.
    /// nil where nobody classified the route — Apple's lines carry no tags.
    var mix: RoadMix?

    var seconds: TimeInterval { max(0, ended.timeIntervalSince(started) - pausedSeconds) }
    /// Door to door, standing time included.
    var averageKmh: Double { seconds > 0 ? meters / seconds * 3.6 : 0 }
    /// While rolling — the number that says how fast one rides, as opposed to
    /// how long the way takes.
    var movingKmh: Double { movingSeconds > 0 ? meters / movingSeconds * 3.6 : 0 }
    var standingSeconds: TimeInterval { max(0, seconds - movingSeconds) }
    var signalWaitAverage: TimeInterval {
        signalStops > 0 ? signalWaitTotal / Double(signalStops) : 0
    }
    var stops: Int { signalStops + otherStops }
    var travelMode: TravelMode? { TravelMode(rawValue: mode) }
    /// Minutes off the plan; negative means faster than announced.
    var deviationSeconds: TimeInterval? { plannedSeconds.map { seconds - $0 } }
    /// Der Schnitt, den der Plan versprochen hat — Tür zu Tür, wie `averageKmh`.
    var plannedAverageKmh: Double? {
        guard let s = plannedSeconds, s > 0, let m = plannedMeters, m > 0 else { return nil }
        return m / s * 3.6
    }
}

// MARK: Grouping

extension Ride {
    /// The rides of one month, with the sums that make a month worth a heading.
    struct Month: Identifiable, Equatable {
        var id: String
        var title: String
        var rides: [Ride]

        var meters: Double { rides.reduce(0) { $0 + $1.meters } }
        var seconds: TimeInterval { rides.reduce(0) { $0 + $1.seconds } }
        var averageKmh: Double { seconds > 0 ? meters / seconds * 3.6 : 0 }
        var signalStops: Int { rides.reduce(0) { $0 + $1.signalStops } }
    }

    struct Year: Identifiable, Equatable {
        var id: Int
        var months: [Month]

        var rides: [Ride] { months.flatMap(\.rides) }
        var meters: Double { months.reduce(0) { $0 + $1.meters } }
        var seconds: TimeInterval { months.reduce(0) { $0 + $1.seconds } }
        var averageKmh: Double { seconds > 0 ? meters / seconds * 3.6 : 0 }
    }

    /// Years newest first, months within a year newest first, rides within a
    /// month newest first — a list one reads from the top downwards into the past.
    static func grouped(_ rides: [Ride], calendar: Calendar = .current) -> [Year] {
        var byYear: [Int: [Int: [Ride]]] = [:]
        for ride in rides {
            let parts = calendar.dateComponents([.year, .month], from: ride.started)
            guard let y = parts.year, let m = parts.month else { continue }
            byYear[y, default: [:]][m, default: []].append(ride)
        }
        return byYear.keys.sorted(by: >).map { y in
            Year(id: y, months: byYear[y]!.keys.sorted(by: >).map { m in
                Month(id: "\(y)-\(String(format: "%02d", m))",
                      title: monthName(m, calendar: calendar),
                      rides: byYear[y]![m]!.sorted { $0.started > $1.started })
            })
        }
    }

    static func monthName(_ month: Int, calendar: Calendar = .current) -> String {
        let names = calendar.standaloneMonthSymbols
        return names.indices.contains(month - 1) ? names[month - 1] : "\(month)"
    }
}

// MARK: Stehen vor der Pause, nachträglich

extension Ride {
    /// Wie lange vor jeder Pause schon gestanden wurde — aus der Linie
    /// gelesen, für Fahrten, bei denen die Pause erst beim Tippen begann.
    ///
    /// Eine Pause ist in der Linie eine Lücke: die Ortung war aus. Welche
    /// Lücken Pausen sind und welche nur Empfangslöcher, sagt `pausedSeconds`:
    /// die längsten Lücken, solange sie zusammen nicht über die gespeicherte
    /// Pausenzeit hinausgehen (eine Lücke ist bis zu `maxGap` länger als die
    /// Pause, weil der erste Fix danach etwas braucht). Vor jeder davon zählt
    /// die zusammenhängende Strecke unter `stopSpeed` — einen Halt kann es
    /// darin nicht geben, der endete erst über `goSpeed`.
    static func standingBeforePauses(_ points: [RidePoint], pausedSeconds: TimeInterval) -> TimeInterval {
        guard pausedSeconds > 0, points.count >= 2 else { return 0 }
        let gaps = (0..<(points.count - 1))
            .map { (i: $0, dt: points[$0 + 1].t.timeIntervalSince(points[$0].t)) }
            .filter { $0.dt > RideMeter.maxGap }
            .sorted { $0.dt > $1.dt }
        var covered: TimeInterval = 0, taken = 0.0
        var extra: TimeInterval = 0
        for gap in gaps {
            guard covered + gap.dt <= pausedSeconds + RideMeter.maxGap * (taken + 1) else { continue }
            covered += gap.dt
            taken += 1
            var j = gap.i
            while j > 0, points[j - 1].v < RideMeter.stopSpeed { j -= 1 }
            if points[gap.i].v < RideMeter.stopSpeed {
                extra += points[gap.i].t.timeIntervalSince(points[j].t)
            }
        }
        return extra
    }
}
