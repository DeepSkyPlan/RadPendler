import SwiftUI

struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @State private var model = PlanModel()
    /// `-tab map` opens on the map (screenshots, UI tests).
    /// The map is the default; `-tab list` opens the list (screenshots, UI tests).
    @State private var tab = UserDefaults.standard.string(forKey: "tab") == "list" ? Tab.list : Tab.map
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

/// The route bar: one card with a rail from start to destination, a swap
/// button on the rail, and the departure times as chips underneath.
private struct RouteHeader: View {
    var origin: Place?
    var destination: Place?
    @Binding var startTime: PlanModel.StartTime
    var prepMinutes: Int
    var presets: [Int]
    var onEdit: (ContentView.PlaceField) -> Void
    var onSwap: () -> Void

    @State private var swapTurns = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                rail
                VStack(alignment: .leading, spacing: 12) {
                    field(origin, placeholder: "Start wählen", field: .origin)
                    field(destination, placeholder: "Ziel wählen", field: .destination)
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation(.snappy(duration: 0.35)) { swapTurns += 0.5 }
                    onSwap()
                } label: {
                    Image(systemName: "arrow.trianglehead.swap")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .rotationEffect(.degrees(swapTurns * 360))
                        .frame(width: 36, height: 36)
                        .background(Theme.accent.opacity(0.12), in: Circle())
                }
                .accessibilityLabel("Richtung tauschen")
            }
            DepartureChips(startTime: $startTime, presets: presets, prepMinutes: prepMinutes)
        }
        .padding(16)
        .card()
        .padding(.horizontal, Theme.gutter)
    }

    /// Dot, dotted line, pin — the visual spine of the card.
    private var rail: some View {
        VStack(spacing: 3) {
            Circle().strokeBorder(Theme.accent, lineWidth: 3).frame(width: 11, height: 11)
            VStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(Color.secondary.opacity(0.35)).frame(width: 2.5, height: 2.5)
                }
            }
            Image(systemName: "mappin.circle.fill").font(.system(size: 13)).foregroundStyle(.pink)
        }
        .padding(.vertical, 4)
    }

    private func field(_ place: Place?, placeholder: String, field: ContentView.PlaceField) -> some View {
        Button { onEdit(field) } label: {
            Text(place?.shortName ?? placeholder)
                .display(.headline, weight: place == nil ? .medium : .semibold)
                .foregroundStyle(place == nil ? .secondary : .primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel((field == .origin ? "Start: " : "Ziel: ") + (place?.name ?? "nicht gesetzt"))
    }
}

/// "Jetzt", the saved offsets and a free time, as a row of chips.
struct DepartureChips: View {
    @Binding var startTime: PlanModel.StartTime
    var presets: [Int]
    var prepMinutes: Int
    @State private var showPicker = false
    @State private var custom = Date.now.addingTimeInterval(1800)

    private var isCustom: Bool {
        if case .at(let d) = startTime { return !presets.contains { matches($0, d) } }
        return false
    }

    /// A preset stays selected for a minute, so the chip does not flicker.
    private func matches(_ minutes: Int, _ date: Date) -> Bool {
        abs(date.timeIntervalSinceNow - Double(minutes) * 60) < 60
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("Jetzt", active: startTime == .now) { startTime = .now }
                ForEach(presets, id: \.self) { m in
                    let active: Bool = if case .at(let d) = startTime { matches(m, d) } else { false }
                    chip(AppSettings.offsetTitle(m).replacingOccurrences(of: "in ", with: "+"), active: active) {
                        startTime = .at(.now.addingTimeInterval(Double(m) * 60))
                    }
                }
                chip(customLabel, symbol: "calendar", active: isCustom) { showPicker = true }
                Divider().frame(height: 16)
                Chip(text: "\(prepMinutes) min Rüstzeit", symbol: "figure.walk.departure")
            }
            .padding(.vertical, 1)
        }
        .scrollClipDisabled()
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                DatePicker("Startzeit", selection: $custom)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("Wann losgehen?")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Übernehmen") { startTime = .at(custom); showPicker = false }
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Abbrechen") { showPicker = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var customLabel: String {
        if case .at(let d) = startTime, isCustom { return Fmt.time(d) }
        return "Zeit"
    }

    private func chip(_ title: String, symbol: String? = nil, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.caption2) }
                Text(title).font(.system(.caption, design: .rounded, weight: .semibold))
            }
            .foregroundStyle(active ? .white : Theme.accent)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background {
                if active { Capsule().fill(Theme.gradient(Theme.accent)) }
                else { Capsule().fill(Theme.accent.opacity(0.10)) }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct MapTab: View {
    @Environment(AppSettings.self) private var settings
    var model: PlanModel


    var body: some View {
        if model.needsAddresses {
            ContentUnavailableView("Start und Ziel wählen", systemImage: "mappin.and.ellipse",
                                   description: Text("Oben auf die beiden Zeilen tippen. Die Adressen bleiben auf diesem Gerät."))
            Spacer()
        } else {
            map
        }
    }

    private var map: some View {
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
