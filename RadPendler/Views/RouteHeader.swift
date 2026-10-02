import SwiftUI
import TipKit

// Die Kopfzeile des Hauptbildschirms: Start, Ziel, Abfahrt oder Ankunft und
// die Zeitwahl — lag bis 1.9.1 mit in ContentView.swift.

/// From, to, departure-or-arrival, and the time chips.
struct RouteHeader: View {
    var origin: Place?
    var destination: Place?
    @Binding var when: PlanModel.When
    var prepMinutes: Int
    var presets: [DeparturePreset]
    /// Whether this address is the user's home or work, for the little mark.
    var role: (Place?) -> PlaceRole?
    var onEdit: (ContentView.PlaceField) -> Void
    /// Double tap anywhere on the box: the commute, without typing (`tap`).
    var onQuickCommute: () -> Void
    var onSwap: () -> Void
    var onWhenChange: () -> Void
    /// Die Fixpunkte dieser Strecke; nil, solange Start oder Ziel fehlt.
    var waypoints: [Place]? = nil
    var onWaypoints: () -> Void = {}

    @State private var swapTurns = 0.0
    /// Der erste Tipp, der noch auf seinen zweiten wartet — für die **ganze**
    /// Box, nicht je Zeile.
    @State private var pendingTap: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Abfahrt/Ankunft rides beside the two addresses: two lines there,
            // two lines here, and a whole row saved.
            HStack(alignment: .center, spacing: 10) {
                rail
                VStack(alignment: .leading, spacing: waypoints == nil ? 10 : 3) {
                    field(origin, placeholder: L("Start wählen"), field: .origin)
                    if let waypoints { via(waypoints) }
                    field(destination, placeholder: L("Ziel wählen"), field: .destination)
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
                .accessibilityLabel(L("Richtung tauschen"))
                ArrivalToggle(when: $when, onChange: onWhenChange)
            }
            WhenPicker(when: $when, presets: presets, prepMinutes: prepMinutes, onChange: onWhenChange)
        }
        .padding(14)
        .card()
        // The empty parts of the box answer to the double tap as well, so it
        // does not matter where exactly it lands.
        .contentShape(Rectangle())
        .onTapGesture { tap(nil) }
        .popoverTip(QuickCommuteTip(), arrowEdge: .top)
        .padding(.horizontal, Theme.gutter)
    }

    /// Zwischen Start und Ziel, klein: über welche Fixpunkte diese Strecke
    /// führt — oder das Angebot, einen zu setzen. Sie gehören zur Strecke,
    /// also stehen sie hier und nicht in den allgemeinen Einstellungen.
    private func via(_ points: [Place]) -> some View {
        Button(action: onWaypoints) {
            Label(points.isEmpty ? L("Fixpunkt") : L("über %@", points.map(\.shortName).joined(separator: " · ")),
                  systemImage: points.isEmpty ? "plus" : "mappin.and.ellipse")
                .font(.system(.caption2, design: .rounded).weight(.medium))
                .foregroundStyle(points.isEmpty ? Color.secondary : Theme.accent)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(points.isEmpty ? L("Fixpunkt hinzufügen")
                            : L("über %@", points.map(\.shortName).joined(separator: ", ")))
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

    /// Ein Tipp öffnet die Adresssuche, zwei kurz hintereinander setzen die
    /// Pendelstrecke — **egal wo in der Box** die beiden landen.
    ///
    /// Bis 1.10.1 hatte jede Zeile ihren eigenen Doppeltipp
    /// (`TapGesture(count: 2).exclusively(before: TapGesture())`) und die Box
    /// einen dritten. Landete der zweite Tipp ein paar Punkte daneben — auf
    /// der anderen Zeile oder dazwischen —, zählte der erste allein, und es
    /// ging die Suche auf statt der Pendelstrecke. Jetzt zählt die Box selbst
    /// mit, mit einem Fenster, das hier steht und nicht im System.
    private func tap(_ field: ContentView.PlaceField?) {
        if let pending = pendingTap {
            pending.cancel()
            pendingTap = nil
            onQuickCommute()
            return
        }
        pendingTap = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.doubleTapWindow))
            guard !Task.isCancelled else { return }
            pendingTap = nil
            if let field { onEdit(field) }
        }
    }

    /// So lange wartet ein Tipp auf seinen zweiten. Etwas länger als das
    /// System (rund 0,3 s): wer mit dem Daumen tippt, ist langsamer.
    static let doubleTapWindow = 0.35

    /// Street big, postal code and town small beside it — in Berlin a street
    /// name alone is not an address.
    /// Not a `Button`: a button would swallow the first of the two taps, and
    /// the shortcut has to work on the address rows as well as beside them.
    private func field(_ place: Place?, placeholder: String, field: ContentView.PlaceField) -> some View {
        Group {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if let role = role(place) { RoleBadge(role: role, compact: true) }
                Text(place?.shortName ?? placeholder)
                    .display(.subheadline, weight: place == nil ? .medium : .semibold)
                    .foregroundStyle(place == nil ? .secondary : .primary)
                    .layoutPriority(1)
                if let area = place?.areaLine {
                    Text(area)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .onTapGesture { tap(field) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel((field == .origin ? L("Start: ") : L("Ziel: ")) + (place?.name ?? L("nicht gesetzt")))
        .accessibilityAction { onEdit(field) }
        .accessibilityAction(named: L("Pendelstrecke einsetzen"), onQuickCommute)
    }
}

/// Abfahrt or Ankunft as two small pills, stacked to the height of the two
/// address lines they sit next to.
fileprivate struct ArrivalToggle: View {
    @Binding var when: PlanModel.When
    var onChange: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            item(L("Abfahrt"), arrival: false)
            item(L("Ankunft"), arrival: true)
        }
        .frame(width: 74)
    }

    private func item(_ title: String, arrival: Bool) -> some View {
        let active = when.isArrival == arrival
        return Button { set(arrival) } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(active ? .white : Theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background {
                    if active { Capsule().fill(Theme.gradient(Theme.accent)) }
                    else { Capsule().fill(Theme.accent.opacity(0.10)) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }

    /// Switching to "be there at": start at the next of the two commute times
    /// instead of keeping a departure time that means nothing now.
    private func set(_ arrival: Bool) {
        guard arrival != when.isArrival else { return }
        let base = arrival ? (WhenPicker.arrivalPresets.map { $0.date() }.min() ?? .now)
                           : (when.date ?? .now.addingTimeInterval(1800))
        withAnimation(.snappy(duration: 0.2)) {
            when = arrival ? .arriveAt(base) : .departAt(base)
        }
        onChange()
    }
}

/// Departure or arrival, plus the quick choices. Departure offers the saved
/// presets; arrival only the two times a commute actually has — there at 9,
/// home by 19 — and the clock for everything else.
fileprivate struct WhenPicker: View {
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if !when.isArrival {
                    chip(L("Jetzt"), active: when == .departNow) { set(.departNow) }
                }
                ForEach(chips, id: \.self) { p in
                    chip(p.title, active: matches(p)) { set(stamp(p.date())) }
                }
                chip(customLabel, symbol: "clock", active: isCustom) {
                    custom = when.date ?? .now.addingTimeInterval(1800)
                    showPicker = true
                }
                Chip(text: L("%d min Rüstzeit", prepMinutes), symbol: "figure.walk.departure")
            }
            .padding(.horizontal, 2)
        }
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                DatePicker(when.isArrival ? L("Ankunft") : L("Abfahrt"), selection: $custom)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle(when.isArrival ? L("Wann da sein?") : L("Wann losgehen?"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(L("Übernehmen")) { set(stamp(custom)); showPicker = false }
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L("Abbrechen")) { showPicker = false }
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
        return L("Zeit")
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

/// Die Fixpunkte der eingestellten Strecke, vom Tipp auf die Zeile zwischen
/// Start und Ziel.
struct WaypointSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    WaypointRows()
                } footer: {
                    Text(L("Gilt nur für %@ ↔ %@, in beiden Richtungen. Radrouten fahren die Fixpunkte an, die am Weg liegen.",
                           settings.origin?.shortName ?? "", settings.destination?.shortName ?? ""))
                }
            }
            .navigationTitle(L("Fixpunkte dieser Strecke"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button(L("Fertig")) { dismiss() } }
        }
    }
}
