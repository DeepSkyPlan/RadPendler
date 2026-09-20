import SwiftUI

/// One screen: where from and to, when, the map, and one card per travel mode.
struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @State private var model = PlanModel()
    @State private var showSettings = false
    @State private var editing: PlaceField?

    /// Bike first, then bike+rail, car, and public transport.
    private let order: [TravelMode] = [.bike, .bikeTransit, .car, .transit]

    enum PlaceField: Identifiable {
        case origin, destination
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                ScrollView {
                    VStack(spacing: 14) {
                        RouteHeader(origin: settings.origin, destination: settings.destination,
                                    when: $model.when, prepMinutes: settings.prepMinutes,
                                    presets: settings.departurePresets, countdown: model.countdownOption,
                                    alerts: settings.alertsOn ? settings.alertMinutes : [],
                                    onEdit: { editing = $0 },
                                    onSwap: { settings.swapDirection(); model.applyDefaultWhen(settings: settings); refresh() },
                                    onWhenChange: refresh)
                        if model.needsAddresses {
                            ContentUnavailableView("Start und Ziel wählen", systemImage: "mappin.and.ellipse",
                                                   description: Text("Oben auf die beiden Zeilen tippen. Die Adressen bleiben auf diesem Gerät."))
                                .padding(.top, 40)
                        } else {
                            TripMapPanel(options: model.options, selectedID: model.selected?.id,
                                         waypoints: settings.waypoints,
                                         onSelect: { select($0) },
                                         onCycleBike: cycleBike)
                                .frame(height: 300)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.06))
                                }
                                .padding(.horizontal, Theme.gutter)
                            ForEach(order) { mode in
                                ModeBlock(model: model, mode: mode)
                                    .padding(.horizontal, Theme.gutter)
                            }
                            footer.padding(.horizontal, Theme.gutter + 4)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .refreshable { refresh() }
            }
            .navigationTitle("RadPendler")
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
            .sheet(item: $editing, onDismiss: {
                model.applyDefaultWhen(settings: settings)
                refresh()
            }) { field in
                NavigationStack {
                    AddressSearchView(title: field == .origin ? "Start" : "Ziel") { place in
                        if field == .origin { settings.origin = place } else { settings.destination = place }
                    }
                }
            }
            .task {
                model.applyDefaultWhen(settings: settings)
                refresh()
            }
        }
        .tint(Theme.accent)
    }

    private func refresh() {
        model.refresh(settings: settings)
    }

    private func select(_ id: TripOption.ID) {
        guard let option = model.options.first(where: { $0.id == id }) else { return }
        withAnimation(.snappy(duration: 0.2)) {
            model.activeMode = option.mode
            model.selection[option.mode] = id
        }
    }

    /// Long press on a bike line: step to the next bike route.
    private func cycleBike() {
        let bikes = model.options(for: .bike)
        guard bikes.count > 1 else { return }
        let current = model.selected(for: .bike)?.id
        let i = bikes.firstIndex { $0.id == current } ?? 0
        select(bikes[(i + 1) % bikes.count].id)
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// From, to, the countdown, and the time chips.
private struct RouteHeader: View {
    var origin: Place?
    var destination: Place?
    @Binding var when: PlanModel.When
    var prepMinutes: Int
    var presets: [DeparturePreset]
    var countdown: TripOption?
    var alerts: [Int]
    var onEdit: (ContentView.PlaceField) -> Void
    var onSwap: () -> Void
    var onWhenChange: () -> Void

    @State private var swapTurns = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                rail
                VStack(alignment: .leading, spacing: 12) {
                    field(origin, placeholder: "Start wählen", field: .origin)
                    field(destination, placeholder: "Ziel wählen", field: .destination)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    withAnimation(.snappy(duration: 0.35)) { swapTurns += 0.5 }
                    onSwap()
                } label: {
                    Image(systemName: "arrow.trianglehead.swap")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .rotationEffect(.degrees(swapTurns * 360))
                        .frame(width: 32, height: 32)
                        .background(Theme.accent.opacity(0.12), in: Circle())
                }
                .accessibilityLabel("Richtung tauschen")
                CountdownBox(option: countdown, alerts: alerts).frame(width: 108)
            }
            WhenPicker(when: $when, presets: presets, prepMinutes: prepMinutes, onChange: onWhenChange)
        }
        .padding(14)
        .card()
        .padding(.horizontal, Theme.gutter)
    }

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
                .display(.subheadline, weight: place == nil ? .medium : .semibold)
                .foregroundStyle(place == nil ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel((field == .origin ? "Start: " : "Ziel: ") + (place?.name ?? "nicht gesetzt"))
    }
}

/// Departure or arrival, plus the saved quick choices.
private struct WhenPicker: View {
    @Binding var when: PlanModel.When
    var presets: [DeparturePreset]
    var prepMinutes: Int
    var onChange: () -> Void
    @State private var showPicker = false
    @State private var custom = Date.now.addingTimeInterval(1800)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: Binding(get: { when.isArrival }, set: { toArrival($0) })) {
                Text("Abfahrt").tag(false)
                Text("Ankunft").tag(true)
            }
            .pickerStyle(.segmented)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if !when.isArrival {
                        chip("Jetzt", active: when == .departNow) { set(.departNow) }
                    }
                    ForEach(presets, id: \.self) { p in
                        chip(p.title, active: matches(p)) { set(stamp(p.date())) }
                    }
                    chip(customLabel, symbol: "calendar", active: isCustom) {
                        custom = when.date ?? .now.addingTimeInterval(1800)
                        showPicker = true
                    }
                    Chip(text: "\(prepMinutes) min Rüstzeit", symbol: "figure.walk.departure")
                }
                .padding(.horizontal, 2)
            }
        }
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                DatePicker(when.isArrival ? "Ankunft" : "Abfahrt", selection: $custom)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle(when.isArrival ? "Wann da sein?" : "Wann losgehen?")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Übernehmen") { set(stamp(custom)); showPicker = false }
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Abbrechen") { showPicker = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func stamp(_ date: Date) -> PlanModel.When {
        when.isArrival ? .arriveAt(date) : .departAt(date)
    }

    private func set(_ new: PlanModel.When) {
        when = new
        onChange()
    }

    private func toArrival(_ arrival: Bool) {
        let base = when.date ?? .now.addingTimeInterval(1800)
        set(arrival ? .arriveAt(base) : .departAt(base))
    }

    private func matches(_ p: DeparturePreset) -> Bool {
        guard let d = when.date else { return false }
        return abs(d.timeIntervalSince(p.date())) < 60
    }

    private var isCustom: Bool {
        guard let d = when.date else { return false }
        return !presets.contains { abs(d.timeIntervalSince($0.date())) < 60 }
    }

    private var customLabel: String {
        if let d = when.date, isCustom { return Fmt.time(d) }
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
