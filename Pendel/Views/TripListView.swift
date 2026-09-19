import SwiftUI

struct TripListView: View {
    var model: PlanModel
    @Environment(AppSettings.self) private var settings

    /// Bike+rail first: it is the default whenever the weather is doubtful.
    private let order: [TravelMode] = [.bikeTransit, .bike, .transit, .car]

    var body: some View {
        List {
            if let rec = model.recommended, let reason = model.result.recommendation?.reason {
                Section {
                    NavigationLink { TripDetailView(option: rec) } label: {
                        TripRow(option: rec, highlighted: true)
                    }
                    Label(reason, systemImage: "star.fill")
                        .font(.footnote).foregroundStyle(.secondary)
                        .symbolRenderingMode(.multicolor)
                } header: {
                    Text("Empfehlung")
                }
            }
            ForEach(order) { mode in
                Section(mode.title) {
                    let options = model.options(for: mode)
                    ForEach(options) { option in
                        NavigationLink { TripDetailView(option: option) } label: {
                            TripRow(option: option, highlighted: false)
                        }
                    }
                    if let failure = model.result.failures[mode] {
                        Label(failure, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.orange)
                    } else if options.isEmpty && !model.isLoading && model.lastRun != nil {
                        Text(mode == .bikeTransit ? "Keine Verbindung mit Fahrradmitnahme gefunden"
                                                  : "Keine Verbindung gefunden")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                if let rainFailure = model.result.rainFailure {
                    Label(rainFailure, systemImage: "cloud.slash").font(.footnote).foregroundStyle(.orange)
                }
                if let last = model.lastRun {
                    Text("Stand \(Fmt.time(last)) · Rad \(Int(settings.bikeSpeedKmh)) km/h · Fahrplan VBB, Regen DWD/Open-Meteo")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if model.isLoading && model.options.isEmpty { ProgressView("Suche Verbindungen …") }
        }
        .refreshable { model.refresh(settings: settings) }
    }
}

struct TripRow: View {
    var option: TripOption
    var highlighted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: option.mode.symbol)
                .font(.title2)
                .foregroundStyle(option.mode.color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Fmt.time(option.leave)) → \(Fmt.time(option.arrival))")
                        .font(highlighted ? .title3.weight(.semibold) : .body.weight(.semibold))
                        .monospacedDigit()
                    Spacer()
                    Text(Fmt.duration(option.duration))
                        .font(.callout.weight(.medium)).monospacedDigit()
                }
                legSummary
                HStack(spacing: 8) {
                    Text("fertig machen \(Fmt.time(option.getReady))")
                    if option.bikeDistance > 0 { Text("Rad \(Fmt.km(option.bikeDistance))") }
                    if option.walkDistance > 0 { Text("zu Fuß \(Fmt.km(option.walkDistance))") }
                    if option.mode == .car, let d = option.legs.first?.distance { Text(Fmt.km(d)) }
                }
                .font(.caption).foregroundStyle(.secondary)
                if let rain = option.rain {
                    Label(rain.summary, systemImage: rain.level.symbol)
                        .font(.caption).foregroundStyle(rain.level.color)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var legSummary: some View {
        let transit = option.transitLegs
        if transit.isEmpty {
            Text(option.note ?? option.mode.title).font(.caption).foregroundStyle(.secondary)
        } else {
            HStack(spacing: 4) {
                if option.mode == .bikeTransit { Image(systemName: "bicycle").font(.caption) }
                ForEach(transit) { leg in
                    LineBadge(leg: leg)
                    if let d = Fmt.delay(leg.departureDelay) {
                        Text(d).font(.caption2.weight(.bold)).foregroundStyle(leg.departureDelay > 0 ? .red : .green)
                    }
                }
                if option.mode == .bikeTransit { Image(systemName: "bicycle").font(.caption) }
                Text("ab \(transit[0].fromName)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}
