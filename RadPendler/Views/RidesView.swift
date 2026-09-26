import MapKit
import SwiftUI

/// The rides that were actually ridden, newest first, in the months and years
/// they happened in. The heading of a month carries its sums — that is what
/// one comes here for after the first week: not a single ride, but whether
/// this month was faster than the last.
struct RidesView: View {
    @Environment(RideStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDelete: Ride?
    /// Warum die Linien gerade nicht reisen — leer, solange sie es tun.
    @State private var cloudTrouble: String?

    private var years: [Ride.Year] { Ride.grouped(store.rides) }

    var body: some View {
        NavigationStack {
            Group {
                if store.rides.isEmpty {
                    ContentUnavailableView(L("Noch keine Fahrt"),
                                           systemImage: "figure.outdoor.cycle",
                                           description: Text(L("Auf der Hauptseite eine Verbindung wählen und „Fahrt aufzeichnen“ antippen. Was aufgezeichnet wurde, steht danach hier.")))
                } else {
                    list
                }
            }
            // Ein Upload, der dauerhaft abgewiesen wird, war bis hierher
            // völlig stumm: die Liste sah normal aus, und dass in der Wolke
            // nichts ankam, merkte man erst im CloudKit-Dashboard.
            .safeAreaInset(edge: .top) {
                if let cloudTrouble {
                    Label(cloudTrouble, systemImage: "exclamationmark.icloud")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.gutter).padding(.vertical, 7)
                        .background(.regularMaterial)
                }
            }
            .task { cloudTrouble = await TrackCloud.shared.lastFailure }
            .navigationTitle(L("Fahrten"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Fertig")) { dismiss() } }
            }
        }
    }

    private var list: some View {
        List {
            ForEach(years) { year in
                Section {
                    ForEach(year.months) { month in
                        MonthHeader(month: month)
                        ForEach(month.rides) { ride in
                            NavigationLink { RideDetailView(ride: ride) } label: { RideRow(ride: ride) }
                                .swipeActions {
                                    Button(L("Löschen"), systemImage: "trash", role: .destructive) {
                                        pendingDelete = ride
                                    }
                                }
                        }
                    }
                } header: {
                    YearHeader(year: year)
                }
            }
        }
        .listStyle(.plain)
        .confirmationDialog(L("Fahrt löschen?"), isPresented: Binding(get: { pendingDelete != nil },
                                                                  set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button(L("Löschen"), role: .destructive) {
                if let ride = pendingDelete { store.delete(ride) }
                pendingDelete = nil
            }
            Button(L("Behalten"), role: .cancel) { pendingDelete = nil }
        } message: {
            // The list is merged between devices, so a gap has to be made on
            // each of them — sagen statt hinterher erklären.
            Text(L("Auf diesem Gerät. Andere Geräte behalten sie, bis du sie auch dort löschst."))
        }
    }
}

private struct YearHeader: View {
    var year: Ride.Year

    var body: some View {
        HStack(spacing: 6) {
            Text(String(year.id))
                .font(.system(.headline, design: .rounded, weight: .heavy))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Text(L(year.rides.count == 1 ? "%@ · %d Fahrt · Ø %@" : "%@ · %d Fahrten · Ø %@",
                   Fmt.km(year.meters), year.rides.count, Fmt.kmh(year.averageKmh)))
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .textCase(nil)
        .padding(.vertical, 2)
    }
}

private struct MonthHeader: View {
    var month: Ride.Month

    var body: some View {
        HStack(spacing: 6) {
            Text(month.title)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.accent)
            Spacer(minLength: 0)
            Text(L("%d× · %@ · Ø %@ · %d Ampeln", month.rides.count, Fmt.km(month.meters),
                   Fmt.kmh(month.averageKmh), month.signalStops))
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .listRowBackground(Theme.accent.opacity(0.07))
        .padding(.vertical, 1)
    }
}

/// One ride in one line and a half: when, how long, how fast, how many lights.
struct RideRow: View {
    var ride: Ride

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Image(systemName: ride.travelMode?.symbol ?? "bicycle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ride.travelMode?.color ?? Theme.accent)
                Text(ride.started.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text(Fmt.time(ride.started))
                    .font(.system(size: 12, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(Fmt.clock(ride.seconds))
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .monospacedDigit()
            }
            HStack(spacing: 5) {
                Chip(text: Fmt.km(ride.meters), symbol: "ruler")
                Chip(text: Fmt.kmh(ride.averageKmh), symbol: "speedometer")
                Chip(text: ride.plannedSignals.map { "\(ride.signalStops)/\($0)" } ?? "\(ride.signalStops)",
                     icon: AnyView(TrafficLightIcon()))
                if ride.signalStops > 0 {
                    Chip(text: Fmt.clock(ride.signalWaitTotal), symbol: "hourglass")
                }
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// One ride: the map of the way taken, and every number that was measured.
struct RideDetailView: View {
    @Environment(RideStore.self) private var store
    var ride: Ride
    @State private var track: RideTrack?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                RideMapCard(ride: ride).frame(height: 300)
                RideFacts(ride: ride, track: track)
                StopList(ride: ride)
            }
            .padding(Theme.gutter)
        }
        .background(Theme.background)
        .navigationTitle(ride.started.formatted(.dateTime.day().month().year().hour().minute()))
        .navigationBarTitleDisplayMode(.inline)
        // Die Linie wird ohnehin für die Karte geholt; das Höhenprofil liest
        // aus derselben.
        .task { track = await store.track(for: ride) }
    }
}

/// The map of a finished ride. The track is fetched when the view appears —
/// from the device, or from iCloud when the ride was recorded on another one.
struct RideMapCard: View {
    @Environment(RideStore.self) private var store
    var ride: Ride
    @State private var track: RideTrack?
    @State private var searched = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let track, track.points.count > 1 {
                // Die Skala kommt aus **dieser** Fahrt: eine Autofahrt hat
                // andere Zahlen als eine Radfahrt, und eine Radfahrt gegen den
                // Wind andere als eine mit. Erst dadurch sagt die Farbe etwas.
                let scale = RideColors.Scale.fitted(to: track.points.map(\.kmh),
                                                    fallback: .of(ride.travelMode))
                RouteMapView(options: [], selectedID: nil, radarFrames: [], radarTime: nil,
                             track: track.points, speedScale: scale, trackStops: track.stops,
                             // Die geplante Linie dünn daneben: der Unterschied
                             // ist die eigentliche Auskunft einer Fahrt.
                             plannedLine: track.plannedCoordinates)
                // Nur hier, im Rückblick: während der Fahrt ist der Platz für
                // die Karte da, und die Farben erklären sich beim Fahren von
                // selbst.
                SpeedLegend(scale: scale).padding(8)
            } else if searched {
                // The numbers of every ride reach every device; the line stays
                // where it was drawn. Eighty Kilobyte je Fahrt passen nicht in
                // einen Speicher, der für die ganze App ein Megabyte hat.
                ContentUnavailableView(L("Keine Linie"),
                                       systemImage: "map",
                                       description: Text(L("Die Zahlen dieser Fahrt sind da, die gefahrene Linie nicht: entweder wurde sie vor 1.3 auf einem anderen Gerät aufgezeichnet, oder sie ist gerade nicht aus iCloud zu holen.")))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        }
        .task {
            track = await store.track(for: ride)
            searched = true
        }
    }
}

/// Every number of one ride, in the order they matter.
struct RideFacts: View {
    var ride: Ride
    /// Für das Höhenprofil; ohne sie fehlt nur das Profil.
    var track: RideTrack? = nil

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: ride.travelMode?.symbol ?? "bicycle")
                    .foregroundStyle(ride.travelMode?.color ?? Theme.accent)
                Text("\(ride.origin) → \(ride.destination)")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Text("\(Fmt.time(ride.started)) → \(Fmt.time(ride.ended))")
                    .font(.system(size: 12, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                fact(L("Fahrzeit"), Fmt.clock(ride.seconds), .primary)
                fact(L("Strecke"), Fmt.km(ride.meters), .primary)
                fact(ride.plannedAverageKmh == nil ? L("Ø gesamt") : L("Ø gesamt / Plan"),
                     ride.plannedAverageKmh.map { "\(Self.number(ride.averageKmh)) / \(Self.number($0))" }
                         ?? Fmt.kmh(ride.averageKmh),
                     ride.plannedAverageKmh.map { ride.averageKmh >= $0 ? Color.green : .orange } ?? Theme.accent)
                fact(L("Ø rollend"), Fmt.kmh(ride.movingKmh),
                     RideColors.color(ride.movingKmh, scale: .of(ride.travelMode)))
                fact(L("Spitze"), Fmt.kmh(ride.maxKmh),
                     RideColors.color(ride.maxKmh, scale: .of(ride.travelMode)))
                fact(L("gestanden"), Fmt.clock(ride.standingSeconds), .orange)
                fact(ride.plannedSignals == nil ? L("Ampelhalts") : L("Ampeln / Plan"),
                     ride.plannedSignals.map { "\(ride.signalStops)/\($0)" } ?? "\(ride.signalStops)",
                     .yellow)
                fact(L("Ampelwartezeit"), Fmt.clock(ride.signalWaitTotal), .yellow)
                fact(L("Ø je Ampel"), ride.signalStops == 0 ? "–" : Fmt.clock(ride.signalWaitAverage), .yellow)
            }
            if let mix = ride.mix, !mix.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("Worauf gefahren"))
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                    RoadMixBar(mix: mix)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let profile = ElevationProfile.from(track?.points ?? []) {
                ElevationProfileView(profile: profile)
            }
            if let version = ride.appVersion {
                Text(L("aufgezeichnet mit %@", version))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let off = ride.deviationSeconds {
                // The one comparison that judges the app rather than the rider.
                Label(off <= 0 ? L("%@ schneller als geplant", Fmt.clock(-off))
                               : L("%@ länger als geplant", Fmt.clock(off)),
                      systemImage: off <= 0 ? "checkmark.circle" : "clock.badge.exclamationmark")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(off <= 0 ? .green : .orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .card()
    }

    /// Zwei Geschwindigkeiten in ein Feld: ohne die Einheit, die im Titel
    /// steht. „13,2 / 14,7" ist in einem Drittel Bildschirmbreite lesbar,
    /// „13,2 km/h / 14,7 km/h" nicht.
    static func number(_ kmh: Double) -> String {
        guard kmh.isFinite, kmh >= 0 else { return "–" }
        return kmh.formatted(.number.precision(.fractionLength(1)))
    }

    private func fact(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: Theme.innerCorner))
        .accessibilityElement(children: .combine)
    }
}

/// Where the ride stood and for how long — the longest waits first, because
/// those are the junctions one might want to ride around next time.
private struct StopList: View {
    @Environment(RideStore.self) private var store
    var ride: Ride
    @State private var stops: [RideStop] = []

    var body: some View {
        Group {
            if !stops.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Halte"))
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                    ForEach(stops.sorted { $0.seconds > $1.seconds }.prefix(12)) { stop in
                        HStack(spacing: 8) {
                            if stop.atSignal {
                                TrafficLightIcon()
                            } else {
                                Image(systemName: "pause.circle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Text(stop.atSignal ? L("Ampel") : L("Halt"))
                                .font(.system(size: 13, design: .rounded))
                            Text(Fmt.time(stop.start))
                                .font(.system(size: 11, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Text(Fmt.clock(stop.seconds))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
        }
        .task { stops = await store.track(for: ride)?.stops ?? [] }
    }
}


/// Das Höhenprofil einer Fahrt: die geglättete Höhe über der Strecke.
///
/// Die Höhe ist das Unsicherste, was ein Empfänger liefert — einzelne Fixe
/// springen um zehn Meter, auch auf einer Ebene. Deshalb wird über ein Fenster
/// von `window` Punkten gemittelt, bevor irgendetwas gezeichnet oder gezählt
/// wird: ungeglättet summiert eine flache Pendelstrecke ein Gebirge.
struct ElevationProfile: Equatable {
    /// Höhe je Punkt, geglättet …
    var heights: [Double]
    /// … und wie weit der Punkt vom Start entfernt ist.
    var distances: [Double]
    var ascent: Double
    var lowest: Double
    var highest: Double

    static let window = 9
    /// Unter so vielen Punkten mit Höhe ist es kein Profil, sondern ein Strich.
    static let minPoints = 20
    /// Und so viel muss es am Stück bergauf gehen, bevor es als Anstieg zählt.
    /// Glätten allein reicht nicht: ein Rauschen von ±8 m bleibt auch als
    /// Mittel über neun Punkte ein Zickzack, und die Summe seiner Aufwärtsstücke
    /// ist auf einer Ebene dreistellig. Dasselbe Verfahren, das BRouter
    /// „filtered ascend" nennt.
    static let ascentThreshold = 5.0

    /// Alles Bergauf, das diesen Namen verdient: gezählt wird erst, wenn es
    /// seit dem letzten Tiefpunkt um mehr als `ascentThreshold` hochgegangen
    /// ist.
    static func filteredAscent(_ heights: [Double]) -> Double {
        guard var reference = heights.first else { return 0 }
        var ascent = 0.0
        for h in heights.dropFirst() {
            if h > reference + ascentThreshold {
                ascent += h - reference
                reference = h
            } else if h < reference {
                reference = h
            }
        }
        return ascent
    }

    static func from(_ points: [RidePoint]) -> ElevationProfile? {
        let usable = points.filter { $0.h != nil }
        guard usable.count >= minPoints else { return nil }
        let raw = usable.map { $0.h! }
        var heights: [Double] = []
        heights.reserveCapacity(raw.count)
        for i in raw.indices {
            let lo = Swift.max(0, i - window / 2), hi = Swift.min(raw.count - 1, i + window / 2)
            heights.append(raw[lo...hi].reduce(0, +) / Double(hi - lo + 1))
        }
        var distances: [Double] = [0]
        for (a, b) in zip(usable, usable.dropFirst()) {
            distances.append(distances[distances.count - 1] + a.coordinate.distance(to: b.coordinate))
        }
        let ascent = filteredAscent(heights)
        return ElevationProfile(heights: heights, distances: distances, ascent: ascent,
                                lowest: heights.min() ?? 0, highest: heights.max() ?? 0)
    }
}

/// Eine flache Kurve unter der Straßenart — dieselbe Breite, dieselbe Sprache:
/// was war unter dem Rad, und wie oft ging es dabei bergauf.
struct ElevationProfileView: View {
    var profile: ElevationProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(L("Höhe"))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("+\(Int(profile.ascent.rounded())) m · \(Int(profile.lowest.rounded()))–\(Int(profile.highest.rounded())) m")
                    .font(.system(size: 10, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                let path = curve(in: geo.size)
                ZStack {
                    path.fill(LinearGradient(colors: [Theme.accent.opacity(0.35), Theme.accent.opacity(0.05)],
                                             startPoint: .top, endPoint: .bottom))
                    line(in: geo.size).stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                }
            }
            .frame(height: 44)
            .accessibilityElement()
            .accessibilityLabel(L("Höhenprofil, %d Höhenmeter bergauf", Int(profile.ascent.rounded())))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Die Fläche unter der Kurve …
    private func curve(in size: CGSize) -> Path {
        var p = line(in: size)
        p.addLine(to: CGPoint(x: size.width, y: size.height))
        p.addLine(to: CGPoint(x: 0, y: size.height))
        p.closeSubpath()
        return p
    }

    /// … und die Kurve selbst. Mindestens zehn Meter Spanne, sonst macht die
    /// Skalierung aus einem Meter Rauschen ein Mittelgebirge.
    private func line(in size: CGSize) -> Path {
        var p = Path()
        let total = profile.distances.last ?? 0
        guard total > 0, size.width > 0 else { return p }
        let span = Swift.max(10, profile.highest - profile.lowest)
        for (i, h) in profile.heights.enumerated() {
            let x = profile.distances[i] / total * size.width
            let y = size.height - (h - profile.lowest) / span * size.height
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        return p
    }
}
