import SwiftUI

/// One travel mode as a single card with a chip row to pick between its
/// options: the bike routes by name, everything else by departure and changes.
struct ModeBlock: View {
    var model: PlanModel
    var mode: TravelMode

    private var options: [TripOption] { model.options(for: mode) }
    private var chosen: TripOption? { model.selected(for: mode) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label(mode.title, systemImage: mode.symbol)
                    .font(.system(.footnote, design: .rounded, weight: .bold))
                    .foregroundStyle(mode.color)
                    .textCase(.uppercase)
                if model.recommended?.mode == mode {
                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 4)

            if options.count > 1 { picker }

            if let chosen {
                NavigationLink { TripDetailView(option: chosen) } label: {
                    TripCard(option: chosen, highlighted: model.recommended?.id == chosen.id,
                             reason: model.recommended?.id == chosen.id ? model.result.recommendation?.reason : nil)
                        .card(highlighted: model.activeMode == mode, tint: mode.color)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { model.activeMode = mode })
            } else if let failure = model.result.failures[mode] {
                note(failure, symbol: "exclamationmark.triangle", tint: .orange)
            } else if model.isLoading {
                note("Suche …", symbol: "ellipsis", tint: .secondary)
            } else if model.lastRun != nil {
                note(mode == .bikeTransit ? "Keine Verbindung mit Fahrradmitnahme gefunden"
                                          : "Keine Verbindung gefunden",
                     symbol: "minus.circle", tint: .secondary)
            }
        }
    }

    private var picker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(options) { option in
                    let active = option.id == chosen?.id
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            model.selection[mode] = option.id
                            model.activeMode = mode
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if let symbol = symbol(option) { Image(systemName: symbol).font(.caption2) }
                            Text(label(option))
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                            if option.transfers > 0 {
                                Text("\(option.transfers)×")
                                    .font(.system(.caption2, design: .rounded, weight: .bold))
                                    .foregroundStyle(active ? .white : .red)
                            }
                        }
                        .foregroundStyle(active ? .white : mode.color)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background {
                            if active { Capsule().fill(Theme.gradient(mode.color)) }
                            else { Capsule().fill(mode.color.opacity(0.12)) }
                        }
                        .opacity(option.passesWaypoints ? 1 : 0.5)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    /// Bike routes are named, connections are known by when they leave.
    private func label(_ option: TripOption) -> String {
        if let bike = option.bikeRoute { return bike.title }
        return Fmt.time(option.leave)
    }

    private func symbol(_ option: TripOption) -> String? {
        option.bikeRoute?.variants.sorted().first?.symbol
    }

    private func note(_ text: String, symbol: String, tint: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(.footnote, design: .rounded))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .card()
    }
}

/// One option as a card: mode bubble, travel time, the legs as icons, the facts.
struct TripCard: View {
    var option: TripOption
    var highlighted: Bool
    var reason: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ModeBubble(symbol: option.mode.symbol, color: option.mode.color, size: highlighted ? 44 : 38)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Fmt.time(option.leave)) → \(Fmt.time(option.arrival))")
                            .display(highlighted ? .title3 : .subheadline, weight: .regular)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Text(Fmt.duration(option.duration))
                            .display(highlighted ? .title2 : .title3, weight: .bold)
                            .monospacedDigit()
                            .foregroundStyle(option.mode.color)
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
            if let reason {
                Divider().padding(.horizontal, 14)
                Label(reason, systemImage: "sparkles")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        }
        .contentShape(Rectangle())
        .grayscale(option.passesWaypoints ? 0 : 1)
        .opacity(option.passesWaypoints ? 1 : 0.55)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var facts: some View {
        HStack(spacing: 6) {
            Chip(text: Fmt.km(option.totalDistance), symbol: "ruler")
            if let s = option.bikeRoute?.stats {
                Chip(text: "\(s.signals)", icon: AnyView(TrafficLightIcon()))
            }
            if let t = option.transferText {
                Chip(text: t, symbol: option.transfers == 0 ? "arrow.forward" : "arrow.triangle.swap",
                     tint: option.transfers == 0 ? .green : .red, strong: true)
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
