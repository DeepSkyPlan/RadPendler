import CoreLocation
import XCTest
@testable import RadPendler

/// Was in den UserDefaults und in iCloud liegt, hat irgendeine Fassung der App
/// geschrieben — und jede spätere muss es lesen, ohne zu stolpern und ohne
/// etwas zu verlieren. Hier liegt zu jedem reisenden Schlüssel eine Probe je
/// Format, das je ausgeliefert wurde.
///
/// **Wer ein Feld hinzufügt oder ändert: die Probe der bisherigen Fassung
/// bleibt stehen, eine neue kommt dazu.** Schlägt ein Test hier fehl, wäre das
/// auf dem Telefon eine leere Fahrtenliste oder ein Absturz beim Start
/// (03.10.2026) gewesen — siehe `Stored`.
final class StoredFormatTests: XCTestCase {
    private let noon = Date(timeIntervalSince1970: 1_780_000_000)

    // MARK: Proben

    /// 23.–25.09.2026: vor `pausedSeconds`, `standingInPause`, `appVersion`,
    /// `motorcycle`, `mix`, `plannedMeters`, `plannedSignals`.
    private let rideFirst = #"{"id":"8D7A1E8E-6C3B-4C61-9E0B-5A4B2F1D3C11","started":780000000,"ended":780001500,"origin":"A","destination":"B","mode":"bike","meters":8000,"movingSeconds":1300,"maxKmh":31.5,"signalStops":4,"otherStops":1,"signalWaitTotal":95,"plannedSeconds":1500}"#
    /// 1.11 (51): alles, was es gibt.
    private let ride111 = #"{"appVersion":"1.11 (51)","destination":"B","ended":780101500,"id":"8D7A1E8E-6C3B-4C61-9E0B-5A4B2F1D3C12","maxKmh":31.5,"meters":8000,"mix":{"meters":["main",1200,"side",300.5]},"mode":"bike","motorcycle":false,"movingSeconds":1300,"origin":"A","otherStops":1,"pausedSeconds":120,"plannedMeters":7900,"plannedSeconds":1500,"plannedSignals":9,"pointCount":812,"signalStops":4,"signalWaitTotal":95,"standingInPause":true,"started":780100000}"#
    /// 1.15: eine Autofahrt mit Apples Ansage (`appleSeconds`).
    private let ride115 = #"{"appVersion":"1.15 (55)","appleSeconds":1500,"destination":"B","ended":780301800,"id":"8D7A1E8E-6C3B-4C61-9E0B-5A4B2F1D3C14","maxKmh":95,"meters":20000,"mode":"car","movingSeconds":1600,"origin":"A","otherStops":1,"pausedSeconds":0,"plannedMeters":20000,"plannedSeconds":1700,"plannedSignals":9,"pointCount":812,"signalStops":4,"signalWaitTotal":95,"standingInPause":true,"started":780300000}"#
    /// Eine Fassung, die es noch nicht gibt: ein Feld, das niemand kennt, eine
    /// Straßenklasse, die niemand kennt, und ein bekanntes Feld in neuem Typ.
    private let rideLater = #"{"id":"8D7A1E8E-6C3B-4C61-9E0B-5A4B2F1D3C13","started":780200000,"ended":780201500,"origin":"A","destination":"B","mode":"hoverboard","meters":8000,"movingSeconds":1300,"maxKmh":31.5,"signalStops":4,"otherStops":1,"signalWaitTotal":95,"pausedSeconds":0,"pointCount":3,"motorcycle":"ja","neuesFeld":{"x":[1,2]},"mix":{"meters":["main",1200,"tunnel",50]}}"#

    private func rides(_ json: String...) -> [Ride]? {
        RideStore.decode(Data("[\(json.joined(separator: ","))]".utf8))
    }

    // MARK: Lesen

    func testEveryShippedRideFormatStillReads() throws {
        let list = try XCTUnwrap(rides(rideFirst, ride111, rideLater))
        XCTAssertEqual(list.count, 3, "keine Fahrt darf an ihrem Format hängen bleiben")
        let first = try XCTUnwrap(list.last)
        XCTAssertEqual(first.pausedSeconds, 0, "ein Feld, das später kam, fehlt in der alten Fahrt — und ist dann 0")
        XCTAssertEqual(first.pointCount, 0)
        XCTAssertNil(first.mix)
        let full = list[1]
        XCTAssertEqual(full.pausedSeconds, 120)
        XCTAssertEqual(full.appVersion, "1.11 (51)")
        XCTAssertEqual(full.mix?[.side], 300.5)
        let later = list[0]
        XCTAssertNil(later.motorcycle, "ein Feld in unbekanntem Typ ist wie ein fehlendes")
        XCTAssertEqual(later.mix?.total, 1200, "die unbekannte Straßenklasse fällt allein heraus")
        XCTAssertNil(later.travelMode)
    }

    /// Apples Ansage kam mit 1.15 dazu: ältere Fahrten haben keine und tragen
    /// zum Faktor nichts bei; die neue übersteht Schreiben und Lesen.
    func testApplesTimeIsOptional() throws {
        let list = try XCTUnwrap(rides(rideFirst, ride111, ride115))
        XCTAssertEqual(list.count, 3)
        let car = try XCTUnwrap(list.first { $0.mode == "car" })
        XCTAssertEqual(car.appleSeconds, 1500)
        XCTAssertEqual(car.appleFactor ?? 0, 1.2, accuracy: 0.001)
        XCTAssertTrue(list.filter { $0.mode != "car" }.allSatisfy { $0.appleSeconds == nil && $0.appleFactor == nil })
        let packed = try XCTUnwrap(RideStore.encode(list))
        XCTAssertEqual(RideStore.decode(packed), list)
        XCTAssertEqual(car.sanitized?.appleSeconds, 1500)
    }

    func testOneUnreadableRideDoesNotTakeTheListWithIt() throws {
        let list = try XCTUnwrap(rides(rideFirst, #"{"id":"kaputt"}"#, "7", ride111))
        XCTAssertEqual(list.count, 2)
        XCTAssertNil(RideStore.decode(Data("kaputt".utf8)), "gar keine Liste ist etwas anderes als eine leere")
    }

    func testTheCompressedListReadsLikeThePlainOne() throws {
        let list = try XCTUnwrap(rides(rideFirst, ride111))
        let packed = try XCTUnwrap(RideStore.encode(list))
        XCTAssertEqual(RideStore.decode(packed), list)
    }

    func testTracksOfEveryAgeRead() throws {
        // Vor 1.9.2, mit einem Punkt, den es so nie gab, und einem Halt ohne Kennung.
        let old = #"{"id":"8D7A1E8E-6C3B-4C61-9E0B-5A4B2F1D3C11","points":[{"lat":52.5,"lon":13.4,"t":780000000,"v":5},{"kaputt":1}],"stops":[{"lat":52.5,"lon":13.4,"start":780000100,"seconds":30,"atSignal":true}]}"#
        let t = try JSONDecoder().decode(RideTrack.self, from: Data(old.utf8))
        XCTAssertEqual(t.points.count, 1)
        XCTAssertEqual(t.stops.count, 1)
        XCTAssertEqual(t.planned, [])
        // 1.11: mit Protokoll und Neuplanungen.
        let new = #"{"events":[{"kind":"start","lat":52.5,"lon":13.4,"t":780000000}],"id":"8D7A1E8E-6C3B-4C61-9E0B-5A4B2F1D3C12","planned":[{"lat":52.5,"lon":13.4}],"points":[{"a":8,"h":41,"lat":52.5,"lon":13.4,"t":780000000,"v":5}],"routes":[[{"lat":52.5,"lon":13.4}],[{"lat":52.51,"lon":13.41}]],"stops":[{"atSignal":true,"id":"8D7A1E8E-6C3B-4C61-9E0B-5A4B2F1D3C99","lat":52.5,"lon":13.4,"seconds":30,"start":780000100}]}"#
        let n = try JSONDecoder().decode(RideTrack.self, from: Data(new.utf8))
        XCTAssertEqual(n.routes?.count, 2)
        XCTAssertEqual(n.events?.first?.kind, "start")
        XCTAssertEqual(n.points.first?.a, 8)
        // Und zurück: was diese Fassung schreibt, liest sie wieder.
        XCTAssertEqual(try JSONDecoder().decode(RideTrack.self, from: XCTUnwrap(Stored.encode(n))), n)
    }

    func testTheSettingsListsOfEveryAgeRead() throws {
        // Gelernte Ampeln: vor den Vorbeifahrten, mit ihnen, und ein Eintrag aus Unsinn.
        let signals: [LearnedSignal] = try XCTUnwrap(Stored.list(from: Data(#"[{"lat":52.5,"lon":13.4,"stops":4,"totalWait":80,"lastSeen":760000000},{"lastSeen":780000000,"lat":52.6,"lon":13.5,"passes":9,"stops":4,"totalWait":80},{"lat":"oben"}]"#.utf8)))
        XCTAssertEqual(signals.count, 2)
        XCTAssertNil(signals[0].passes)
        // Adressen: vor 0.9 ohne Postleitzahl und Ort.
        let places: [PlaceUse] = try XCTUnwrap(Stored.list(from: Data(#"[{"place":{"name":"Musterstraße 1, Berlin","latitude":52.5,"longitude":13.4},"count":3,"lastUsed":760000000},{"count":1,"lastUsed":780000000,"place":{"latitude":52.6,"locality":"Berlin","longitude":13.5,"name":"Beispielweg 2","postalCode":"10115"}}]"#.utf8)))
        XCTAssertEqual(places.count, 2)
        XCTAssertEqual(places[1].place.postalCode, "10115")
        // Linien mit und ohne Entscheidung.
        let lines: [BikeLine] = try XCTUnwrap(Stored.list(from: Data(#"[{"name":"S7","lastSeen":760000000},{"allowed":false,"lastSeen":780000000,"name":"M11"}]"#.utf8)))
        XCTAssertEqual(lines.map(\.allowed), [nil, false])
        // Fixpunkte je Strecke (seit 1.9.1).
        let ways: [RouteWaypoints] = try XCTUnwrap(Stored.list(from: Data(#"[{"a":{"lat":52.5,"lon":13.4},"b":{"lat":52.4,"lon":13.2},"points":[{"latitude":52.45,"longitude":13.3,"name":"S Ostkreuz"}]}]"#.utf8)))
        XCTAssertEqual(ways.first?.points.count, 1)
        // Grabsteine (seit 1.4).
        let stones = try JSONDecoder().decode(Tombstones.self, from: Data(#"{"stones":{"ride:8D7A1E8E-6C3B-4C61-9E0B-5A4B2F1D3C11":780000000}}"#.utf8))
        XCTAssertTrue(stones.has("ride:8D7A1E8E-6C3B-4C61-9E0B-5A4B2F1D3C11"))
    }

    /// Die Probe aus der anderen Richtung: was die Einstellungen aus einem
    /// Speicher machen, in dem die Listen einer alten Fassung liegen.
    func testSettingsLoadOldListsWithOneBadEntryEach() {
        let d = UserDefaults(suiteName: "stored-\(UUID())")!
        d.set(Data(#"[{"lat":52.5,"lon":13.4,"stops":4,"totalWait":80,"lastSeen":760000000},{"lat":"oben"}]"#.utf8), forKey: "learnedSignals")
        d.set(Data(#"[{"place":{"name":"Musterstraße 1","latitude":52.5,"longitude":13.4},"count":3,"lastUsed":760000000},17]"#.utf8), forKey: "placeHistory")
        let settings = AppSettings(defaults: d)
        XCTAssertEqual(settings.learnedSignals.count, 1)
        XCTAssertEqual(settings.placeHistory.count, 1)
    }

    // MARK: Schreiben

    func testWritingIsTheSameBytesEveryTime() throws {
        let signal = LearnedSignal(lat: 52.5, lon: 13.25, stops: 4, totalWait: 80,
                                   lastSeen: Date(timeIntervalSinceReferenceDate: 780_000_000), passes: 9)
        XCTAssertEqual(String(data: try XCTUnwrap(Stored.encode([signal])), encoding: .utf8),
                       #"[{"lastSeen":780000000,"lat":52.5,"lon":13.25,"passes":9,"stops":4,"totalWait":80}]"#)
    }

    /// Die Straßenanteile stehen seit 1.0 als Paare in einer Liste — das
    /// bleibt so, nur in fester Reihenfolge.
    func testTheRoadMixKeepsItsWireFormat() throws {
        let mix = RoadMix(meters: [.side: 300.5, .main: 1200])
        XCTAssertEqual(String(data: try XCTUnwrap(Stored.encode(mix)), encoding: .utf8),
                       #"{"meters":["main",1200,"side",300.5]}"#)
        XCTAssertEqual(try JSONDecoder().decode(RoadMix.self, from: XCTUnwrap(Stored.encode(mix))), mix)
    }

    // MARK: Zusammenführen — wiederholbar, und auf beiden Geräten dasselbe

    private func ride(_ id: UUID, day: Int, paused: TimeInterval = 0, repaired: Bool? = nil) -> Ride {
        var r = Ride(id: id, started: noon.addingTimeInterval(Double(day) * 86_400),
                     ended: noon.addingTimeInterval(Double(day) * 86_400 + 1200),
                     origin: "A", destination: "B", mode: TravelMode.bike.rawValue, meters: 8000,
                     movingSeconds: 1100, maxKmh: 30, signalStops: 3, otherStops: 0,
                     signalWaitTotal: 60, plannedSeconds: nil)
        r.pausedSeconds = paused
        r.standingInPause = repaired
        return r
    }

    func testMergingRidesIsRepeatableAndTheSameFromBothSides() {
        let (a, b, c) = (UUID(), UUID(), UUID())
        let phone = [ride(a, day: 0, paused: 700, repaired: true), ride(b, day: -1)]
        let pad = [ride(a, day: 0, paused: 600), ride(c, day: -2)]
        let one = RideStore.merge(phone, pad)
        XCTAssertEqual(one, RideStore.merge(pad, phone), "wer fragt, darf nichts ändern")
        XCTAssertEqual(RideStore.merge(one, one), one)
        XCTAssertEqual(RideStore.merge(one, pad), one)
        XCTAssertEqual(one.count, 3)
        XCTAssertEqual(one.first?.pausedSeconds, 700, "die nachgerechnete Fassung bleibt")
    }

    func testMergingSignalsIsRepeatableAndTheSameFromBothSides() {
        let here = LearnedSignal(lat: 52.5, lon: 13.4, stops: 50, totalWait: 1000, lastSeen: noon, passes: 100)
        let there = LearnedSignal(lat: 52.5001, lon: 13.4, stops: 100, totalWait: 2000,
                                  lastSeen: noon.addingTimeInterval(-86_400), passes: 200)
        let only = LearnedSignal(lat: 52.6, lon: 13.5, stops: 1, totalWait: 20, lastSeen: noon, passes: 3)
        let order: (LearnedSignal, LearnedSignal) -> Bool = { $0.lat < $1.lat }
        let one = LearnedSignal.merging([here], [there, only]).sorted(by: order)
        XCTAssertEqual(one, LearnedSignal.merging([there, only], [here]).sorted(by: order))
        XCTAssertEqual(LearnedSignal.merging(one, one), one)
        XCTAssertEqual(one.first, here, "der jüngere Stand gewinnt — sonst käme jede Halbierung vom anderen Gerät zurück")
    }

    func testMergingPlacesIsRepeatableAndTheSameFromBothSides() {
        let a = Place(name: "Musterstraße 1", latitude: 52.5, longitude: 13.4)
        var renamed = a
        renamed.name = "Musterstr. 1"
        let phone = [PlaceUse(place: a, count: 5, lastUsed: noon)]
        let pad = [PlaceUse(place: renamed, count: 3, lastUsed: noon)]
        let one = phone.merging(pad)
        XCTAssertEqual(one, pad.merging(phone))
        XCTAssertEqual(one.merging(one), one)
    }

    /// Der Weg, den iCloud wirklich nimmt: beide Geräte führen zusammen, und
    /// danach darf keines mehr etwas hinauszuschicken haben.
    func testAfterOneRoundBothDevicesAgree() throws {
        let (a, b) = (UUID(), UUID())
        let cases: [(String, Data?, Data?)] = [
            (CloudStore.ridesKey,
             RideStore.encode([ride(a, day: 0, paused: 700, repaired: true), ride(b, day: -1)]),
             RideStore.encode([ride(b, day: -1), ride(a, day: 0, paused: 600)])),
            ("learnedSignals",
             Stored.encode([LearnedSignal(lat: 52.5, lon: 13.4, stops: 2, totalWait: 40, lastSeen: noon, passes: 8),
                            LearnedSignal(lat: 52.6, lon: 13.5, stops: 1, totalWait: 20, lastSeen: noon, passes: 3)]),
             Stored.encode([LearnedSignal(lat: 52.6, lon: 13.5, stops: 1, totalWait: 20, lastSeen: noon, passes: 3),
                            LearnedSignal(lat: 52.5, lon: 13.4, stops: 3, totalWait: 60, lastSeen: noon, passes: 12)])),
            ("placeHistory",
             Stored.encode([PlaceUse(place: Place(name: "A", latitude: 52.5, longitude: 13.4), count: 5, lastUsed: noon)]),
             Stored.encode([PlaceUse(place: Place(name: "B", latitude: 52.6, longitude: 13.5), count: 1, lastUsed: noon)])),
        ]
        for (key, phone, pad) in cases {
            let (phone, pad) = (try XCTUnwrap(phone), try XCTUnwrap(pad))
            let onPhone = try XCTUnwrap(CloudStore.merged(key, local: phone, cloud: pad))
            let onPad = try XCTUnwrap(CloudStore.merged(key, local: pad, cloud: onPhone))
            XCTAssertTrue(CloudStore.sameContent(key, onPad, onPhone), "\(key): das zweite Gerät hätte zurückgeschrieben")
            let again = try XCTUnwrap(CloudStore.merged(key, local: onPhone, cloud: onPad))
            XCTAssertTrue(CloudStore.sameContent(key, again, onPad), "\(key): und das erste gleich wieder")
        }
    }

    func testTheSameListInAnotherOrderOrPackingIsNoChange() throws {
        let list = [ride(UUID(), day: 0), ride(UUID(), day: -1)]
        let packed = try XCTUnwrap(RideStore.encode(list))
        let plain = try XCTUnwrap(Stored.encode(Array(list.reversed())))
        XCTAssertNotEqual(packed, plain)
        XCTAssertTrue(CloudStore.sameContent(CloudStore.ridesKey, packed, plain))
        XCTAssertFalse(CloudStore.sameContent(CloudStore.ridesKey, packed, try XCTUnwrap(RideStore.encode([list[0]]))))
        XCTAssertFalse(CloudStore.sameContent(CloudStore.ridesKey, packed, Data("kaputt".utf8)))
    }

    // MARK: Grenzen — nichts, was hereinkommt, bringt die Rechnung zum Absturz

    func testSignalsWithAbsurdValuesAreCutDownBeforeAnyArithmetic() throws {
        let json = #"[{"lat":52.5,"lon":13.4,"stops":9223372036854775807,"totalWait":1e300,"lastSeen":780000000,"passes":9223372036854775807},{"lat":1e300,"lon":13.4,"stops":1,"totalWait":20,"lastSeen":780000000},{"lat":52.6,"lon":13.5,"stops":-5,"totalWait":-1,"lastSeen":780000000,"passes":-9223372036854775808}]"#
        let raw: [LearnedSignal] = try XCTUnwrap(Stored.list(from: Data(json.utf8)))
        XCTAssertEqual(raw.count, 3)
        let list = LearnedSignal.healed(raw)
        XCTAssertEqual(list.count, 2, "ohne brauchbare Lage kein Eintrag")
        for s in list {
            XCTAssertLessThanOrEqual(s.passCount, LearnedSignal.memory)
            XCTAssertGreaterThanOrEqual(s.stops, 0)
            XCTAssertLessThanOrEqual(s.totalWait, Double(s.stops) * LearnedSignal.longestWait)
            XCTAssertTrue(s.expectedWait(default: 20).isFinite)
            XCTAssertFalse(s.id.isEmpty)
        }
        // Und der ungeheilte Stand durch jede Tür, durch die er kommen kann.
        var merged = LearnedSignal.merging(raw, raw)
        let here = CLLocationCoordinate2D(latitude: 52.5, longitude: 13.4)
        merged = LearnedSignal.recording(merged, at: here, waited: 30)
        merged = LearnedSignal.passing(merged, at: here)
        XCTAssertTrue(merged.allSatisfy { $0.passCount <= LearnedSignal.memory })
        let d = UserDefaults(suiteName: "stored-\(UUID())")!
        d.set(Data(json.utf8), forKey: "learnedSignals")
        XCTAssertEqual(AppSettings(defaults: d).learnedSignals.count, 2)
    }

    func testRidesWithAbsurdValuesAreCutDownOrDropped() throws {
        let huge = #"{"id":"8D7A1E8E-6C3B-4C61-9E0B-5A4B2F1D3C21","started":780000000,"ended":780001500,"origin":"A","destination":"B","mode":"bike","meters":1e300,"movingSeconds":-4,"maxKmh":1e300,"signalStops":9223372036854775807,"otherStops":9223372036854775807,"signalWaitTotal":1e300,"pausedSeconds":1e300,"pointCount":-1,"plannedSignals":9223372036854775807}"#
        let never = #"{"id":"8D7A1E8E-6C3B-4C61-9E0B-5A4B2F1D3C22","started":1e300,"ended":1e300,"origin":"A","destination":"B","mode":"bike","meters":1,"movingSeconds":1,"maxKmh":1,"signalStops":1,"otherStops":1,"signalWaitTotal":1}"#
        let list = try XCTUnwrap(rides(huge, huge.replacingOccurrences(of: "3C21", with: "3C23"), never))
        XCTAssertEqual(list.count, 2, "eine Fahrt zu einer Zeit, die es nicht gibt, fällt heraus")
        let r = list[0]
        XCTAssertEqual(r.signalStops, Ride.maxStops)
        XCTAssertEqual(r.meters, Ride.maxMeters)
        XCTAssertEqual(r.movingSeconds, 0)
        XCTAssertEqual(r.pointCount, 0)
        // Alles, was über die Liste summiert, ohne Überlauf.
        XCTAssertEqual(r.stops, 2 * Ride.maxStops)
        let month = try XCTUnwrap(Ride.grouped(list).first?.months.first)
        XCTAssertEqual(month.signalStops, 2 * Ride.maxStops)
        XCTAssertTrue(month.averageKmh.isFinite)
        _ = Int(r.meters) + Int(r.seconds) + Int(r.maxKmh)
    }

    func testPlacesAndPlainNumbersAreCutDown() throws {
        let json = #"[{"place":{"name":"A","latitude":52.5,"longitude":13.4},"count":9223372036854775807,"lastUsed":780000000},{"place":{"name":"B","latitude":1e300,"longitude":13.4},"count":1,"lastUsed":780000000}]"#
        let raw: [PlaceUse] = try XCTUnwrap(Stored.list(from: Data(json.utf8)))
        let merged = raw.merging(raw)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].count, PlaceUse.maxCount)
        XCTAssertEqual(raw.recording(raw[0].place)[0].count, PlaceUse.maxCount, "und +1 läuft nicht über")

        let d = UserDefaults(suiteName: "stored-\(UUID())")!
        d.set(Int.max, forKey: "prepMinutes")
        d.set(Int.min, forKey: "parkingMinutes")
        d.set(1e300, forKey: "autoStopMinutes")
        d.set(Data(json.utf8), forKey: "placeHistory")
        let settings = AppSettings(defaults: d)
        XCTAssertEqual(settings.prepMinutes, AppSettings.numberLimit)
        XCTAssertEqual(settings.parkingMinutes, -AppSettings.numberLimit)
        XCTAssertEqual(settings.autoStopMinutes, Double(AppSettings.numberLimit))
        XCTAssertEqual(settings.placeHistory.map(\.count), [PlaceUse.maxCount])
        _ = settings.prepMinutes * 60
    }

    // MARK: Alterung

    func testCountsAgeInsteadOfGrowing() {
        let here = CLLocationCoordinate2D(latitude: 52.5, longitude: 13.4)
        var list = [LearnedSignal(lat: here.latitude, lon: here.longitude, stops: 100, totalWait: 2000,
                                  lastSeen: noon, passes: LearnedSignal.memory)]
        list = LearnedSignal.recording(list, at: here, waited: 20, now: noon.addingTimeInterval(60))
        XCTAssertEqual(list[0].passCount, 100, "über der Grenze wird halbiert")
        XCTAssertEqual(list[0].stops, 50)
        XCTAssertEqual(list[0].averageWait, 20, accuracy: 0.5, "und der Schnitt bleibt")
        // Ein Jahr Pendeln: nie über der Grenze.
        for day in 0..<500 { list = LearnedSignal.passing(list, at: here, now: noon.addingTimeInterval(Double(day) * 86_400)) }
        XCTAssertLessThanOrEqual(list[0].passCount, LearnedSignal.memory)
        XCTAssertGreaterThan(list[0].passCount, LearnedSignal.memory / 2 - 1)
    }

    /// Nach 100 grünen Durchfahrten an einer Ampel, die früher immer rot war,
    /// kostet sie kaum noch etwas — ohne Alterung bliebe sie für Jahre teuer.
    func testARebuiltJunctionIsForgottenInMonths() {
        let here = CLLocationCoordinate2D(latitude: 52.5, longitude: 13.4)
        var list = [LearnedSignal(lat: here.latitude, lon: here.longitude, stops: 200, totalWait: 8000,
                                  lastSeen: noon, passes: 200)]
        XCTAssertEqual(list[0].expectedWait(default: 20), 40, accuracy: 0.5)
        for _ in 0..<400 { list = LearnedSignal.passing(list, at: here) }
        XCTAssertLessThan(list[0].expectedWait(default: 20), 12)
    }

    func testTheAgedCountSurvivesTheOtherDevicesOlderLargerOne() {
        let aged = LearnedSignal(lat: 52.5, lon: 13.4, stops: 50, totalWait: 1010, lastSeen: noon, passes: 100)
        let stale = LearnedSignal(lat: 52.5, lon: 13.4, stops: 100, totalWait: 2000,
                                  lastSeen: noon.addingTimeInterval(-3600), passes: 200)
        XCTAssertEqual(LearnedSignal.merging([aged], [stale]), [aged])
        XCTAssertEqual(LearnedSignal.merging([stale], [aged]), [aged])
    }

    // MARK: Startwächter

    func testTwoStartsThatDidNotSurvivePauseTheCloud() {
        let d = UserDefaults(suiteName: "guard-\(UUID())")!
        StartGuard.begin(d, build: "1.12 (52)")
        StartGuard.survived(d)
        StartGuard.begin(d, build: "1.12 (52)")
        StartGuard.begin(d, build: "1.12 (52)")
        XCTAssertFalse(StartGuard.cloudPaused(d, build: "1.12 (52)"), "zwei Abstürze sind gezählt, der dritte Start zieht die Bremse")
        StartGuard.begin(d, build: "1.12 (52)")
        XCTAssertTrue(StartGuard.cloudPaused(d, build: "1.12 (52)"))
        XCTAssertFalse(StartGuard.cloudPaused(d, build: "1.12.1 (53)"), "ein Update nimmt den Abgleich wieder auf")
        // Angehalten bleibt angehalten, auch wenn die App danach läuft.
        StartGuard.survived(d)
        StartGuard.begin(d, build: "1.12 (52)")
        XCTAssertTrue(StartGuard.cloudPaused(d, build: "1.12 (52)"))
        StartGuard.resume(d)
        XCTAssertFalse(StartGuard.cloudPaused(d, build: "1.12 (52)"))
    }

    func testAStartThatSurvivedIsNotCounted() {
        let d = UserDefaults(suiteName: "guard-\(UUID())")!
        for _ in 0..<10 {
            StartGuard.begin(d, build: "1.12 (52)")
            StartGuard.survived(d)
        }
        XCTAssertFalse(StartGuard.cloudPaused(d, build: "1.12 (52)"))
    }
}
