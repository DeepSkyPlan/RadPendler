import SwiftUI

extension Color {
    /// "#1FA847" as the phone sends it.
    init(hex: String) {
        let v = UInt64(hex.dropFirst(), radix: 16) ?? 0x888888
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}


/// Three pages, swiped vertically: the countdown, the chosen trip, and the
/// categories — Rad, Rad + Bahn, Auto, Bahn & Bus — with their options behind
/// them. What the wrist picks is what the countdown counts to; the phone keeps
/// its own choice, and "Vorschlag des iPhones" gives it back.
struct WatchHome: View {
    @Environment(WatchModel.self) private var model
    @State private var page = 0

    var body: some View {
        if let plan = model.snapshot, !plan.options.isEmpty {
            TabView(selection: $page) {
                CountdownPage(plan: plan).tag(0)
                if let trip = model.selected { TripPage(plan: plan, trip: trip).tag(1) }
                // Choosing a way sends you back to the countdown: that is what
                // one came for, and finding the way back past a pushed list is
                // more turning of the crown than anybody wants.
                NavigationStack { ModesPage(plan: plan, onPick: { page = 0 }) }.tag(2)
            }
            .tabViewStyle(.verticalPage)
        } else {
            ContentUnavailableView("Kein Plan",
                                   systemImage: "iphone.slash",
                                   description: Text("RadPendler auf dem iPhone öffnen — der Plan kommt von dort."))
        }
    }
}

/// The one number worth a wrist: how long until it is time to go.
private struct CountdownPage: View {
    @Environment(WatchModel.self) private var model
    var plan: TripSnapshot

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let trip = model.selected
            // Riding off "now" has no departure to count to — the pill goes
            // grey instead of pretending to.
            let left = trip.flatMap { $0.countsDown ? $0.getReady.timeIntervalSince(context.date) : nil }
            let gone = trip.map { $0.countsDown && context.date > $0.leave } ?? false
            let step = Countdown.urgency(left, gone: gone)
            VStack(spacing: 2) {
                Text(step.caption(overdue: (left ?? 0) < 0))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .opacity(0.85)
                Text(left.map(Countdown.text) ?? "–")
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .contentTransition(.numericText(countsDown: true))
                if let trip {
                    HStack(spacing: 4) {
                        Image(systemName: trip.symbol).font(.system(size: 11, weight: .semibold))
                        if let line = trip.legs.first(where: { $0.line != nil })?.line {
                            Text(line)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(.white.opacity(0.25), in: RoundedRectangle(cornerRadius: 4))
                        }
                        Text("\(Fmt.time(trip.leave)) → \(Fmt.time(trip.arrival))")
                            .font(.system(size: 12, design: .rounded))
                            .monospacedDigit()
                    }
                    .padding(.top, 2)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 6)
            .background {
                LinearGradient(colors: step.colors.map { Color(.sRGB, red: $0.0, green: $0.1, blue: $0.2) },
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
            .accessibilityLabel(left.map { "Losgehen in \(Countdown.text($0))" } ?? "Keine feste Abfahrt")
        }
    }
}

/// The chosen trip leg by leg — the same chain the phone draws, stacked.
private struct TripPage: View {
    var plan: TripSnapshot
    var trip: TripSnapshot.Option

    var body: some View {
        List {
            Section {
                ForEach(trip.legs) { leg in
                    HStack(spacing: 8) {
                        Image(systemName: leg.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: leg.colorHex))
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                if let line = leg.line {
                                    Text(line)
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(Color(hex: leg.colorHex), in: RoundedRectangle(cornerRadius: 4))
                                }
                                Text("\(Fmt.time(leg.departure)) → \(Fmt.time(leg.arrival))")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                            }
                            Text(leg.to).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if let m = leg.meters {
                            Text(Fmt.km(m)).font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 1)
                }
            } header: {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(trip.modeTitle) · \(Fmt.duration(trip.duration))")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: trip.colorHex))
                    Text("los \(Fmt.time(trip.getReady)) · \(Fmt.km(trip.meters))")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                    if let rain = trip.rain {
                        Label(rain, systemImage: "cloud.rain").font(.system(size: 11)).foregroundStyle(.blue)
                    }
                }
                .textCase(nil)
                .padding(.bottom, 2)
            }
        }
    }
}

/// The four categories, then one option at a time inside them.
private struct ModesPage: View {
    @Environment(WatchModel.self) private var model
    var plan: TripSnapshot
    /// Called once a way has been chosen, so the pages can go back.
    var onPick: () -> Void

    var body: some View {
        List {
            ForEach(plan.modes, id: \.self) { mode in
                NavigationLink {
                    OptionsList(plan: plan, mode: mode, onPick: onPick)
                } label: {
                    row(mode)
                }
            }
            if model.chosenMode != nil {
                Button("Vorschlag des iPhones") {
                    model.followPhone()
                    onPick()
                }
                    .font(.system(size: 12, design: .rounded))
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(plan.origin) → \(plan.destination)").lineLimit(1)
                    Text("Stand \(Fmt.time(plan.computedAt)) · \(Fmt.age(context.date.timeIntervalSince(plan.computedAt)))")
                }
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Wie?")
    }

    /// One category: its best time, how many ways it has, and whether it is the
    /// one on the countdown.
    private func row(_ mode: String) -> some View {
        let own = plan.options(in: mode)
        let best = own.first
        let active = model.activeMode == mode
        return HStack(spacing: 8) {
            Image(systemName: best?.symbol ?? "questionmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: best?.colorHex ?? "#888888"))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(best.map { Fmt.duration($0.duration) } ?? "–")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(own.count > 1 ? "\(plan.title(of: mode)) · \(own.count) Wege" : plan.title(of: mode))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if own.contains(where: \.isRecommended) {
                Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.yellow)
            }
            if active {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(hex: best?.colorHex ?? "#888888"))
            }
        }
        .padding(.vertical, 1)
    }
}

/// The ways one category offers — tapping one puts it on the countdown.
private struct OptionsList: View {
    @Environment(WatchModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var plan: TripSnapshot
    var mode: String
    var onPick: () -> Void

    var body: some View {
        List {
            ForEach(Array(plan.options(in: mode).enumerated()), id: \.element.id) { index, option in
                Button {
                    model.choose(mode: mode, index: index)
                    dismiss()
                    onPick()
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 5) {
                                Text(Fmt.duration(option.duration))
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                Text("\(Fmt.time(option.leave)) → \(Fmt.time(option.arrival))")
                                    .font(.system(size: 11, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            Text(option.caption).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            if let rain = option.rain {
                                Label(rain, systemImage: "cloud.rain")
                                    .font(.system(size: 10)).foregroundStyle(.blue).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        if option.isRecommended {
                            Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.yellow)
                        }
                        if model.isChosen(option) {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color(hex: option.colorHex))
                        }
                    }
                    .padding(.vertical, 1)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(plan.title(of: mode))
    }
}
