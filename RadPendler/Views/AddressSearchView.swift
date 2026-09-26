import MapKit
import SwiftUI

/// Die Adresssuche — ein eigener Bildschirm, und deshalb eine eigene Datei.
/// Sie steckte in `SettingsView`, weil sie von dort aus aufgerufen wird; mit
/// ihr waren es achthundert Zeilen, in denen fünf Bildschirme und ein
/// `MKLocalSearchCompleter` beieinanderlagen.
struct AddressSearchView: View {
    var title: String
    /// The start of a trip begins where one is standing — there "Mein Standort"
    /// sits at the top and is what a tap without typing takes.
    var offersLocation = false
    var onPick: (Place) -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var completer = AddressCompleter()
    @State private var location = LocationService()
    @State private var query = ""
    @State private var error: String?
    @State private var locating = false
    /// The address behind the current fix, looked up as soon as the search for
    /// a start opens with nothing set — so the first row is a real address and
    /// one tap is all it takes.
    @State private var here: Place?

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
            if offersLocation, location.permission != .denied {
                Section {
                    Button(action: useLocation) {
                        HStack(spacing: 10) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(Theme.accent, in: Circle())
                            VStack(alignment: .leading, spacing: 1) {
                                Text(here?.shortName ?? L("Mein Standort")).foregroundStyle(.primary)
                                Text(locating ? L("wird bestimmt …") : (here?.areaLine ?? L("dort, wo du gerade bist")))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if here != nil {
                                Image(systemName: "location.fill")
                                    .font(.caption2).foregroundStyle(Theme.accent)
                            }
                            Spacer(minLength: 0)
                            if locating { ProgressView() }
                        }
                    }
                    .disabled(locating)
                } header: {
                    Text(L("Vorschlag"))
                } footer: {
                    Hint(L("Wird einmal abgefragt und in eine Adresse übersetzt. Die App folgt dir nicht."))
                }
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
                Section(L("Schon benutzt")) {
                    ForEach(known) { use in
                        Button { pick(use.place) } label: { row(use) }
                            .swipeActions {
                                Button(L("Vergessen"), role: .destructive) { settings.forget(use) }
                            }
                    }
                }
            }
            if !completer.results.isEmpty {
                Section(known.isEmpty ? "" : L("Suche")) {
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
        .task {
            // Only unasked-for work the app does: with nothing set yet, the
            // start is almost always where one is standing. The address then
            // stands in the search field as the default, ready to take or to
            // type over.
            guard offersLocation, here == nil, location.permission == .allowed else { return }
            guard let fix = try? await location.current() else { return }
            let found = await location.place(for: fix)
            here = found
            if query.isEmpty { query = found.withArea }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: L("Adresse oder Ort"))
        .onChange(of: query) { completer.query = query }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if !offersLocation, named.isEmpty, known.isEmpty, completer.results.isEmpty, query.isEmpty {
                ContentUnavailableView(L("Noch keine Adresse"), systemImage: "magnifyingglass",
                                       description: Text(L("Tippen, um zu suchen. Was einmal gewählt wurde, steht beim nächsten Mal oben — je öfter benutzt, desto weiter oben.")))
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

    /// One fix, turned into an address, counted like any other pick.
    private func useLocation() {
        error = nil
        locating = true
        Task {
            defer { locating = false }
            do {
                if let here { return pick(here) }
                pick(await location.place(for: try await location.current()))
            } catch {
                self.error = error.localizedDescription
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
            guard let item = response.mapItems.first else { error = L("Adresse nicht gefunden"); return }
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


/// Was die App über das Tempo dieses Fahrers gemessen hat. Sie schreibt daraus
/// die Fahrgeschwindigkeit fort; hier steht, woher die Zahl kommt.
