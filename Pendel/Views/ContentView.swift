import SwiftUI

struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @State private var model = PlanModel()
    /// `-tab map` opens on the map (screenshots, UI tests).
    @State private var tab = UserDefaults.standard.string(forKey: "tab") == "map" ? Tab.map : Tab.list
    @State private var showSettings = false
    @State private var editing: PlaceField?

    enum Tab: String, CaseIterable { case list, map }

    enum PlaceField: Identifiable {
        case origin, destination
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                VStack(spacing: 14) {
                    RouteHeader(origin: settings.origin, destination: settings.destination,
                                startTime: $model.startTime, prepMinutes: settings.prepMinutes,
                                presets: settings.departurePresets,
                                onEdit: { editing = $0 },
                                onSwap: { settings.swapDirection(); refresh() })
                    PillPicker(items: [(Tab.list, "Liste", "list.bullet"), (Tab.map, "Karte", "map")],
                               selection: $tab)
                        .padding(.horizontal, Theme.gutter)

                    switch tab {
                    case .list: TripListView(model: model)
                    case .map: MapTab(model: model)
                    }
                }
                .padding(.top, 6)
            }
            .navigationTitle("Pendel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Einstellungen")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if model.isLoading {
                        ProgressView()
                    } else {
                        Button { refresh() } label: { Image(systemName: "arrow.clockwise") }
                            .accessibilityLabel("Aktualisieren")
                    }
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: refresh) { SettingsView() }
            .sheet(item: $editing, onDismiss: refresh) { field in
                NavigationStack {
                    AddressSearchView(title: field == .origin ? "Start" : "Ziel") { place in
                        if field == .origin { settings.origin = place } else { settings.destination = place }
                    }
                }
            }
            .task { refresh() }
            .onChange(of: model.startTime) { refresh() }
        }
        .tint(Theme.accent)
    }

    private func refresh() {
        model.refresh(settings: settings)
    }
}

/// From, to and departure time — the card at the top of the screen.
private struct RouteHeader: View {
    var origin: Place?
    var destination: Place?
    @Binding var startTime: PlanModel.StartTime
    var prepMinutes: Int
    var presets: [Int]
    var onEdit: (ContentView.PlaceField) -> Void
    var onSwap: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                VStack(spacing: 0) {
                    placeRow(origin, placeholder: "Start wählen", symbol: "smallcircle.filled.circle",
                             color: Theme.accent, field: .origin)
                    Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1).padding(.leading, 44)
                    placeRow(destination, placeholder: "Ziel wählen", symbol: "mappin.circle.fill",
                             color: .pink, field: .destination)
                }
                Button(action: onSwap) {
                    Image(systemName: "arrow.up.arrow.down")
                        .display(.subheadline, weight: .bold)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 38, height: 38)
                        .background(Theme.accent.opacity(0.12), in: Circle())
                }
                .accessibilityLabel("Richtung tauschen")
            }
            HStack(spacing: 8) {
                StartTimePicker(startTime: $startTime, presets: presets)
                Spacer(minLength: 0)
                Chip(text: "\(prepMinutes) min Rüstzeit", symbol: "figure.walk.departure")
            }
        }
        .padding(14)
        .card()
        .padding(.horizontal, Theme.gutter)
    }

    private func placeRow(_ place: Place?, placeholder: String, symbol: String, color: Color,
                          field: ContentView.PlaceField) -> some View {
        Button { onEdit(field) } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 34)
                Text(place?.shortName ?? placeholder)
                    .display(.subheadline, weight: place == nil ? .regular : .semibold)
                    .foregroundStyle(place == nil ? .secondary : .primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel((field == .origin ? "Start: " : "Ziel: ") + (place?.name ?? "nicht gesetzt"))
    }
}

/// "Jetzt" or a chosen time for starting to get ready.
struct StartTimePicker: View {
    @Binding var startTime: PlanModel.StartTime
    var presets: [Int] = []

    private var label: String {
        switch startTime {
        case .now: "Jetzt"
        case .at(let d): Fmt.time(d)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                Button("Jetzt") { startTime = .now }
                ForEach(presets, id: \.self) { minutes in
                    Button(AppSettings.offsetTitle(minutes)) {
                        startTime = .at(.now.addingTimeInterval(Double(minutes) * 60))
                    }
                }
                Divider()
                Button("Andere Zeit …") { startTime = .at(.now.addingTimeInterval(1800)) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "clock").font(.caption)
                    Text(label)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Theme.accent.opacity(0.12), in: Capsule())
            }
            if case .at(let date) = startTime {
                DatePicker("", selection: Binding(get: { date }, set: { startTime = .at($0) }),
                           displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
            }
        }
    }
}

private struct MapTab: View {
    @Environment(AppSettings.self) private var settings
    var model: PlanModel

    var body: some View {
        VStack(spacing: 10) {
            TripMapPanel(options: model.options, selectedID: model.selected?.id,
                         waypoints: settings.waypoints) { model.selectedID = $0 }
                .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06))
                }
                .padding(.horizontal, Theme.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(model.options) { option in
                        Button { withAnimation(.snappy) { model.selectedID = option.id } } label: {
                            OptionChip(option: option, selected: option.id == model.selected?.id,
                                       recommended: option.id == model.recommended?.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 6)
            }
        }
    }
}

private struct OptionChip: View {
    var option: TripOption
    var selected: Bool
    var recommended: Bool

    /// Distance, lit junctions on bike routes, and changes of train.
    private var facts: String {
        var parts = [Fmt.km(option.totalDistance)]
        if let s = option.bikeRoute?.stats { parts.append("\(s.signals) Ampeln") }
        if let t = option.transferText { parts.append(t) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                LegChainView(option: option, compact: true)
                if recommended { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                if let rain = option.rain, rain.level > .dry {
                    Image(systemName: rain.level.symbol).font(.caption2).foregroundStyle(rain.level.color)
                }
            }
            Text("\(Fmt.time(option.leave))–\(Fmt.time(option.arrival))")
                .display(.subheadline).monospacedDigit()
            Text("\(Fmt.duration(option.duration)) · \(facts)")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(minWidth: 150, alignment: .leading)
        .background(selected ? option.mode.color.opacity(0.14) : Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                .strokeBorder(selected ? option.mode.color.opacity(0.7) : Color.primary.opacity(0.06),
                              lineWidth: selected ? 1.5 : 1)
        }
    }
}
