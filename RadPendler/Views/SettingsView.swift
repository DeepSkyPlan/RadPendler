import MapKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    /// Whether iOS lets the app post the countdown warnings at all.
    @State private var notifications: Alarm.Permission = .unknown

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        AddressSearchView(title: "Start") { settings.origin = $0 }
                    } label: {
                        LabeledContent("Start", value: settings.origin?.withArea ?? "nicht gesetzt")
                    }
                    NavigationLink {
                        AddressSearchView(title: "Ziel") { settings.destination = $0 }
                    } label: {
                        LabeledContent("Ziel", value: settings.destination?.withArea ?? "nicht gesetzt")
                    }
                    Button("Beide Adressen löschen", role: .destructive) { settings.clearPlaces() }
                } header: {
                    Text("Adressen")
                } footer: {
                    Text(CloudStore.shared.available
                         ? "Die App wird ohne Adressen ausgeliefert. Start, Ziel, die benutzten Adressen und alle Einstellungen gleichen sich über deine iCloud mit deinen anderen Geräten ab — sonst verlässt nichts davon deine Geräte."
                         : "Die App wird ohne Adressen ausgeliefert. Start und Ziel bleiben nur auf diesem Gerät gespeichert. Mit einem angemeldeten iCloud-Konto gleichen sie sich mit deinen anderen Geräten ab.")
                }
                Section {
                    NavigationLink {
                        PriorityList(title: "Verkehrsmittel", items: $settings.modeOrder,
                                     footer: "Von oben nach unten: was gewinnt, wenn zwei Fahrten fast gleichzeitig ankommen. Auch die Reihenfolge der vier Kästen auf der Hauptseite.",
                                     label: \.title, symbol: \.symbol)
                    } label: {
                        LabeledContent("Verkehrsmittel", value: settings.modeOrder.map(\.short).joined(separator: " › "))
                    }
                    NavigationLink {
                        PriorityList(title: "Radrouten", items: $settings.bikeVariantOrder,
                                     footer: "Welche der gefundenen Radrouten vorgeschlagen wird — die oberste. Die anderen bleiben erreichbar, ein Tipp auf den Kasten schaltet weiter.",
                                     label: \.title, symbol: \.symbol)
                    } label: {
                        LabeledContent("Radrouten", value: settings.bikeVariantOrder.first?.title ?? "")
                    }
                    NavigationLink {
                        PriorityList(title: "Autorouten", items: $settings.carVariantOrder,
                                     footer: "Dasselbe fürs Auto. Apple Karten liefert meist zwei oder drei Linien; welche davon oben steht, entscheidet diese Liste.",
                                     label: \.title, symbol: { _ in nil })
                    } label: {
                        LabeledContent("Autorouten", value: settings.carVariantOrder.first?.title ?? "")
                    }
                    Picker("Rad in die Bahn ab", selection: $settings.rainSwitchLevel) {
                        ForEach([RainLevel.possible, .light, .rain, .heavy], id: \.self) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    Button("Zurück auf Werkseinstellung") { settings.resetPriorities() }
                } header: {
                    Text("Vorlieben")
                } footer: {
                    Text("Womit die App plant, wenn sie die Wahl hat. Ab dem gewählten Regen wird nicht mehr die ganze Strecke geradelt, sondern das Rad in die Bahn gestellt — „starker Regen“ heißt also praktisch immer fahren.")
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
                    Picker("Fahrplan", selection: $settings.timetableSource) {
                        ForEach(TimetableSource.allCases) { Text($0.title).tag($0) }
                    }
                    Link(destination: URL(string: "https://transitous.org/sources/")!) {
                        Label("transitous.org/sources", systemImage: "arrow.up.right.square")
                    }
                    Link(destination: URL(string: "https://www.openstreetmap.org/copyright")!) {
                        Label("openstreetmap.org/copyright", systemImage: "arrow.up.right.square")
                    }
                } header: {
                    Text("Fahrplanquelle")
                } footer: {
                    Text("„Automatisch“ fragt den VBB, solange Start und Ziel in Berlin/Brandenburg liegen — dort ist er genauer und sagt als Einziger, welcher Zug Räder mitnimmt. Alles darüber hinaus beantwortet Transitous, eine von Freiwilligen betriebene MOTIS-Instanz auf dem bundesweiten DELFI-Datensatz. Transitous plant Rad und Bahn in einem Zug und sucht sich die Bahnhöfe selbst. Woher deren Daten kommen, steht hinter dem Link.")
                }
                Section {
                    NavigationLink {
                        BikeLinesView()
                    } label: {
                        LabeledContent("Fahrradmitnahme") {
                            let open = settings.bikeLines.filter { $0.allowed == nil }.count
                            Text(settings.bikeLines.isEmpty ? "noch keine Linie"
                                 : (open == 0 ? "alle geklärt" : "\(open) offen"))
                                .foregroundStyle(open > 0 ? .orange : .secondary)
                        }
                    }
                } footer: {
                    Text("Welche Linien das Rad mitnehmen, weißt du besser als jeder Fahrplan. Die Liste füllt sich mit den Linien, die in gefundenen Verbindungen vorkommen; was die Auskunft selbst zusichert, steht schon auf „ja“. Solange eine Linie offen ist, wird die Fahrt trotzdem vorgeschlagen — mit dem Hinweis, dass die Mitnahme ungeklärt ist.")
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
                    ForEach(PlaceRole.allCases, id: \.self) { role in
                        NavigationLink {
                            AddressSearchView(title: role.title) { settings.setPlace($0, for: role) }
                        } label: {
                            LabeledContent {
                                Text(settings.place(for: role)?.withArea ?? "nicht gesetzt")
                            } label: {
                                Label(role.title, systemImage: role.symbol)
                            }
                        }
                    }
                    if settings.homePlace != nil || settings.workPlace != nil {
                        Button("Beide vergessen", role: .destructive) {
                            settings.homePlace = nil
                            settings.workPlace = nil
                        }
                    }
                    DatePicker("Bei der Arbeit sein um", selection: Binding(
                        get: { DeparturePreset.clock(settings.workArrivalMinutes / 60, settings.workArrivalMinutes % 60).date() },
                        set: { d in
                            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                            settings.workArrivalMinutes = (c.hour ?? 9) * 60 + (c.minute ?? 0)
                        }), displayedComponents: .hourAndMinute)
                } header: {
                    Text("Zuhause und Arbeit")
                } footer: {
                    Text("Diese zwei bekommen überall ein Zeichen — in der Adresssuche, in der Liste der benutzten Adressen und oben auf der Hauptseite — und stehen in der Suche ganz oben. Fahrten zur Arbeit starten mit „Ankunft um …“, Fahrten nach Hause mit „Abfahrt jetzt“; von Hand umschaltbar.")
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
                    Toggle("Warnung vor dem Losgehen", isOn: $settings.alertsOn)
                    if settings.alertsOn {
                        ForEach([15, 10, 5, 3, 1], id: \.self) { m in
                            Toggle("\(m) min vorher", isOn: Binding(
                                get: { settings.alertMinutes.contains(m) },
                                set: { on in
                                    if on { settings.alertMinutes = (settings.alertMinutes + [m]).sorted(by: >) }
                                    else { settings.alertMinutes.removeAll { $0 == m } }
                                }))
                        }
                        if notifications == .denied {
                            Button {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                Label("Mitteilungen sind aus — in den iOS-Einstellungen erlauben",
                                      systemImage: "bell.slash")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                } header: {
                    Text("Countdown")
                } footer: {
                    Text("Der Countdown oben rechts zählt bis zum Losgehen für Bahn und Bus — und bei „Ankunft um …“ für jede Fahrt. Warnungen kommen als Mitteilung, auch wenn die App zu ist; bei offener App zusätzlich als Ton.")
                }
                Section {
                    ForEach(settings.waypoints, id: \.self) { p in
                        Label(p.withArea, systemImage: "mappin.and.ellipse")
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
                    Text("Punkte, über die die Strecke führen soll, z. B. „S Ostkreuz“ oder „Berlin Hauptbahnhof“. Verbindungen, die nicht daran vorbeikommen, werden ausgegraut ans Ende gestellt und nie empfohlen. Ohne Fixpunkte gilt keine Einschränkung.")
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
            // Asking iOS every time the sheet opens, so the hint disappears as
            // soon as the permission is granted somewhere else.
            .task { notifications = await Alarm.permission() }
            .onChange(of: settings.alertsOn) { _, on in
                guard on else { return }
                Task { notifications = await Alarm.requestPermission() ? .granted : .denied }
            }
        }
    }
}

/// The lines the app has met, and what the user says about taking the bike on
/// each. Lines arrive by themselves out of the found routes; a line that has
/// not turned up yet can be added by hand.
struct BikeLinesView: View {
    @Environment(AppSettings.self) private var settings
    @State private var newLine = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Linie, z. B. RE 7", text: $newLine)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .onSubmit(add)
                    Button("Hinzufügen", action: add)
                        .disabled(newLine.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("Für Linien, die noch in keiner Verbindung vorkamen.")
            }
            if settings.bikeLines.isEmpty {
                Section {
                    Text("Noch keine Linie. Sobald die App eine Verbindung mit Bahn oder Bus findet, stehen deren Linien hier.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(settings.bikeLines.sortedForList) { line in
                        HStack(spacing: 10) {
                            Text(line.name)
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 5))
                            Spacer(minLength: 0)
                            Picker("", selection: Binding(
                                get: { line.allowed },
                                set: { settings.setBikeLine(line.name, allowed: $0) })) {
                                Text("Rad ja").tag(Bool?.some(true))
                                Text("Rad nein").tag(Bool?.some(false))
                                Text("offen").tag(Bool?.none)
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .tint(line.allowed == nil ? .orange : .secondary)
                        }
                        .swipeActions {
                            Button("Löschen", role: .destructive) {
                                settings.bikeLines.removeAll { $0.name == line.name }
                            }
                        }
                    }
                } header: {
                    Text("Gesehene Linien")
                } footer: {
                    Text("„offen“ heißt: die Verbindung wird weiter vorgeschlagen, aber mit dem Hinweis, dass die Mitnahme ungeklärt ist. „Rad nein“ nimmt sie aus den Rad + Bahn-Vorschlägen heraus.")
                }
            }
        }
        .navigationTitle("Fahrradmitnahme")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func add() {
        let name = newLine.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        settings.setBikeLine(name, allowed: true)
        newLine = ""
    }
}

/// "Zuhause" or "Arbeit" as a small capsule — the mark those two addresses
/// carry everywhere they appear.
struct RoleBadge: View {
    var role: PlaceRole
    var compact = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: role.symbol).font(.system(size: compact ? 8 : 9, weight: .semibold))
            if !compact {
                Text(role.title).font(.system(size: 10, weight: .semibold, design: .rounded))
            }
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, compact ? 4 : 6)
        .padding(.vertical, 2)
        .background(Theme.accent.opacity(0.12), in: Capsule())
        .accessibilityLabel(role.title)
    }
}

/// One list of preferences, dragged into the order the user wants. No edit
/// button: with three or four rows, always-on dragging is less in the way than
/// a mode to switch into.
private struct PriorityList<T: Hashable>: View {
    var title: String
    @Binding var items: [T]
    var footer: String
    var label: (T) -> String
    var symbol: (T) -> String?

    var body: some View {
        List {
            Section {
                ForEach(Array(items.enumerated()), id: \.element) { index, item in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(.footnote, design: .rounded, weight: .bold))
                            .foregroundStyle(index == 0 ? Theme.accent : .secondary)
                            .frame(width: 16)
                        if let s = symbol(item) {
                            Image(systemName: s).foregroundStyle(.secondary).frame(width: 22)
                        }
                        Text(label(item))
                        Spacer(minLength: 0)
                    }
                }
                .onMove { items.move(fromOffsets: $0, toOffset: $1) }
            } footer: {
                Text(footer)
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Address search: the addresses already used, most used first, and Apple's
/// autocomplete underneath. Everything is shown with its postal code, because
/// a street name alone is not an address in Berlin.
struct AddressSearchView: View {
    var title: String
    var onPick: (Place) -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var completer = AddressCompleter()
    @State private var query = ""
    @State private var error: String?

    private var known: [PlaceUse] { settings.placeHistory.matching(query) }

    /// The two named addresses, when they exist and match what is typed.
    private var named: [(PlaceRole, Place)] {
        PlaceRole.allCases.compactMap { role in
            guard let place = settings.place(for: role) else { return nil }
            let q = query.trimmingCharacters(in: .whitespaces)
            guard q.isEmpty || place.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    || role.title.range(of: q, options: [.caseInsensitive]) != nil else { return nil }
            return (role, place)
        }
    }

    var body: some View {
        List {
            if let error {
                Text(error).foregroundStyle(.orange)
            }
            if !named.isEmpty {
                Section {
                    ForEach(named, id: \.0) { role, place in
                        Button { pick(place) } label: {
                            HStack(spacing: 10) {
                                RoleBadge(role: role)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(place.shortName).foregroundStyle(.primary)
                                    if let area = place.areaLine {
                                        Text(area).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
            if !known.isEmpty {
                Section("Schon benutzt") {
                    ForEach(known) { use in
                        Button { pick(use.place) } label: { row(use) }
                            .swipeActions {
                                Button("Vergessen", role: .destructive) { settings.forget(use) }
                            }
                    }
                }
            }
            if !completer.results.isEmpty {
                Section(known.isEmpty ? "" : "Suche") {
                    ForEach(completer.results, id: \.self) { r in
                        Button {
                            Task { await resolve(r) }
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.title).foregroundStyle(.primary)
                                if !r.subtitle.isEmpty {
                                    Text(r.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Adresse oder Ort")
        .onChange(of: query) { completer.query = query }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if named.isEmpty && known.isEmpty && completer.results.isEmpty && query.isEmpty {
                ContentUnavailableView("Noch keine Adresse", systemImage: "magnifyingglass",
                                       description: Text("Tippen, um zu suchen. Was einmal gewählt wurde, steht beim nächsten Mal oben — je öfter benutzt, desto weiter oben."))
            }
        }
    }

    /// One remembered address: street big, postal code and town under it, and
    /// how often it was used — the reason it stands where it stands.
    private func row(_ use: PlaceUse) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(use.place.shortName).foregroundStyle(.primary)
                    if let role = settings.role(of: use.place) { RoleBadge(role: role) }
                }
                if let area = use.place.areaLine {
                    Text(area).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if use.count > 1 {
                Text("\(use.count)×")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func pick(_ place: Place) {
        settings.remember(place)
        onPick(place)
        dismiss()
    }

    /// Turns a completion into a place — and builds the name from the placemark
    /// so the postal code is a field, not something to parse back out later.
    private func resolve(_ r: MKLocalSearchCompletion) async {
        do {
            let response = try await MKLocalSearch(request: MKLocalSearch.Request(completion: r)).start()
            guard let item = response.mapItems.first else { error = "Adresse nicht gefunden"; return }
            let mark = item.placemark
            let area = [mark.postalCode, mark.locality].compactMap { $0 }.joined(separator: " ")
            let name = area.isEmpty ? [r.title, r.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
                                    : "\(r.title), \(area)"
            let c = mark.coordinate
            pick(Place(name: name, latitude: c.latitude, longitude: c.longitude,
                       postalCode: mark.postalCode, locality: mark.locality))
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
