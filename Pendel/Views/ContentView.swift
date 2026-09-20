import SwiftUI

/// One screen: where from and to, when, the map, and the four modes as a strip
/// of boxes with the chosen route in one line underneath.
struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @State private var model = PlanModel()
    @State private var showSettings = false
    @State private var showHelp = false
    @State private var editing: PlaceField?

    enum PlaceField: Identifiable {
        case origin, destination
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                ScrollView {
                    VStack(spacing: 12) {
                        RouteHeader(origin: settings.origin, destination: settings.destination,
                                    when: $model.when, prepMinutes: settings.prepMinutes,
                                    presets: settings.departurePresets, countdown: model.countdownOption,
                                    alerts: settings.alertsOn ? settings.alertMinutes : [],
                                    loading: model.isLoading,
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
                                         onCycleBike: { model.cycle(.bike) })
                                .frame(height: 320)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.06))
                                }
                                .padding(.horizontal, Theme.gutter)
                            ModeStrip(model: model)
                                .padding(.horizontal, Theme.gutter)
                            if let option = model.selected {
                                SelectedTripBar(model: model, option: option)
                                    .padding(.horizontal, Theme.gutter)
                            }
                            footer.padding(.horizontal, Theme.gutter + 4)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .refreshable { await model.refreshAndWait(settings: settings) }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 7) {
                        AppMark(size: 22)
                        Text("RadPendler").display(.headline)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("RadPendler")
                }
                ToolbarItem(placement: .topBarTrailing) { menu }
            }
            .sheet(isPresented: $showSettings, onDismiss: refresh) { SettingsView() }
            .sheet(isPresented: $showHelp) { HelpView() }
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

    /// Everything that is not the plan itself, behind one quiet button.
    /// Refreshing lives in the pull, not in a button.
    private var menu: some View {
        Menu {
            Button { showSettings = true } label: { Label("Einstellungen", systemImage: "gearshape") }
            Button { showHelp = true } label: { Label("Anleitung", systemImage: "questionmark.circle") }
            Section("RadPendler \(Self.version)") {
                Button {} label: { Text("© 2026 AK") }.disabled(true)
                Button {} label: { Text("Daten: VBB · Apple Karten · BRouter/OSM · DWD · Open-Meteo") }.disabled(true)
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .semibold))
        }
        .accessibilityLabel("Menü")
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
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

    @ViewBuilder private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let rainFailure = model.result.rainFailure {
                Label(rainFailure, systemImage: "cloud.slash").foregroundStyle(.orange)
            }
            if let last = model.lastRun {
                Text("Stand \(Fmt.time(last)) · zum Aktualisieren nach unten ziehen")
                Text("Rad \(Int(settings.bikeSpeedKmh)) km/h + \(settings.signalWaitSeconds) s/Ampel · Fahrplan VBB · Karten Apple · Radrouten BRouter/OSM · Regen DWD und Open-Meteo")
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
    var loading: Bool
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
                if loading { ProgressView().padding(.trailing, 2) }
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
                // Only where a departure is fixed: trains and buses, or a wanted
                // arrival time. Otherwise the box stays away entirely.
                if let countdown {
                    CountdownBox(option: countdown, alerts: alerts).frame(width: 108)
                }
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

/// Departure or arrival, plus the quick choices. Departure offers the saved
/// presets; arrival only the two times a commute actually has — there at 9,
/// home by 19 — and the clock for everything else.
private struct WhenPicker: View {
    @Binding var when: PlanModel.When
    var presets: [DeparturePreset]
    var prepMinutes: Int
    var onChange: () -> Void
    @State private var showPicker = false
    @State private var custom = Date.now.addingTimeInterval(1800)

    /// The two arrival times worth a chip; everything else goes through the clock.
    static let arrivalPresets: [DeparturePreset] = [.clock(9, 0), .clock(19, 0)]

    private var chips: [DeparturePreset] { when.isArrival ? Self.arrivalPresets : presets }

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
                    ForEach(chips, id: \.self) { p in
                        chip(p.title, active: matches(p)) { set(stamp(p.date())) }
                    }
                    chip(customLabel, symbol: "clock", active: isCustom) {
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
        // Switching to "be there at": start at the next of the two commute
        // times instead of keeping a departure time that means nothing now.
        let base = arrival ? (Self.arrivalPresets.map { $0.date() }.min() ?? .now)
                           : (when.date ?? .now.addingTimeInterval(1800))
        set(arrival ? .arriveAt(base) : .departAt(base))
    }

    private func matches(_ p: DeparturePreset) -> Bool {
        guard let d = when.date else { return false }
        return abs(d.timeIntervalSince(p.date())) < 60
    }

    private var isCustom: Bool {
        guard let d = when.date else { return false }
        return !chips.contains { abs(d.timeIntervalSince($0.date())) < 60 }
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
