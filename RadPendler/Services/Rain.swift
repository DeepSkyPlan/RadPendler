import CoreLocation
import Foundation

/// Where and when the rider will be, so the forecast is read for that place at
/// that time — not for "Berlin, now".
struct RainSample: Equatable {
    var coordinate: CLLocationCoordinate2D
    var time: Date

    static func == (a: RainSample, b: RainSample) -> Bool {
        a.coordinate.latitude == b.coordinate.latitude && a.coordinate.longitude == b.coordinate.longitude
            && a.time == b.time
    }
}

struct RainReading {
    var sample: RainSample
    /// Precipitation in the 15-minute slot containing `sample.time`, mm.
    var millimetres: Double
    /// Probability of any precipitation in that slot, percent.
    var probability: Int
}

enum RainLevel: Int, Comparable {
    case dry, possible, light, rain, heavy

    static func < (a: RainLevel, b: RainLevel) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .dry: "trocken"
        case .possible: "Schauer möglich"
        case .light: "leichter Regen"
        case .rain: "Regen"
        case .heavy: "starker Regen"
        }
    }

    var symbol: String {
        switch self {
        case .dry: "sun.max"
        case .possible: "cloud.sun.rain"
        case .light: "cloud.drizzle"
        case .rain: "cloud.rain"
        case .heavy: "cloud.heavyrain"
        }
    }

    /// Classification of one 15-minute slot.
    static func of(millimetres mm: Double, probability: Int) -> RainLevel {
        switch mm {
        case 2...: .heavy
        case 0.5...: .rain
        case 0.05...: .light
        default: probability >= 40 ? .possible : .dry
        }
    }
}

struct RainAssessment {
    var readings: [RainReading]

    var level: RainLevel {
        readings.map { RainLevel.of(millimetres: $0.millimetres, probability: $0.probability) }.max() ?? .dry
    }

    var maxMillimetres: Double { readings.map(\.millimetres).max() ?? 0 }
    var maxProbability: Int { readings.map(\.probability).max() ?? 0 }

    /// First moment on the ride that is wetter than "possible".
    var firstWet: Date? {
        readings.filter { RainLevel.of(millimetres: $0.millimetres, probability: $0.probability) >= .light }
            .map(\.sample.time).min()
    }

    var summary: String {
        switch level {
        case .dry: return maxProbability > 0 ? "trocken (\(maxProbability) %)" : "trocken"
        case .possible: return "Schauer möglich (\(maxProbability) %)"
        default:
            let from = firstWet.map { " ab \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
            return "\(level.label)\(from), bis \(String(format: "%.1f", maxMillimetres)) mm/15 min"
        }
    }
}

enum RainSampler {
    /// Points every `spacing` metres along a leg (ends included), each stamped
    /// with the time the rider passes it at constant speed.
    static func samples(along coords: [CLLocationCoordinate2D], departure: Date, arrival: Date,
                        spacing: Double = 1500) -> [RainSample] {
        guard let first = coords.first else { return [] }
        var cumulative: [Double] = [0]
        for (a, b) in zip(coords, coords.dropFirst()) {
            cumulative.append(cumulative.last! + a.distance(to: b))
        }
        let total = cumulative.last!
        let duration = arrival.timeIntervalSince(departure)
        guard total > 0 else { return [RainSample(coordinate: first, time: departure)] }

        let steps = max(1, Int((total / spacing).rounded(.up)))
        return (0...steps).map { i in
            let target = total * Double(i) / Double(steps)
            let j = cumulative.lastIndex { $0 <= target } ?? 0
            let c: CLLocationCoordinate2D
            if j >= coords.count - 1 {
                c = coords[coords.count - 1]
            } else {
                let seg = cumulative[j + 1] - cumulative[j]
                let f = seg > 0 ? (target - cumulative[j]) / seg : 0
                c = CLLocationCoordinate2D(
                    latitude: coords[j].latitude + (coords[j + 1].latitude - coords[j].latitude) * f,
                    longitude: coords[j].longitude + (coords[j + 1].longitude - coords[j].longitude) * f)
            }
            return RainSample(coordinate: c, time: departure.addingTimeInterval(duration * target / total))
        }
    }

    /// Position on a leg at `time`, or nil outside the leg's time span.
    static func position(on coords: [CLLocationCoordinate2D], departure: Date, arrival: Date,
                         at time: Date) -> CLLocationCoordinate2D? {
        guard time >= departure, time <= arrival, coords.count > 1 else { return nil }
        let f = arrival > departure ? time.timeIntervalSince(departure) / arrival.timeIntervalSince(departure) : 0
        var cumulative: [Double] = [0]
        for (a, b) in zip(coords, coords.dropFirst()) { cumulative.append(cumulative.last! + a.distance(to: b)) }
        let target = cumulative.last! * f
        let j = min(cumulative.lastIndex { $0 <= target } ?? 0, coords.count - 2)
        let seg = cumulative[j + 1] - cumulative[j]
        let g = seg > 0 ? (target - cumulative[j]) / seg : 0
        return CLLocationCoordinate2D(latitude: coords[j].latitude + (coords[j + 1].latitude - coords[j].latitude) * g,
                                      longitude: coords[j].longitude + (coords[j + 1].longitude - coords[j].longitude) * g)
    }
}

/// 15-minute precipitation from Open-Meteo (DWD ICON-D2 over Germany), one
/// request for all sample points. Free for non-commercial use, no key.
struct RainService {
    var session: URLSession = .shared

    enum RainError: LocalizedError {
        case malformed
        var errorDescription: String? { "Wetterdaten: unerwartete Antwort" }
    }

    func readings(for samples: [RainSample]) async throws -> [RainReading] {
        guard !samples.isEmpty else { return [] }
        // Round to ~1 km so neighbouring samples share a forecast cell and a URL slot.
        let points = Array(Set(samples.map { GridPoint($0.coordinate) })).sorted()
        let times = samples.map(\.time)
        let start = times.min()!.addingTimeInterval(-900), end = times.max()!.addingTimeInterval(900)

        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            .init(name: "latitude", value: points.map { String(format: "%.3f", $0.lat) }.joined(separator: ",")),
            .init(name: "longitude", value: points.map { String(format: "%.3f", $0.lon) }.joined(separator: ",")),
            .init(name: "minutely_15", value: "precipitation,precipitation_probability"),
            .init(name: "timezone", value: "GMT"),
            .init(name: "start_minutely_15", value: Self.slotString(start)),
            .init(name: "end_minutely_15", value: Self.slotString(end)),
        ]
        let (data, _) = try await session.data(from: comps.url!)
        let series = try Self.parse(data)
        guard series.count == points.count else { throw RainError.malformed }
        let byPoint = Dictionary(uniqueKeysWithValues: zip(points, series))

        return samples.map { s in
            let slot = byPoint[GridPoint(s.coordinate)]?.slot(containing: s.time)
            return RainReading(sample: s, millimetres: slot?.mm ?? 0, probability: slot?.probability ?? 0)
        }
    }

    struct Series {
        var times: [Date]
        var mm: [Double]
        var probability: [Int]

        /// Open-Meteo stamps a 15-minute sum with the END of its interval.
        func slot(containing t: Date) -> (mm: Double, probability: Int)? {
            guard let i = times.firstIndex(where: { $0 >= t }) else { return nil }
            return (mm[i], probability.indices.contains(i) ? probability[i] : 0)
        }
    }

    static func parse(_ data: Data) throws -> [Series] {
        let json = try JSONSerialization.jsonObject(with: data)
        let objects = (json as? [[String: Any]]) ?? ((json as? [String: Any]).map { [$0] } ?? [])
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "GMT")
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return try objects.map { o in
            guard let m = o["minutely_15"] as? [String: Any], let t = m["time"] as? [String] else {
                throw RainError.malformed
            }
            let mm = (m["precipitation"] as? [Any] ?? []).map { ($0 as? Double) ?? 0 }
            let p = (m["precipitation_probability"] as? [Any] ?? []).map { ($0 as? Int) ?? 0 }
            return Series(times: t.compactMap { fmt.date(from: $0) }, mm: mm, probability: p)
        }
    }

    private static func slotString(_ d: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "GMT")
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let slot = (d.timeIntervalSince1970 / 900).rounded(.down) * 900
        return fmt.string(from: Date(timeIntervalSince1970: slot))
    }

    struct GridPoint: Hashable, Comparable {
        var lat: Double
        var lon: Double

        init(_ c: CLLocationCoordinate2D) {
            lat = (c.latitude * 100).rounded() / 100
            lon = (c.longitude * 100).rounded() / 100
        }

        static func < (a: GridPoint, b: GridPoint) -> Bool { (a.lat, a.lon) < (b.lat, b.lon) }
    }
}
