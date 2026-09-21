import SwiftUI

/// The four modes as small boxes side by side: icon, travel time and what this
/// option is (schnellst, kürzest, wenig Ampeln — or when the train leaves). One tap
/// picks the mode, the next tap steps to its next option. The route itself is
/// one line underneath and only unfolds when it is tapped.
struct ModeStrip: View {
    var model: PlanModel

    var body: some View {
        HStack(spacing: 7) {
            // Bike first, then bike+rail, car, public transport — except on a
            // long trip, where the bike alone goes last.
            ForEach(model.modeOrder) { mode in
                box(mode)
            }
        }
    }

    private func box(_ mode: TravelMode) -> some View {
        let option = model.selected(for: mode)
        let count = model.options(for: mode).count
        let active = model.activeMode == mode
        let recommended = model.recommended?.mode == mode
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                if active { model.cycle(mode) } else { model.activeMode = mode }
            }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    icon(mode)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(active ? .white : mode.color)
                        .frame(width: 34, height: 24)
                    if recommended {
                        Image(systemName: "star.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(active ? .white : .yellow)
                            .offset(x: 5, y: -3)
                    }
                }
                Text(option.map { Fmt.duration($0.duration) } ?? "–")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(active ? .white : mode.color)
                Text(caption(mode, option))
                    .font(.system(size: 9.5, design: .rounded))
                    .foregroundStyle(active ? .white.opacity(0.85) : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                dots(count: count, index: index(mode), active: active, color: mode.color)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                    .fill(active ? AnyShapeStyle(Theme.gradient(mode.color))
                                 : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(active ? 0 : 0.07))
            }
            .shadow(color: .black.opacity(active ? 0.12 : 0.04), radius: active ? 8 : 3, y: 2)
            .opacity(option?.passesWaypoints == false ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        // Held down: back to the first, which is the best one of this mode.
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
            withAnimation(.snappy(duration: 0.2)) { model.selectFirst(mode) }
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        })
        .accessibilityLabel("\(mode.title): \(option.map { Fmt.duration($0.duration) } ?? "keine Verbindung")")
        .accessibilityHint(count > 1 ? "Nochmal tippen für die nächste von \(count) Möglichkeiten, lang drücken für die beste" : "")
    }

    /// Rad + Bahn is the one mode that is two things, so it gets both symbols;
    /// the rest have one that says it all.
    @ViewBuilder private func icon(_ mode: TravelMode) -> some View {
        if mode == .bikeTransit {
            // Two glyphs in the width of one, so they need to be a size smaller.
            HStack(spacing: 3) {
                Image(systemName: "bicycle")
                Image(systemName: "train.side.front.car")
            }
            .font(.system(size: 13, weight: .semibold))
        } else {
            Image(systemName: mode.symbol)
        }
    }

    /// One dot per option of this mode, the chosen one filled — the hint that
    /// another tap gets you the next one.
    @ViewBuilder private func dots(count: Int, index: Int, active: Bool, color: Color) -> some View {
        if count > 1 {
            HStack(spacing: 2.5) {
                ForEach(0..<min(count, 5), id: \.self) { i in
                    Circle()
                        .fill(active ? Color.white.opacity(i == index ? 1 : 0.4)
                                     : color.opacity(i == index ? 0.9 : 0.25))
                        .frame(width: 3.5, height: 3.5)
                }
            }
            .padding(.top, 1)
        } else {
            Color.clear.frame(height: 4.5)
        }
    }

    private func index(_ mode: TravelMode) -> Int {
        let own = model.options(for: mode)
        let id = model.selected(for: mode)?.id
        return own.firstIndex { $0.id == id } ?? 0
    }

    /// Bike routes say which variant they are, connections when they leave.
    private func caption(_ mode: TravelMode, _ option: TripOption?) -> String {
        guard let option else {
            if model.isLoading { return "sucht …" }
            return model.result.failures[mode] != nil ? "Fehler" : "nichts"
        }
        if let bike = option.bikeRoute { return bike.variants.first?.title ?? "Route" }
        if let car = option.carRoute { return car.variants.first?.title ?? Fmt.km(option.totalDistance) }
        if option.transitLegs.isEmpty { return Fmt.km(option.totalDistance) }
        return option.transfers == 0 ? "ab \(Fmt.time(option.leave))"
                                     : "\(Fmt.time(option.leave)) · \(option.transfers)×"
    }
}

/// The chosen trip in two lines: when it leaves and arrives with its legs, and
/// the handful of facts that change the decision. Everything else — the
/// timeline, the crossings, the route's origin — waits behind the chevron.
struct SelectedTripBar: View {
    var model: PlanModel
    var option: TripOption

    var body: some View {
        NavigationLink {
            TripDetailView(option: option, reason: recommendationReason)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("\(Fmt.time(option.leave)) → \(Fmt.time(option.arrival))")
                        .display(.subheadline, weight: .semibold)
                        .monospacedDigit()
                        .fixedSize()
                    // The legs take whatever width is left and scroll if the
                    // trip has more of them than the line can hold.
                    ScrollView(.horizontal, showsIndicators: false) {
                        LegChainView(option: option, compact: true).padding(.vertical, 1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(Fmt.duration(option.duration))
                        .display(.subheadline, weight: .bold)
                        .monospacedDigit()
                        .foregroundStyle(option.mode.color)
                        .fixedSize()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 5) {
                    Chip(text: "los \(Fmt.time(option.getReady))", symbol: "alarm")
                    Chip(text: Fmt.km(option.totalDistance), symbol: "ruler")
                    if let signals = option.bikeRoute?.stats?.signals ?? option.carRoute?.signals {
                        Chip(text: "\(signals)", icon: AnyView(TrafficLightIcon()))
                    }
                    if let t = option.transferText {
                        Chip(text: t, symbol: option.transfers == 0 ? "arrow.forward" : "arrow.triangle.swap",
                             tint: option.transfers == 0 ? .green : .red, strong: true)
                    }
                    if let warning {
                        Chip(text: warning.text, symbol: warning.symbol, tint: warning.tint, strong: true)
                    }
                    Spacer(minLength: 0)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(highlighted: model.recommended?.id == option.id, tint: option.mode.color)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private struct Note { var text: String; var symbol: String; var tint: Color }

    private var recommendationReason: String? {
        model.recommended?.id == option.id ? model.result.recommendation?.reason : nil
    }

    /// At most one warning, as a chip: rain first, then the two ways this trip
    /// is not the plain one. The reasons and the full text live in the detail.
    private var warning: Note? {
        if let rain = option.rain, rain.level != .dry {
            return Note(text: rain.summary, symbol: rain.level.symbol, tint: rain.level.color)
        }
        if option.bikeCarriageUnclear {
            return Note(text: "Rad ungeklärt", symbol: "questionmark.circle", tint: .orange)
        }
        if option.isAlternative {
            return Note(text: "U-Bahn/Tram", symbol: "arrow.triangle.branch", tint: .orange)
        }
        if !option.passesWaypoints {
            return Note(text: "ohne Fixpunkte", symbol: "point.topleft.down.to.point.bottomright.curvepath",
                        tint: .secondary)
        }
        if model.result.failures[option.mode] != nil {
            return Note(text: "Fehler", symbol: "exclamationmark.triangle", tint: .orange)
        }
        return nil
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
