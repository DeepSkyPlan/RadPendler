#if DEBUG
import CoreLocation
import Foundation

/// Erfundene Fahrten für den Simulator: eine frisch installierte App hat keine,
/// und Heatmap, Fahrtenliste und Monatssummen zeigen dann nichts, woran sich
/// etwas prüfen ließe. Nur in Debug-Fassungen, nur auf Ansage:
///
///     ./dev demo            # baut, installiert, startet mit -demoRides 18
///
/// Die Linien kommen von den echten Routern zwischen den beiden Testorten
/// (Alexanderplatz, S Wannsee) — drei Radprofile und das Auto —, gefahren wird
/// mal die eine, mal die andere, hin und zurück, mit Halten an immer denselben
/// Stellen. Dieselben Kennungen bei jedem Lauf: ein zweiter Aufruf ersetzt
/// die Fahrten, statt sie zu verdoppeln.
enum DemoRides {
    /// Wie viele bestellt sind (`-demoRides 18`); 0 heißt: keine.
    static var requested: Int { UserDefaults.standard.integer(forKey: "demoRides") }

    static let from = CLLocationCoordinate2D(latitude: 52.5210, longitude: 13.4130)
    static let to = CLLocationCoordinate2D(latitude: 52.4213, longitude: 13.1794)

    private struct Line {
        var mode: TravelMode
        var coordinates: [CLLocationCoordinate2D]
        /// Meter je Sekunde.
        var speed: Double
        /// Wie oft sie unter zehn Fahrten vorkommt.
        var weight: Int
    }

    /// Zufall, der bei jedem Lauf derselbe ist.
    private struct Dice {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 33) / Double(1 << 31)
        }
    }

    @MainActor
    static func seed(into store: RideStore, count: Int) async {
        let router = CompositeRouter()
        func bike(_ profile: BRouterClient.Profile) async -> [CLLocationCoordinate2D] {
            await Log.attemptAsync("Demo-Linie \(profile.rawValue)") {
                try await router.bikeRoute(from: from, to: to, via: [], profile: profile, avoidCobbles: true)
            }?.coordinates ?? []
        }
        let commute = await bike(.trekking)
        let car = await Log.attemptAsync("Demo-Linie Auto") {
            try await router.route(from: from, to: to, mode: .car, departure: nil)
        }?.coordinates ?? []
        var lines = [Line(mode: .bike, coordinates: commute, speed: 5.6, weight: 4),
                     Line(mode: .bike, coordinates: await bike(.fastbike), speed: 6.2, weight: 2),
                     Line(mode: .bike, coordinates: await bike(.quiet), speed: 5.2, weight: 1),
                     Line(mode: .car, coordinates: car, speed: 12.5, weight: 2),
                     // Rad + Bahn: nur das erste Drittel wird gefahren.
                     Line(mode: .bikeTransit, coordinates: Array(commute.prefix(commute.count / 3)), speed: 5.6, weight: 1)]
            .filter { $0.coordinates.count > 1 }
        // Ohne Netz bleibt die Luftlinie — besser als nichts auf der Karte.
        if lines.isEmpty { lines = [Line(mode: .bike, coordinates: [from, to], speed: 5.6, weight: 1)] }
        let deck = lines.flatMap { Array(repeating: $0, count: $0.weight) }
        var dice = Dice(state: 20261012)
        let today = Calendar.current.startOfDay(for: .now)
        for n in 0..<Swift.max(0, Swift.min(count, 60)) {
            let line = deck[Int(dice.next() * Double(deck.count)) % deck.count]
            // Morgens hin, abends zurück, zwei Fahrten je Tag.
            let back = n % 2 == 1
            let start = today.addingTimeInterval(-Double(n / 2 + 1) * 86_400 + (back ? 17.5 : 8) * 3_600)
            let (ride, track) = ride(n, on: line, back: back, start: start, dice: &dice)
            store.add(ride, track: track)
        }
    }

    /// So weit streuen die erfundenen Ortungen um die Linie.
    static let scatterMeters = 7.0
    /// So weit auseinander stehen die erfundenen Ampeln.
    static let signalEvery = 900.0

    private static func ride(_ n: Int, on line: Line, back: Bool, start: Date,
                             dice: inout Dice) -> (Ride, RideTrack) {
        let way = back ? Array(line.coordinates.reversed()) : line.coordinates
        // Die Ampeln hängen an der Linie, nicht an der Richtung: gemessen
        // wird vom selben Ende, damit Hin- und Rückweg dieselben treffen.
        let cum = TurnGuide.cumulative(way)
        let total = cum.last ?? 0
        let speed = line.speed * (0.92 + 0.16 * dice.next())
        var points: [RidePoint] = []
        var stops: [RideStop] = []
        var clock = start
        var (travelled, segment) = (0.0, 0)
        // Vom selben Ende gezählt, in Fahrtrichtung abgearbeitet.
        var nextSignal = back ? (total / signalEvery).rounded(.down) * signalEvery : signalEvery
        var (waited, top) = (0.0, 0.0)
        while travelled < total {
            while segment < cum.count - 2, cum[segment + 1] < travelled { segment += 1 }
            let span = cum[segment + 1] - cum[segment]
            let f = span > 0 ? (travelled - cum[segment]) / span : 0
            let (a, b) = (way[segment], way[segment + 1])
            // Ein paar Meter Streuung, wie sie ein Empfänger hat: ohne sie
            // lägen alle Fahrten auf einem Strich, und die Wolke wäre keine.
            let drift = (dice.next() - 0.5) * 2 * scatterMeters / 111_320
            let here = CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * f + drift,
                                              longitude: a.longitude + (b.longitude - a.longitude) * f + drift * 1.2)
            let fromStart = back ? total - travelled : travelled
            // Schnelle und langsame Abschnitte an immer denselben Stellen —
            // sonst wäre die Karte der Geschwindigkeiten einfarbig.
            let v = speed * (0.6 + 0.6 * abs(sin(fromStart / 1_400))) * (0.9 + 0.2 * dice.next())
            points.append(RidePoint(lat: here.latitude, lon: here.longitude, t: clock, v: v))
            top = Swift.max(top, v)
            // An jeder Ampel knapp jede zweite Fahrt; manche sind lang.
            let reached = back ? nextSignal > 0 && fromStart <= nextSignal : fromStart >= nextSignal
            if reached {
                let index = Int((nextSignal / signalEvery).rounded())
                nextSignal += back ? -signalEvery : signalEvery
                if dice.next() < 0.45 {
                    let wait = (12 + Double(index % 4) * 22) * (0.6 + 0.8 * dice.next())
                    stops.append(RideStop(lat: here.latitude, lon: here.longitude, start: clock,
                                          seconds: wait, atSignal: true))
                    // Im Stehen ein Punkt alle fünf Sekunden reicht fürs Bild.
                    for s in stride(from: 5.0, to: wait, by: 5) {
                        points.append(RidePoint(lat: here.latitude, lon: here.longitude,
                                                t: clock.addingTimeInterval(s), v: 0))
                    }
                    clock.addTimeInterval(wait)
                    waited += wait
                }
            }
            travelled += v
            clock.addTimeInterval(1)
        }
        let id = UUID(uuidString: String(format: "DE300000-0000-4000-8000-%012d", n)) ?? UUID()
        let moving = clock.timeIntervalSince(start) - waited
        let ride = Ride(id: id, started: start, ended: clock,
                        origin: back ? "S Wannsee" : "Alexanderplatz",
                        destination: back ? "Alexanderplatz" : "S Wannsee",
                        mode: line.mode.rawValue, meters: total, movingSeconds: moving, maxKmh: top * 3.6,
                        signalStops: stops.count, otherStops: 0, signalWaitTotal: waited,
                        plannedSeconds: total / line.speed, plannedMeters: total,
                        plannedSignals: Int(total / signalEvery),
                        standingInPause: true, appVersion: "Demo", pointCount: points.count)
        return (ride, RideTrack(id: id, points: points, stops: stops,
                                planned: Geo.thinned(way).map(TrackPoint.init)))
    }
}
#endif
