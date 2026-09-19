import SwiftUI

struct TripDetailView: View {
    var option: TripOption

    var body: some View {
        List {
            Section {
                TripMapPanel(options: [option], selectedID: option.id)
                    .frame(height: 340)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                row("Fertig machen", Fmt.time(option.getReady), symbol: "figure.walk.departure")
                row("Los", Fmt.time(option.leave), symbol: "door.left.hand.open")
                row("Ankunft", Fmt.time(option.arrival), symbol: "flag.checkered")
                row("Dauer", Fmt.duration(option.duration), symbol: "timer")
                if let rain = option.rain {
                    Label(rain.summary, systemImage: rain.level.symbol).foregroundStyle(rain.level.color)
                }
                if let note = option.note {
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let bike = option.bikeRoute {
                Section("Radroute: \(bike.title)") {
                    if let st = bike.stats {
                        LabeledContent("Ampelkreuzungen", value: "\(st.signals)")
                        if let v = option.bikeAverageKmh {
                            LabeledContent("Schnitt inkl. Ampeln", value: "\(Int(v.rounded())) km/h")
                        }
                        LabeledContent("An Hauptstraßen", value: Fmt.km(st.mainRoadMeters))
                        LabeledContent("Hauptstraßen gequert", value: "\(st.crossings.count)")
                        if !st.crossings.isEmpty {
                            Text(st.crossings.joined(separator: " → ")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Route von", value: bike.source == "Apple" ? "Apple Karten" : "BRouter (\(bike.source))")
                        .font(.caption)
                }
            }
            Section("Abschnitte") {
                ForEach(option.legs) { leg in LegRow(leg: leg) }
            }
        }
        .navigationTitle(option.mode.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, _ value: String, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text(value).monospacedDigit().fontWeight(.medium)
        }
    }
}

private struct LegRow: View {
    var leg: Leg

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: leg.kind.symbol)
                .foregroundStyle(leg.kind.color)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    if leg.isTransit {
                        LineBadge(leg: leg)
                        if let dir = leg.direction { Text("→ \(dir)").font(.caption).lineLimit(1) }
                    } else {
                        Text(title).font(.subheadline.weight(.medium))
                    }
                    Spacer()
                    Text(Fmt.duration(leg.duration)).font(.caption).foregroundStyle(.secondary)
                }
                stop(time: leg.departure, planned: leg.plannedDeparture, name: leg.fromName, platform: leg.departurePlatform)
                stop(time: leg.arrival, planned: leg.plannedArrival, name: leg.toName, platform: leg.arrivalPlatform)
                if leg.isTransit {
                    Label(leg.bikeCarriage ? "Fahrradmitnahme möglich" : "keine Angabe zur Fahrradmitnahme",
                          systemImage: leg.bikeCarriage ? "bicycle" : "questionmark.circle")
                        .font(.caption2).foregroundStyle(leg.bikeCarriage ? .green : .secondary)
                }
                if leg.cancelled {
                    Text("Fällt aus").font(.caption.weight(.bold)).foregroundStyle(.red)
                }
            }
        }
    }

    private var title: String {
        switch leg.kind {
        case .bike: "Rad \(leg.distance.map(Fmt.km) ?? "")"
        case .walk: "zu Fuß \(leg.distance.map(Fmt.km) ?? "")"
        case .car: "Auto \(leg.distance.map(Fmt.km) ?? "")"
        case .transit: ""
        }
    }

    private func stop(time: Date, planned: Date?, name: String, platform: String?) -> some View {
        HStack(spacing: 6) {
            Text(Fmt.time(time)).monospacedDigit().font(.caption.weight(.semibold))
            if let planned, let d = Fmt.delay(time.timeIntervalSince(planned)) {
                Text(d).font(.caption2.weight(.bold)).foregroundStyle(time > planned ? .red : .green)
            }
            Text(name).font(.caption).lineLimit(1)
            if let platform { Text("Gl. \(platform)").font(.caption2).foregroundStyle(.secondary) }
        }
    }
}
