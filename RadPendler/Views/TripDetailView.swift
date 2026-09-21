import SwiftUI

struct TripDetailView: View {
    var option: TripOption
    /// Why the app recommends this trip, when it does — the line the trip bar
    /// used to carry on the main screen.
    var reason: String? = nil
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TripMapPanel(options: [option], selectedID: option.id, waypoints: settings.waypoints)
                        .frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.06))
                        }
                    summary
                    TripFacts(option: option)
                    timeline
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle(option.mode.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summary: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ModeBubble(symbol: option.mode.symbol, color: option.mode.color, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Fmt.duration(option.duration))
                            .display(.title2, weight: .bold)
                            .monospacedDigit()
                            .foregroundStyle(option.mode.color)
                        Text("\(Fmt.time(option.leave)) → \(Fmt.time(option.arrival))")
                            .display(.subheadline, weight: .regular)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Text(Fmt.km(option.totalDistance))
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Chip(text: "fertig machen \(Fmt.time(option.getReady))", symbol: "alarm",
                     tint: option.mode.color, strong: true)
                if let t = option.transferText { Chip(text: t, symbol: "arrow.triangle.swap") }
                if let v = option.bikeAverageKmh, option.mode == .bike {
                    Chip(text: "Ø \(Int(v.rounded())) km/h", symbol: "speedometer")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let rain = option.rain {
                Label(rain.summary, systemImage: rain.level.symbol)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(rain.level.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            TripNotes(option: option, reason: reason)
        }
        .padding(14)
        .card()
    }

    private var timeline: some View {
        TripTimeline(option: option).padding(14).card()
    }
}

/// Why this trip and not another, plus the warnings that go with it. The phone
/// squeezes at most one of these into a chip; here they get their words back.
struct TripNotes: View {
    var option: TripOption
    var reason: String?

    private struct Note { var text: String; var symbol: String; var tint: Color }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(notes, id: \.text) { note in
                Label(note.text, systemImage: note.symbol)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(note.tint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var notes: [Note] {
        var out: [Note] = []
        if let reason { out.append(Note(text: reason, symbol: "sparkles", tint: .secondary)) }
        if option.isAlternative {
            out.append(Note(text: "Alternative mit U-Bahn/Tram — kein festes Radabteil",
                            symbol: "arrow.triangle.branch", tint: .orange))
        }
        if !option.passesWaypoints {
            out.append(Note(text: "führt nicht über die Fixpunkte",
                            symbol: "point.topleft.down.to.point.bottomright.curvepath", tint: .secondary))
        }
        if let note = option.note { out.append(Note(text: note, symbol: "info.circle", tint: .secondary)) }
        return out
    }
}

/// What kind of route this is: the bike card or the car card. A timetable trip
/// has no card — its facts are the timeline.
struct TripFacts: View {
    var option: TripOption

    var body: some View {
        if let bike = option.bikeRoute {
            bikeCard(bike)
        } else if let car = option.carRoute {
            carCard(car)
        }
    }

    private func bikeCard(_ bike: BikeRouteInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Radroute: \(bike.title)", systemImage: "bicycle")
                .display(.subheadline)
                .foregroundStyle(LegKind.bike.color)
            if let st = bike.stats {
                HStack(spacing: 6) {
                    Chip(text: "\(st.signals) Ampeln", icon: AnyView(TrafficLightIcon()))
                    Chip(text: "\(st.crossings.count)× quer", symbol: "arrow.left.arrow.right")
                    Chip(text: "\(Fmt.km(st.mainRoadMeters)) an Hauptstraßen", symbol: "road.lanes")
                }
                .lineLimit(1).minimumScaleFactor(0.8)
                if !st.crossings.isEmpty {
                    Text(st.crossings.joined(separator: " → "))
                        .font(.system(.caption, design: .rounded)).foregroundStyle(.secondary)
                }
            }
            Text(bike.source == "Apple" ? "Route von Apple Karten" : "Route von BRouter (\(bike.source))")
                .font(.system(.caption2, design: .rounded)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .card()
    }

    private func carCard(_ car: CarRouteInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Autoroute: \(car.title)", systemImage: "car.fill")
                .display(.subheadline)
                .foregroundStyle(LegKind.car.color)
            HStack(spacing: 6) {
                Chip(text: Fmt.km(option.totalDistance), symbol: "ruler")
                if let s = car.signals {
                    Chip(text: "\(s) Ampeln", icon: AnyView(TrafficLightIcon()))
                } else {
                    Chip(text: "Ampeln unbekannt", symbol: "questionmark.circle")
                }
            }
            .lineLimit(1).minimumScaleFactor(0.8)
            Text("Linienführung und Fahrzeit von Apple Karten, Ampeln aus OpenStreetMap")
                .font(.system(.caption2, design: .rounded)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .card()
    }
}

/// The legs of a trip one under the other. Its own view because the iPad puts
/// it straight into the side column — there is room for it there, and a tap
/// less is a tap less.
struct TripTimeline: View {
    var option: TripOption

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(option.legs.enumerated()), id: \.element.id) { i, leg in
                LegTimelineRow(leg: leg, isLast: i == option.legs.count - 1)
            }
        }
    }
}

/// One leg as a row on a vertical line: dot, times, what and how far.
struct LegTimelineRow: View {
    var leg: Leg
    var isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle().fill(leg.kind.color).frame(width: 10, height: 10)
                if !isLast {
                    Rectangle().fill(leg.kind.color.opacity(0.35)).frame(width: 3)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)
            VStack(alignment: .leading, spacing: 4) {
                stop(time: leg.departure, planned: leg.plannedDeparture, name: leg.fromName, platform: leg.departurePlatform)
                HStack(spacing: 6) {
                    Image(systemName: leg.kind.symbol).font(.caption).foregroundStyle(leg.kind.color)
                    if leg.isTransit {
                        LineBadge(leg: leg)
                        if let dir = leg.direction {
                            Text("→ \(dir)").font(.system(.caption, design: .rounded)).lineLimit(1)
                        }
                    }
                    if let m = leg.length { Chip(text: Fmt.km(m), symbol: "ruler") }
                    Chip(text: Fmt.duration(leg.duration), symbol: "clock")
                }
                if leg.isTransit {
                    Label(leg.bikeCarriage ? "Fahrradmitnahme möglich" : "keine Angabe zur Fahrradmitnahme",
                          systemImage: leg.bikeCarriage ? "bicycle" : "questionmark.circle")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(leg.bikeCarriage ? LegKind.bike.color : .secondary)
                }
                if leg.cancelled {
                    Text("Fällt aus").font(.system(.caption, design: .rounded, weight: .bold)).foregroundStyle(.red)
                }
                stop(time: leg.arrival, planned: leg.plannedArrival, name: leg.toName, platform: leg.arrivalPlatform)
                    .padding(.bottom, isLast ? 0 : 12)
            }
        }
    }

    private func stop(time: Date, planned: Date?, name: String, platform: String?) -> some View {
        HStack(spacing: 6) {
            Text(Fmt.time(time)).monospacedDigit()
                .font(.system(.caption, design: .rounded, weight: .semibold))
            if let planned, let d = Fmt.delay(time.timeIntervalSince(planned)) {
                Text(d).font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(time > planned ? .red : .green)
            }
            Text(name).font(.system(.caption, design: .rounded)).lineLimit(1)
            if let platform {
                Text("Gl. \(platform)").font(.system(.caption2, design: .rounded)).foregroundStyle(.secondary)
            }
        }
    }
}
