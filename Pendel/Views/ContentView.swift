import SwiftUI

struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @State private var model = PlanModel()
    /// `-tab map` opens on the map (screenshots, UI tests).
    @State private var tab = UserDefaults.standard.string(forKey: "tab") == "map" ? Tab.map : Tab.list
    @State private var showSettings = false
    @State private var editing: PlaceField?

    enum Tab: String, CaseIterable { case list = "Liste", map = "Karte" }

    enum PlaceField: Identifiable {
        case origin, destination
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Picker("Ansicht", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                switch tab {
                case .list: TripListView(model: model)
                case .map: MapTab(model: model)
                }
            }
            .navigationTitle("Pendel")
            .navigationBarTitleDisplayMode(.inline)
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
            .sheet(isPresented: $showSettings, onDismiss: refresh) {
                SettingsView()
            }
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
    }

    private func refresh() {
        model.refresh(settings: settings)
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    placeButton(settings.origin, symbol: "circle", field: .origin)
                    placeButton(settings.destination, symbol: "mappin.circle.fill", field: .destination)
                }
                Button {
                    settings.swapDirection()
                    refresh()
                } label: {
                    Image(systemName: "arrow.up.arrow.down").font(.title3)
                }
                .accessibilityLabel("Richtung tauschen")
            }
            HStack {
                StartTimePicker(startTime: $model.startTime)
                Spacer()
                Label("\(settings.prepMinutes) min Rüstzeit", systemImage: "figure.walk.departure")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func placeButton(_ place: Place, symbol: String, field: PlaceField) -> some View {
        Button { editing = field } label: {
            HStack {
                Image(systemName: symbol).foregroundStyle(field == .origin ? .green : .red)
                Text(place.name).lineLimit(1).foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6).padding(.horizontal, 10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel(field == .origin ? "Start: \(place.name)" : "Ziel: \(place.name)")
    }
}

/// "Jetzt" or a chosen time for starting to get ready.
struct StartTimePicker: View {
    @Binding var startTime: PlanModel.StartTime

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                Button("Jetzt") { startTime = .now }
                Button("Andere Zeit …") { startTime = .at(.now.addingTimeInterval(1800)) }
            } label: {
                Label(startTime == .now ? "Jetzt" : "Start", systemImage: "clock")
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
    var model: PlanModel

    var body: some View {
        VStack(spacing: 0) {
            TripMapPanel(options: model.options, selectedID: model.selected?.id) { model.selectedID = $0 }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(model.options) { option in
                        Button { model.selectedID = option.id } label: {
                            OptionChip(option: option, selected: option.id == model.selected?.id,
                                       recommended: option.id == model.recommended?.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
        }
    }
}

private struct OptionChip: View {
    var option: TripOption
    var selected: Bool
    var recommended: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: option.mode.symbol)
                if recommended { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                if let rain = option.rain, rain.level > .dry {
                    Image(systemName: rain.level.symbol).font(.caption2).foregroundStyle(rain.level.color)
                }
            }
            Text("\(Fmt.time(option.leave))–\(Fmt.time(option.arrival))").font(.caption.monospacedDigit())
            Text(RouteMapView.Coordinator.labelText(option)).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(8)
        .background(selected ? option.mode.color.opacity(0.2) : Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? option.mode.color : .clear, lineWidth: 2))
    }
}
