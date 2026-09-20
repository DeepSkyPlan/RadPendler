import MapKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        AddressSearchView(title: "Start") { settings.origin = $0 }
                    } label: {
                        LabeledContent("Start", value: settings.origin?.name ?? "nicht gesetzt")
                    }
                    NavigationLink {
                        AddressSearchView(title: "Ziel") { settings.destination = $0 }
                    } label: {
                        LabeledContent("Ziel", value: settings.destination?.name ?? "nicht gesetzt")
                    }
                    Button("Beide Adressen löschen", role: .destructive) { settings.clearPlaces() }
                } header: {
                    Text("Adressen")
                } footer: {
                    Text("Die App wird ohne Adressen ausgeliefert. Start und Ziel bleiben nur auf diesem Gerät gespeichert.")
                }
                Section {
                    Stepper("Rüstzeit: \(settings.prepMinutes) min", value: $settings.prepMinutes, in: 0...30)
                } footer: {
                    Text("Zeit vom Planen bis zum Losgehen. Gilt für jedes Verkehrsmittel.")
                }
                Section {
                    Stepper(value: $settings.bikeSpeedKmh, in: 10...45, step: 1) {
                        Text("Fahrgeschwindigkeit: \(Int(settings.bikeSpeedKmh)) km/h")
                    }
                    Stepper("Puffer am Bahnhof: \(settings.bikeStationBufferMinutes) min",
                            value: $settings.bikeStationBufferMinutes, in: 0...10)
                    Stepper("Wartezeit je Ampel: \(settings.signalWaitSeconds) s",
                            value: $settings.signalWaitSeconds, in: 0...90, step: 5)
                    Stepper(value: $settings.maxBikeToStationKm, in: 1...10, step: 0.5) {
                        Text("Radweg zum Bahnhof: bis \(settings.maxBikeToStationKm.formatted(.number.precision(.fractionLength(0...1)))) km")
                    }
                } header: {
                    Text("Fahrrad")
                } footer: {
                    Text("Fahrgeschwindigkeit = Tempo beim Rollen, ohne Halte. Die Fahrzeit ist Strecke ÷ Fahrgeschwindigkeit plus die Wartezeit je Ampelkreuzung (inkl. Anfahren); daraus ergibt sich der angezeigte Schnitt „Ø … km/h“. Der Puffer gilt je Bahnhof für Rad schieben, Aufzug und Bahnsteig. Die Ampelwartezeit ist ein Mittelwert (etwa jede zweite ist grün) und wird je Ampelkreuzung auf der Strecke addiert. Für die ganze Strecke gibt es bis zu drei Routen: kürzest, Mittelweg und ruhigst (wenig Ampeln, wenig Hauptstraßen). Rad + Bahn nimmt nur Züge, für die die VBB-Auskunft Fahrradmitnahme meldet.")
                }
                Section {
                    Stepper("Umstieg zählt wie \(settings.transferPenaltyMinutes) min", value: $settings.transferPenaltyMinutes, in: 0...30)
                } header: {
                    Text("Umsteigen")
                } footer: {
                    Text("Beim Sortieren und Empfehlen wird jeder Umstieg wie so viele Minuten längere Fahrt gewertet. Eine direkte Verbindung gewinnt also, solange die mit Umstieg nicht mehr als diese Zeit früher ankommt.")
                }
                Section {
                    ForEach(settings.departurePresets, id: \.self) { p in
                        Text(p.title)
                    }
                    .onDelete { settings.departurePresets.remove(atOffsets: $0) }
                    Menu {
                        ForEach(DeparturePreset.choices, id: \.self) { p in
                            Button(p.title) {
                                guard !settings.departurePresets.contains(p) else { return }
                                settings.departurePresets.append(p)
                            }
                        }
                    } label: {
                        Label("Zeitpunkt hinzufügen", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Startzeiten")
                } footer: {
                    Text("Diese Vorschläge stehen oben neben „Jetzt“ zur Wahl — relativ („in 15 min“) oder als Uhrzeit („um 8 Uhr“, heute oder morgen).")
                }
                Section {
                    Picker("Arbeitsadresse", selection: Binding(
                        get: { settings.isWork(settings.destination) ? 1 : (settings.isWork(settings.origin) ? 0 : 2) },
                        set: { settings.workPlace = $0 == 0 ? settings.origin : ($0 == 1 ? settings.destination : nil) })) {
                        Text(settings.origin?.shortName ?? "Start").tag(0)
                        Text(settings.destination?.shortName ?? "Ziel").tag(1)
                        Text("keine").tag(2)
                    }
                    DatePicker("Dort sein um", selection: Binding(
                        get: { DeparturePreset.clock(settings.workArrivalMinutes / 60, settings.workArrivalMinutes % 60).date() },
                        set: { d in
                            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                            settings.workArrivalMinutes = (c.hour ?? 9) * 60 + (c.minute ?? 0)
                        }), displayedComponents: .hourAndMinute)
                } header: {
                    Text("Arbeitsweg")
                } footer: {
                    Text("Fahrten zur Arbeitsadresse starten mit „Ankunft um …“, Fahrten nach Hause mit „Abfahrt jetzt“. Von Hand umschaltbar.")
                }
                Section {
                    Stepper("Puffer vor der Abfahrt: \(settings.departureBufferMinutes) min",
                            value: $settings.departureBufferMinutes, in: 0...30)
                    Stepper("Puffer vor der Ankunft: \(settings.arrivalBufferMinutes) min",
                            value: $settings.arrivalBufferMinutes, in: 0...30)
                } header: {
                    Text("Puffer")
                } footer: {
                    Text("Der Abfahrtspuffer verschiebt das Losgehen nach vorn, der Ankunftspuffer lässt die Verbindung früher ankommen. Beide zählen nicht zur angezeigten Fahrzeit.")
                }
                Section {
                    Toggle("Warnton vor der Abfahrt", isOn: $settings.alertsOn)
                    if settings.alertsOn {
                        ForEach([15, 10, 5, 3, 1], id: \.self) { m in
                            Toggle("\(m) min vorher", isOn: Binding(
                                get: { settings.alertMinutes.contains(m) },
                                set: { on in
                                    if on { settings.alertMinutes = (settings.alertMinutes + [m]).sorted(by: >) }
                                    else { settings.alertMinutes.removeAll { $0 == m } }
                                }))
                        }
                    }
                } header: {
                    Text("Countdown")
                } footer: {
                    Text("Der Countdown oben rechts zählt bis zum Losgehen für Bahn und Bus — und bei „Ankunft um …“ für jede Fahrt. Der Ton kommt nur, solange die App offen ist.")
                }
                Section {
                    ForEach(settings.waypoints, id: \.self) { p in
                        Label(p.shortName, systemImage: "mappin.and.ellipse")
                    }
                    .onDelete { settings.waypoints.remove(atOffsets: $0) }
                    NavigationLink {
                        AddressSearchView(title: "Fixpunkt") { settings.waypoints.append($0) }
                    } label: {
                        Label("Fixpunkt hinzufügen", systemImage: "plus.circle")
                    }
                    if settings.waypoints.count > 1 {
                        Toggle("Alle Fixpunkte verlangen", isOn: $settings.requireAllWaypoints)
                    }
                } header: {
                    Text("Fixpunkte")
                } footer: {
                    Text("Punkte, über die die Strecke führen soll, z. B. „S Musterhausen“ oder „Berlin Hauptbahnhof“. Verbindungen, die nicht daran vorbeikommen, werden ausgegraut ans Ende gestellt und nie empfohlen. Ohne Fixpunkte gilt keine Einschränkung.")
                }
                Section("Auto") {
                    Stepper("Parkplatzsuche: \(settings.parkingMinutes) min", value: $settings.parkingMinutes, in: 0...30)
                }
                Section {
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                } header: {
                    Text("Daten, Rechte und Version")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Fahrplan und Echtzeit: VBB Verkehrsverbund Berlin-Brandenburg (HAFAS-Fahrinfo).")
                        Text("Karten, Adresssuche und Autorouten: Apple Karten. © Apple Inc. und Mitwirkende.")
                        Text("Radrouten: BRouter (brouter.de), auf Basis von OpenStreetMap.")
                        Text("Ampeln, Straßen und Kartendaten: © OpenStreetMap-Mitwirkende, ODbL 1.0, abgefragt über die Overpass API.")
                        Text("Regenradar und Niederschlagsvorhersage: Deutscher Wetterdienst (DWD), Datenlizenz Deutschland – Namensnennung 2.0.")
                        Text("Regen entlang der Strecke: Open-Meteo.com, CC BY 4.0, auf Basis von DWD ICON-D2.")
                        Text("© 2026 AK. Alle Zeiten ohne Gewähr.")
                    }
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
    }
}

/// Address search with Apple's autocomplete; resolves the pick to coordinates.
struct AddressSearchView: View {
    var title: String
    var onPick: (Place) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var completer = AddressCompleter()
    @State private var query = ""
    @State private var error: String?

    var body: some View {
        List {
            if let error {
                Text(error).foregroundStyle(.orange)
            }
            ForEach(completer.results, id: \.self) { r in
                Button {
                    Task { await pick(r) }
                } label: {
                    VStack(alignment: .leading) {
                        Text(r.title).foregroundStyle(.primary)
                        if !r.subtitle.isEmpty { Text(r.subtitle).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Adresse oder Ort")
        .onChange(of: query) { completer.query = query }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func pick(_ r: MKLocalSearchCompletion) async {
        do {
            let response = try await MKLocalSearch(request: MKLocalSearch.Request(completion: r)).start()
            guard let item = response.mapItems.first else { error = "Adresse nicht gefunden"; return }
            let name = [r.title, r.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
            let c = item.placemark.coordinate
            onPick(Place(name: name, latitude: c.latitude, longitude: c.longitude))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

@Observable
final class AddressCompleter: NSObject, MKLocalSearchCompleterDelegate {
    var results: [MKLocalSearchCompletion] = []
    var query = "" { didSet { completer.queryFragment = query } }
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        // Berlin/Brandenburg first.
        completer.region = MKCoordinateRegion(center: .init(latitude: 52.47, longitude: 13.35),
                                              latitudinalMeters: 80_000, longitudinalMeters: 80_000)
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }
}
