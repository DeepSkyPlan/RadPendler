import CoreLocation
import XCTest
@testable import RadPendler

final class BikeRouteTests: XCTestCase {
    /// Metres → coordinates around the office (x east, y north).
    private func c(_ x: Double, _ y: Double) -> CLLocationCoordinate2D {
        let f = Flat(latitude: 52.5)
        return CLLocationCoordinate2D(latitude: 52.5 + y / f.ky, longitude: 13.3 + x / f.kx)
    }

    func testCrossingSignalAndAlongRoad() {
        // Route: 1 km due north. A main road crosses it east–west at y = 300
        // (with a signal), a second main road runs beside it (x = 10) from y = 600 to 900.
        let route = stride(from: 0.0, through: 1000, by: 20).map { c(0, $0) }
        let data = RoadData(
            signals: [c(3, 302), c(-4, 296), c(500, 500)],   // two nodes of one junction + one far away
            roads: [.init(name: "B 1", points: [c(-300, 300), c(300, 300)]),
                    .init(name: "Clayallee", points: [c(10, 600), c(10, 900)])])
        let st = RouteAnalyzer.analyze(route, roads: data)
        XCTAssertEqual(st.crossings, ["B 1"], "riding beside Clayallee is not a crossing")
        XCTAssertEqual(st.signals, 1, "signal nodes of one junction count once")
        XCTAssertEqual(st.mainRoadMeters, 340, accuracy: 60)   // ~300 m beside Clayallee + ~40 m at the B 1
    }

    func testDualCarriagewayCountsOnce() {
        let route = stride(from: 0.0, through: 1000, by: 20).map { c(0, $0) }
        let data = RoadData(signals: [], roads: [
            .init(name: "Potsdamer Chaussee", points: [c(-300, 400), c(300, 400)]),
            .init(name: "Potsdamer Chaussee", points: [c(-300, 425), c(300, 425)]),
        ])
        XCTAssertEqual(RouteAnalyzer.analyze(route, roads: data).crossings.count, 1)
    }

    func testCacheBoxSurvivesFloatNoise() {
        let box = RoadDataStore.Box(around: [c(0, 0), CLLocationCoordinate2D(latitude: 52.536, longitude: 13.361),
                                             CLLocationCoordinate2D(latitude: 52.409, longitude: 13.23)])
        XCTAssertEqual(box.key, "52.40_13.20_52.55_13.40")
        let fromDisk = RoadDataStore.Box(south: 52.4, west: 13.2, north: 52.55, east: 13.4)
        XCTAssertTrue(fromDisk.contains(box))
    }

    func testBRouterParse() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "brouter_safety_route", withExtension: "json"))
        let r = try BRouterClient.parse(Data(contentsOf: url))
        XCTAssertEqual(r.distance, 32842)
        XCTAssertGreaterThan(r.coordinates.count, 500)
        XCTAssertEqual(r.coordinates.first!.latitude, 52.521, accuracy: 0.002)
        XCTAssertEqual(r.coordinates.last!.latitude, 52.391, accuracy: 0.002)
    }

    private func candidate(_ name: String, km: Double, signals: Int, crossings: Int, mainKm: Double) -> BikeCandidate {
        BikeCandidate(source: name, route: StreetRoute(distance: km * 1000, expectedTravelTime: 0, coordinates: []),
                      stats: BikeRouteStats(signals: signals, crossings: Array(repeating: "B 1", count: crossings),
                                            mainRoadMeters: mainKm * 1000))
    }

    func testPickFastestBalancedQuiet() {
        let s = PlanSettings()
        // Fastest is not the shortest here: 19.7 km with 45 lights beats
        // 19.5 km with 50 at 20 s each.
        let short = candidate("fastbike", km: 19.5, signals: 55, crossings: 18, mainKm: 13.5)
        let middle = candidate("trekking", km: 19.7, signals: 45, crossings: 14, mainKm: 9)
        let quiet = candidate("safety", km: 24.0, signals: 43, crossings: 12, mainKm: 7.6)
        let picked = BikeCandidate.pick([quiet, short, middle], settings: s)
        XCTAssertLessThan(middle.time(s), short.time(s))
        // fastbike is the shortest by distance, trekking the fastest overall.
        // The list comes back in the user's variant order, which ships as
        // optimal › schnellst › ruhigst › kürzest — so trekking (optimal and
        // schnellst) leads, then safety (ruhigst), then fastbike (kürzest).
        XCTAssertEqual(picked.map(\.0.source), ["trekking", "safety", "fastbike"])
        // safety has both the least disturbance and the fewest metres beside a
        // main road, so it carries both labels — one route, listed once.
        XCTAssertEqual(picked.map(\.1), [[.balanced, .fastest], [.quiet, .lowTraffic], [.shortest]])
        // Signal waits are part of the riding time: 45 × 20 s = 15 min.
        XCTAssertEqual(middle.time(s), s.bikeTime(19_700) + 900, accuracy: 1)
    }

    /// „ruhigst" und „verkehrsarm" fragen verschiedene Dinge: die eine, wo man
    /// am wenigsten *neben* Autos fährt, die andere, wo man ihretwegen am
    /// seltensten *anhalten* muss. Eine Strecke am Kanal entlang mit wenigen
    /// Kreuzungen gewinnt die zweite und verliert die erste.
    func testQuietAndLowTrafficAskDifferentQuestions() {
        let s = PlanSettings()
        // Wenig Halte, aber lange neben der Hauptstraße.
        let fewStops = candidate("verkehrsarm", km: 21, signals: 5, crossings: 2, mainKm: 12.0)
        // Abseits der Autos, dafür durch lauter kleine Kreuzungen.
        let calm = candidate("safety", km: 21, signals: 40, crossings: 15, mainKm: 2.0)
        let quick = candidate("fastbike", km: 19, signals: 25, crossings: 10, mainKm: 8.0)
        let picked = BikeCandidate.pick([fewStops, calm, quick], settings: s)
        let roles = Dictionary(uniqueKeysWithValues: picked.map { ($0.0.source, $0.1) })
        XCTAssertTrue(roles["verkehrsarm"]?.contains(.lowTraffic) ?? false,
                      "die wenigsten Stellen, an denen der Verkehr zum Halten zwingt")
        XCTAssertTrue(roles["safety"]?.contains(.quiet) ?? false, "die geringste Störung insgesamt")
        XCTAssertFalse(roles["safety"]?.contains(.lowTraffic) ?? true, "und eben nicht dasselbe")
        XCTAssertEqual(fewStops.stats?.stops, 7)
        XCTAssertEqual(calm.stats?.stops, 55)
    }

    /// Ohne OpenStreetMap-Daten lässt sich nur die Zeit beurteilen — dann
    /// vertritt BRouters eigenes Profil die Rolle.
    func testWithoutRoadDataTheProfileNamesTheVariant() {
        let plain = { (name: String, km: Double) in
            BikeCandidate(source: name, route: StreetRoute(distance: km * 1000, expectedTravelTime: 0,
                                                           coordinates: [], signals: 0), stats: nil)
        }
        let picked = BikeCandidate.pick([plain("trekking", 20), plain("safety", 21),
                                         plain("verkehrsarm", 22)], settings: PlanSettings())
        let roles = Dictionary(uniqueKeysWithValues: picked.map { ($0.0.source, $0.1) })
        XCTAssertTrue(roles["safety"]?.contains(.quiet) ?? false)
        XCTAssertTrue(roles["verkehrsarm"]?.contains(.lowTraffic) ?? false)
    }

    /// Eine Linie, die alles gewinnt, steht **einmal** da und trägt alle ihre
    /// Namen. Die schlechtere verschwindet deswegen aber nicht — sie ist ein
    /// anderer Weg und bleibt als „Alternative" wählbar. Bis 1.3 fiel sie
    /// heraus, und unter dem Rad-Kasten standen zwei Punkte, wo neun Routen
    /// angefragt worden waren.
    func testTheWinnerIsListedOnceAndTheOthersStay() {
        let best = candidate("safety", km: 19, signals: 10, crossings: 2, mainKm: 1)
        let worse = candidate("fastbike", km: 20, signals: 50, crossings: 18, mainKm: 13)
        let picked = BikeCandidate.pick([worse, best], settings: PlanSettings())
        XCTAssertEqual(picked.count, 2, "beide Wege bleiben wählbar")
        XCTAssertEqual(picked[0].0.source, "safety", "die benannte steht vorn")
        XCTAssertEqual(picked[0].1, BikeVariant.defaultOrder, "all five labels, in the user's order")
        XCTAssertEqual(picked[1].0.source, "fastbike")
        XCTAssertTrue(picked[1].1.isEmpty, "ohne Namen, weil sie in keiner Hinsicht die beste ist")
    }

    func testTheVariantOrderTravelsThroughToWhatIsSuggested() {
        let short = candidate("fastbike", km: 19.5, signals: 55, crossings: 18, mainKm: 13.5)
        let quiet = candidate("safety", km: 24.0, signals: 43, crossings: 12, mainKm: 7.6)
        var s = PlanSettings()
        s.bikeVariantOrder = [.shortest, .quiet, .balanced, .fastest]
        let picked = BikeCandidate.pick([quiet, short], settings: s)
        XCTAssertEqual(picked.first?.0.source, "fastbike")
        XCTAssertEqual(picked.first?.1.first, .shortest)
    }

    // MARK: Car alternatives

    private func carLine(_ meters: Double, minutes: Double, signals: Int) -> CarCandidate {
        let route = StreetRoute(distance: meters, expectedTravelTime: minutes * 60,
                                coordinates: [c(0, 0), c(0, meters)])
        return CarCandidate(route: route,
                            stats: BikeRouteStats(signals: signals, crossings: [], mainRoadMeters: 0))
    }

    func testCarRolesGoToTheLineThatWinsThem() {
        let motorway = carLine(30_000, minutes: 28, signals: 12)   // long, quick, few lights
        let town = carLine(21_000, minutes: 35, signals: 41)       // short, slow, many lights
        let middle = carLine(24_000, minutes: 31, signals: 5)      // fewest lights
        let picked = CarCandidate.pick([town, motorway, middle])
        // "optimal" ships first, so the line that wins it leads the list.
        XCTAssertEqual(picked.map(\.1), [[.balanced, .fastest], [.shortest], [.fewSignals]])
        XCTAssertEqual(picked[0].0.route.distance, 30_000, "the fastest comes first — it is the default")
        XCTAssertEqual(picked[1].0.route.distance, 21_000)
        XCTAssertEqual(picked[2].0.signals, 5)
    }

    func testOneCarLineIsJustTheFastest() {
        let only = carLine(26_000, minutes: 33, signals: 20)
        XCTAssertEqual(CarCandidate.pick([only]).map(\.1), [[.fastest]],
                       "four labels on a single route say nothing")
    }

    func testCarWithoutOpenStreetMapDataStillSeparatesQuickAndShort() {
        let a = CarCandidate(route: StreetRoute(distance: 30_000, expectedTravelTime: 28 * 60, coordinates: []), stats: nil)
        let b = CarCandidate(route: StreetRoute(distance: 21_000, expectedTravelTime: 35 * 60, coordinates: []), stats: nil)
        XCTAssertEqual(CarCandidate.pick([a, b]).map(\.1), [[.fastest], [.shortest]])
    }
}

extension BikeRouteTests {
    func testTheCarOffersEveryLineAppleFound() {
        var s = PlanSettings()
        s.signalWaitSeconds = 20
        // Motorway: quickest, but twelve junctions. Town: shortest and slow
        // with forty. Middle: a minute slower than the motorway and five
        // junctions — the best balance, and the calmest.
        let motorway = carLine(30_000, minutes: 28, signals: 12)
        let town = carLine(21_000, minutes: 35, signals: 41)
        let middle = carLine(24_000, minutes: 29, signals: 5)
        let picked = CarCandidate.pick([motorway, town, middle], settings: s)
        XCTAssertEqual(picked.count, 3, "no line Apple offered may disappear")
        XCTAssertEqual(Set(picked.flatMap(\.1)), Set([.fastest, .shortest, .balanced, .fewSignals]))
        XCTAssertEqual(picked.first?.1.first, .balanced, "optimal ships first, as it does for the bike")
        XCTAssertEqual(picked.first?.0.route.distance, 24_000)
    }

    func testALineWithoutARoleIsStillOffered() {
        let best = carLine(20_000, minutes: 25, signals: 5)
        let nothing = carLine(26_000, minutes: 33, signals: 30)
        let picked = CarCandidate.pick([best, nothing], settings: PlanSettings())
        XCTAssertEqual(picked.count, 2)
        XCTAssertEqual(picked.last?.1, [.alternative], "shown as an alternative rather than dropped")
    }

    // MARK: Höhenmeter

    /// BRouter rechnet den Anstieg selbst aus und nennt ihn `filtered ascend` —
    /// „filtered", weil das Rauschen des Höhenmodells herausgerechnet ist.
    /// Ungefiltert summiert jede Unebenheit der Messung ein paar Zentimeter,
    /// und aus einer flachen Berliner Strecke werden hundert Höhenmeter.
    func testTheAscentComesFromTheRouterAndIsFiltered() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "brouter_safety_route", withExtension: "json"))
        let route = try BRouterClient.parse(try Data(contentsOf: url))
        XCTAssertEqual(try XCTUnwrap(route.ascent), 46, accuracy: 0.5)

        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let feature = try XCTUnwrap((raw["features"] as? [[String: Any]])?.first)
        let coords = try XCTUnwrap((feature["geometry"] as? [String: Any])?["coordinates"] as? [[Double]])
        let unfiltered = try XCTUnwrap(BRouterClient.climbed(coords))
        XCTAssertGreaterThan(unfiltered, 46, "ungefiltert ist es immer mehr — das ist der Punkt")
    }

    /// Ohne Höhen in den Punkten gibt es keine Antwort. Eine Strecke ohne
    /// Höhen ist nicht flach, sie ist unbekannt.
    func testARouteWithoutHeightsHasNoAscent() {
        XCTAssertNil(BRouterClient.climbed([[13.4, 52.5], [13.41, 52.51]]))
        XCTAssertEqual(BRouterClient.climbed([[13.4, 52.5, 30], [13.41, 52.51, 40], [13.42, 52.52, 35]]), 10,
                       "nur das Bergauf zählt, das Bergab nicht dagegen")
    }

    /// Apple Karten liefert keine Höhen. Diese Linie darf dadurch weder
    /// gewinnen noch verlieren — für die Bewertung bekommt sie den
    /// Durchschnitt der bekannten, angezeigt wird weiter nichts.
    func testAnUnknownAscentIsNeitherRewardedNorPunished() {
        func candidate(_ name: String, ascent: Double?) -> BikeCandidate {
            BikeCandidate(source: name,
                          route: StreetRoute(distance: 10_000, expectedTravelTime: 1800, coordinates: [],
                                             ascent: ascent),
                          stats: nil)
        }
        let levelled = BikeCandidate.levelled([candidate("Apple", ascent: nil),
                                               candidate("a", ascent: 20),
                                               candidate("b", ascent: 60)])
        XCTAssertEqual(levelled[0].ascent, 40, "der Durchschnitt der beiden bekannten")
        XCTAssertNil(levelled[0].route.ascent, "gemessen ist weiterhin nichts")
        XCTAssertEqual(levelled[1].ascent, 20)

        // Und der Anstieg kostet Zeit: 40 m × 5 s sind gut drei Minuten.
        var s = PlanSettings()
        s.signalWaitSeconds = 0
        let flat = candidate("flach", ascent: 0)
        let hilly = candidate("bergig", ascent: 100)
        XCTAssertEqual(BikeCandidate.levelled([flat, hilly])[1].time(s) - flat.time(s), 500, accuracy: 1)
    }

    /// Bei gleicher Länge gewinnt die flachere Strecke das Rennen um
    /// „schnellst" — vorher entschied allein die Länge.
    func testTheFlatterRouteWinsOnTime() {
        var s = PlanSettings()
        s.signalWaitSeconds = 0
        func candidate(_ name: String, km: Double, ascent: Double) -> BikeCandidate {
            BikeCandidate(source: name,
                          route: StreetRoute(distance: km * 1000, expectedTravelTime: 0, coordinates: [],
                                             ascent: ascent),
                          stats: nil)
        }
        let over = candidate("über den Berg", km: 10, ascent: 120)
        let around = candidate("drumherum", km: 10.5, ascent: 5)
        let picked = BikeCandidate.pick([over, around], settings: s)
        let fastest = picked.first { $0.1.contains(.fastest) }
        XCTAssertEqual(fastest?.0.source, "drumherum", "der halbe Kilometer Umweg ist billiger als 115 Höhenmeter")
        let shortest = picked.first { $0.1.contains(.shortest) }
        XCTAssertEqual(shortest?.0.source, "über den Berg", "kürzest bleibt kürzest")
    }

    // MARK: Wie viele Radrouten der Bildschirm zeigt

    private func line(_ name: String, km: Double, seconds: Double, offset: Double = 0,
                      disturbance: Double? = nil, stops: Int = 0) -> BikeCandidate {
        // Eine gerade Linie nach Osten, um `offset` Grad nach Norden versetzt.
        let points = (0...20).map {
            CLLocationCoordinate2D(latitude: 52.5 + offset, longitude: 13.30 + Double($0) * km / 20 / 68.0)
        }
        var stats: BikeRouteStats?
        if let disturbance {
            // mainRoadMeters trägt die Störung, damit `disturbance` stimmt.
            stats = BikeRouteStats(signals: 0, crossings: [], mainRoadMeters: disturbance, signalPoints: [])
        }
        var c = BikeCandidate(source: name,
                              route: StreetRoute(distance: km * 1000, expectedTravelTime: seconds,
                                                 coordinates: points, ascent: 0),
                              stats: stats)
        if stats != nil { c.stats?.crossings = Array(repeating: "x", count: stops) }
        return c
    }

    /// Mehrere Profile liefern oft dieselbe Straße. Zwei gleiche Linien sind
    /// keine zwei Möglichkeiten.
    func testIdenticalLinesCountOnce() {
        let a = line("trekking", km: 10, seconds: 1800)
        let b = line("fastbike", km: 10.05, seconds: 1800)      // dieselbe Straße
        let c = line("umweg", km: 10, seconds: 1800, offset: 0.02)  // gut 2 km daneben
        XCTAssertTrue(BikeCandidate.sameLine(a.route, b.route))
        XCTAssertFalse(BikeCandidate.sameLine(a.route, c.route))
        XCTAssertEqual(BikeCandidate.distinct([a, b, c]).count, 2)
        XCTAssertEqual(BikeCandidate.distinct([a, b, c]).map { $0.source }, ["trekking", "umweg"])
    }

    /// Der Grund, aus dem unter dem Rad-Kasten oft nur zwei Punkte standen:
    /// eine Linie ohne Rolle fiel ganz heraus. Die Namen bleiben wahr — die
    /// beste ist die beste —, aber jeder andere Weg bleibt wählbar.
    func testEveryDistinctLineStaysChoosable() {
        var s = PlanSettings()
        s.signalWaitSeconds = 0
        // Die erste Linie ist in jeder Hinsicht die beste; früher blieb davon
        // ein Kasten übrig und die anderen vier verschwanden.
        let best = line("best", km: 9.0, seconds: 0, offset: 0.000, disturbance: 100)
        let two = line("zwei", km: 9.5, seconds: 0, offset: 0.02, disturbance: 200)
        let three = line("drei", km: 10.0, seconds: 0, offset: 0.04, disturbance: 300)
        let four = line("vier", km: 10.5, seconds: 0, offset: 0.06, disturbance: 400)
        let picked = BikeCandidate.pick([best, two, three, four], settings: s)
        XCTAssertEqual(picked.count, 4, "vier verschiedene Wege bleiben vier Möglichkeiten")
        XCTAssertEqual(picked.first?.0.source, "best", "die benannte steht vorn")
        XCTAssertEqual(Set(picked[0].1).count, 5, "und trägt alle fünf Namen, weil sie alle gewinnt")
        XCTAssertTrue(picked.dropFirst().allSatisfy { $0.1.isEmpty }, "die übrigen tragen keinen")
    }

    /// Eine namenlose Linie heißt „Alternative" — nicht „Route" und nicht leer.
    func testAnUnlabelledLineIsCalledAlternative() {
        let named = BikeRouteInfo(variants: [.quiet, .fastest], stats: nil, source: "safety")
        XCTAssertEqual(named.shortTitle, "ruhigst")
        let plain = BikeRouteInfo(variants: [], stats: nil, source: "trekking")
        XCTAssertEqual(plain.shortTitle, "Alternative")
        XCTAssertEqual(plain.title, "Alternative")
    }
}
