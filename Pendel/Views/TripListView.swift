import SwiftUI

struct TripListView: View {
    var model: PlanModel
    @Environment(AppSettings.self) private var settings

    /// Bike+rail first: it is the default whenever the weather is doubtful.
    private let order: [TravelMode] = [.bikeTransit, .bike, .transit, .car]

    var body: some View {
        Group {
            if model.needsAddresses {
                ContentUnavailableView("Start und Ziel wählen", systemImage: "mappin.and.ellipse",
                                       description: Text("Oben auf die beiden Felder tippen. Die Adressen bleiben auf diesem Gerät."))
            } else {
                trips
            }
        }
        .refreshable { model.refresh(settings: settings) }
    }

    private var trips: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if let rec = model.recommended, let reason = model.result.recommendation?.reason {
                    section("Empfehlung", symbol: "star.fill", tint: .yellow) {
                        VStack(spacing: 0) {
                            NavigationLink { TripDetailView(option: rec) } label: {
                                TripCard(option: rec, highlighted: true)
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.horizontal, 14)
                            Label(reason, systemImage: "sparkles")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                        }
                        .card(highlighted: true, tint: rec.mode.color)
                    }
                }
                ForEach(order) { mode in
                    let options = model.options(for: mode)
                    section(mode.title, symbol: mode.symbol, tint: mode.color) {
                        VStack(spacing: 10) {
                            ForEach(options) { option in
                                NavigationLink { TripDetailView(option: option) } label: {
                                    TripCard(option: option, highlighted: false).card()
                                }
                                .buttonStyle(.plain)
                            }
                            if let failure = model.result.failures[mode] {
                                note(failure, symbol: "exclamationmark.triangle", tint: .orange)
                            } else if options.isEmpty && model.isLoading {
                                note("Suche …", symbol: "ellipsis", tint: .secondary)
                            } else if options.isEmpty && model.lastRun != nil {
                                note(mode == .bikeTransit ? "Keine Verbindung mit Fahrradmitnahme gefunden"
                                                          : "Keine Verbindung gefunden",
                                     symbol: "minus.circle", tint: .secondary)
                            }
                        }
                    }
                }
                footer
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
    }

    private func section<Content: View>(_ title: String, symbol: String, tint: Color,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.system(.footnote, design: .rounded, weight: .bold))
                .foregroundStyle(tint)
                .textCase(.uppercase)
                .padding(.leading, 4)
            content()
        }
    }

    private func note(_ text: String, symbol: String, tint: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(.footnote, design: .rounded))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .card()
    }

    @ViewBuilder private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let rainFailure = model.result.rainFailure {
                Label(rainFailure, systemImage: "cloud.slash").foregroundStyle(.orange)
            }
            if let last = model.lastRun {
                Text("Stand \(Fmt.time(last)) · Rad \(Int(settings.bikeSpeedKmh)) km/h + \(settings.signalWaitSeconds) s/Ampel")
                Text("Fahrplan VBB · Karten Apple · Radrouten BRouter/OSM · Regen DWD und Open-Meteo")
            }
        }
        .font(.system(.caption2, design: .rounded))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}

/// One option as a card: mode bubble, times, the legs as icons, the facts.
struct TripCard: View {
    var option: TripOption
    var highlighted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ModeBubble(symbol: option.mode.symbol, color: option.mode.color, size: highlighted ? 44 : 38)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Fmt.time(option.leave))
                        .display(highlighted ? .title2 : .title3, weight: .bold).monospacedDigit()
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                    Text(Fmt.time(option.arrival))
                        .display(highlighted ? .title2 : .title3, weight: .bold).monospacedDigit()
                    Spacer(minLength: 0)
                    Chip(text: Fmt.duration(option.duration), tint: option.mode.color, strong: true)
                }
                LegChainView(option: option)
                facts
                if let note = option.departureNote {
                    Text(note).font(.system(.caption, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
                }
                if let rain = option.rain {
                    Label(rain.summary, systemImage: rain.level.symbol)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(rain.level.color)
                }
                if !option.passesWaypoints {
                    Label("führt nicht über die Fixpunkte", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                if option.isAlternative {
                    Label("Alternative mit U-Bahn/Tram — kein festes Radabteil", systemImage: "arrow.triangle.branch")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(14)
        .contentShape(Rectangle())
        .grayscale(option.passesWaypoints ? 0 : 1)
        .opacity(option.passesWaypoints ? 1 : 0.55)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var facts: some View {
        HStack(spacing: 6) {
            if let bike = option.bikeRoute {
                Chip(text: bike.title, symbol: "bicycle", tint: option.mode.color, strong: true)
            }
            Chip(text: Fmt.km(option.totalDistance), symbol: "ruler")
            if let s = option.bikeRoute?.stats {
                Chip(text: "\(s.signals) Ampeln", symbol: "light.beacon.max")
            }
            if let t = option.transferText {
                Chip(text: t, symbol: option.transfers == 0 ? "arrow.forward" : "arrow.triangle.swap",
                     tint: option.transfers == 0 ? .green : .secondary, strong: option.transfers == 0)
            }
            if option.mode == .bike, let v = option.bikeAverageKmh {
                Chip(text: "Ø \(Int(v.rounded())) km/h", symbol: "speedometer")
            }
            Chip(text: "los \(Fmt.time(option.getReady))", symbol: "alarm")
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

extension TripOption {
    /// Where the first train leaves, with its delay.
    var departureNote: String? {
        guard let first = transitLegs.first else { return nil }
        let delay = Fmt.delay(first.departureDelay).map { " \($0) min" } ?? ""
        return "ab \(first.fromName)\(delay)"
    }
}
