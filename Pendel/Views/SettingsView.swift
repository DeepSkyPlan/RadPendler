import MapKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section("Adressen") {
                    NavigationLink {
                        AddressSearchView(title: "Start") { settings.origin = $0 }
                    } label: {
                        LabeledContent("Start", value: settings.origin.name)
                    }
                    NavigationLink {
                        AddressSearchView(title: "Ziel") { settings.destination = $0 }
                    } label: {
                        LabeledContent("Ziel", value: settings.destination.name)
                    }
                    Button("Büro → Beispielweg wiederherstellen") { settings.resetPlaces() }
                }
                Section {
                    Stepper("Rüstzeit: \(settings.prepMinutes) min", value: $settings.prepMinutes, in: 0...30)
                } footer: {
                    Text("Zeit vom Planen bis zum Losgehen. Gilt für jedes Verkehrsmittel.")
                }
                Section {
                    Stepper(value: $settings.bikeSpeedKmh, in: 10...40, step: 1) {
                        Text("Durchschnitt: \(Int(settings.bikeSpeedKmh)) km/h")
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
                    Text("Die Fahrzeit mit dem Rad wird aus der Streckenlänge und dieser Geschwindigkeit berechnet. Der Puffer gilt je Bahnhof für Rad schieben, Aufzug und Bahnsteig. Die Ampelwartezeit ist ein Mittelwert (etwa jede zweite ist grün) und wird je Ampelkreuzung auf der Strecke addiert. Für die ganze Strecke gibt es bis zu drei Routen: kürzest, Mittelweg und ruhigst (wenig Ampeln, wenig Hauptstraßen). Rad + Bahn nimmt nur Züge, für die die VBB-Auskunft Fahrradmitnahme meldet.")
                }
                Section {
                    Stepper("Umstieg zählt wie \(settings.transferPenaltyMinutes) min", value: $settings.transferPenaltyMinutes, in: 0...30)
                } header: {
                    Text("Umsteigen")
                } footer: {
                    Text("Beim Sortieren und Empfehlen wird jeder Umstieg wie so viele Minuten längere Fahrt gewertet. Eine direkte Verbindung gewinnt also, solange die mit Umstieg nicht mehr als diese Zeit früher ankommt.")
                }
                Section("Auto") {
                    Stepper("Parkplatzsuche: \(settings.parkingMinutes) min", value: $settings.parkingMinutes, in: 0...30)
                }
                Section("Datenquellen") {
                    Text("Fahrplan und Echtzeit: VBB-Fahrinfo (HAFAS)")
                    Text("Radrouten: BRouter (brouter.de) und Apple Karten; Autorouten: Apple Karten")
                    Text("Ampeln und Hauptstraßen: © OpenStreetMap-Mitwirkende (ODbL), via Overpass API")
                    Text("Regenradar: Deutscher Wetterdienst")
                    Text("Regen auf der Strecke: Open-Meteo.com (DWD ICON-D2), CC BY 4.0")
                }
                .font(.footnote)
                Section {
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                        .font(.footnote).foregroundStyle(.secondary)
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
