import SwiftUI

/// One screen, and it fits without scrolling: where from and to, when, the map,
/// the four modes as a strip of boxes and the chosen route in two lines
/// underneath. Everything else is one tap away.
///
/// On an iPad the same pieces stand side by side — the controls in a column of
/// their own, the map taking the whole rest of the screen — so the app is an
/// iPad app rather than a phone screen blown up.
struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(RideTracker.self) private var tracker
    /// Nur für das Nachmessen am Ende einer Fahrt: die abgelegten Fahrten sind
    /// die Quelle für Tempo und Ampelwartezeit.
    @Environment(RideStore.self) private var rides
    @Environment(\.horizontalSizeClass) private var widthClass
    @Environment(\.verticalSizeClass) private var heightClass
    @State private var model = PlanModel()
    /// Welche der vier Einstellungsseiten offen ist; nil heißt keine.
    @State private var settingsPage: SettingsPage?
    /// Der Stand der Einstellungen, als die Seite aufging. Beim Zumachen wird
    /// verglichen: wer nur nachgesehen hat, bekommt keine neue Suche — die
    /// kostet ein halbes Dutzend Anfragen und wirft die Auswahl weg.
    @State private var settingsMark: SettingsMark?
    @State private var showHelp = false
    @State private var showMenu = false
    @State private var showRides = false
    @State private var editing: PlaceField?
    /// Only for the double tap on the address box; a single fix, then forgotten.
    @State private var locator = LocationService()

    /// Die vier Einträge im Menü. Aus einer Seite mit sechzehn Abschnitten
    /// sind vier geworden, jede mit einer Frage: wohin, wie, womit, und wie
    /// sieht es dabei aus.
    enum SettingsPage: String, Identifiable, CaseIterable {
        case addresses, navigation, modes, rest
        var id: Self { self }
        var title: String {
            switch self {
            case .addresses: L("Adressen")
            case .navigation: L("Navigation")
            case .modes: L("Verkehrsmittel")
            case .rest: L("Einstellungen")
            }
        }
        var symbol: String {
            switch self {
            case .addresses: "mappin.and.ellipse"
            case .navigation: "point.topleft.down.to.point.bottomright.curvepath"
            case .modes: "bicycle"
            case .rest: "gearshape"
            }
        }
    }

    /// Alles, woran eine Planung hängt: die Wertkopie der Einstellungen und
    /// die beiden Adressen, die nicht darin stehen.
    struct SettingsMark: Equatable {
        var plan: PlanSettings
        var origin: Place?
        var destination: Place?
    }

    private var settingsNow: SettingsMark {
        SettingsMark(plan: settings.snapshot, origin: settings.origin, destination: settings.destination)
    }

    enum PlaceField: Identifiable {
        case origin, destination
        var id: Self { self }
    }

    /// iPad and every other regular width: two columns instead of one.
    private var isWide: Bool { widthClass == .regular }
    /// A phone on its side. Same two columns as the iPad, but narrower and
    /// without the detail — in 390 points of height nothing else fits, and the
    /// map is what one turned the phone for.
    private var isLandscapePhone: Bool { heightClass == .compact && widthClass == .compact }
    private var isTwoColumn: Bool { isWide || isLandscapePhone }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                // No ScrollView: the screen is meant to fit, so everything but
                // the map has a fixed height and the map takes what is left.
                content
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 8) {
                        AppMark(size: 32)
                        Text("RadPendler").display(.headline)
                    }
                    // Without this the bar hands the leading item as little
                    // width as it likes and drops the name.
                    .fixedSize()
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("RadPendler")
                }
                // Between the name and the burger, so the one number that is
                // about to matter sits above everything else.
                // Always there, also for bike and car, where there is nothing
                // to count to — grey then, so the row does not jump about.
                // A tap switches it off; the warnings go with it.
                ToolbarItem(placement: .topBarTrailing) {
                    // Während einer Fahrt sagt die Leiste nicht mehr, wann man
                    // losgehen soll — sie sagt, wann man ankommt.
                    if tracker.isRecording {
                        RideArrivalPill()
                    } else {
                        Button { model.toggleCountdown() } label: {
                            CountdownBox(option: model.activeCountdown,
                                         alerts: settings.alertsOn ? settings.alertMinutes : [],
                                         compact: true, stopped: model.countdownStopped)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.countdownOption == nil && !model.countdownStopped)
                    }
                }
                // iOS 26 packs neighbouring bar items into one glass capsule;
                // the countdown is its own pill, not part of the menu button.
                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
                ToolbarItem(placement: .topBarTrailing) { menu }
            }
            // The warnings have to survive a locked screen, so they are real
            // notifications, rescheduled whenever the trip to watch changes.
            .task(id: alarmKey) {
                await Alarm.schedule(for: model.activeCountdown,
                                     alerts: settings.alertsOn ? settings.alertMinutes : [])
            }
            .onChange(of: settingsPage) { _, page in
                if page != nil { settingsMark = settingsNow }
            }
            .sheet(item: $settingsPage, onDismiss: refreshIfSettingsChanged) { page in
                switch page {
                case .addresses: AddressSettingsView()
                case .navigation: NavigationSettingsView()
                case .modes: ModeSettingsView()
                case .rest: SettingsView()
                }
            }
            .sheet(isPresented: $showHelp) { HelpView() }
            .sheet(isPresented: $showRides) { RidesView() }
            // Right after arriving is the one moment the numbers get read.
            .sheet(item: Binding(get: { tracker.finished }, set: { if $0 == nil { tracker.clearFinished() } })) { ride in
                RideSummarySheet(ride: ride)
            }
            .sheet(item: $editing, onDismiss: {
                model.applyDefaultWhen(settings: settings)
                refresh()
            }) { field in
                NavigationStack {
                    AddressSearchView(title: field == .origin ? L("Start") : L("Ziel"),
                                      offersLocation: field == .origin) { place in
                        if field == .origin { settings.origin = place } else { settings.destination = place }
                    }
                }
            }
            .task {
                // What the wrist picks is what the phone shows — the watch is
                // a second screen onto one plan, not a second plan.
                WatchLink.shared.onChoice = { [model] choice in model.apply(choice) }
                // Beendet sich eine Fahrt von selbst, muss dasselbe passieren
                // wie beim Tippen auf „Fahrt beenden" — nur sieht es niemand.
                tracker.onAutoStop = { afterRide() }
                model.applyDefaultWhen(settings: settings)
                refresh()
            }
        }
        .tint(Theme.accent)
    }

    @ViewBuilder private var content: some View {
        if model.needsAddresses {
            VStack(spacing: 10) {
                header
                ContentUnavailableView(L("Start und Ziel wählen"), systemImage: "mappin.and.ellipse",
                                       description: Text(L("Oben auf die beiden Zeilen tippen. Die Adressen bleiben auf diesem Gerät.")))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
        } else if tracker.isRecording {
            // A ride under way is the whole screen: everything the planning
            // page offers is about a trip that has not started yet.
            RideTrackingView(options: model.options, selectedID: model.selected?.id,
                             onStop: {
                                 tracker.stop()
                                 afterRide()
                             })
        } else if isTwoColumn {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: isWide ? 14 : 8) {
                    header
                    modes
                    tripBar
                    rainNote
                    // The column is taller than the controls need, so the
                    // whole detail goes in: why this trip, what kind of route
                    // it is, and every leg. On an iPad nothing is behind a tap.
                    //
                    // **iPad only.** In 1.2 this also filled the landscape
                    // column on the phone, which looked tidier and cost five
                    // seconds per change of trip — the whole timeline, laid out
                    // in a 360-point column in a screen barely 390 points high,
                    // in one SwiftUI pass. On a phone it took longer than the
                    // scene-update watchdog allows and the app was killed.
                    // Measured: 0,4 s portrait against 5,3 s landscape.
                    // Sideways one turned the phone for the map anyway.
                    if isWide, let option = model.selected {
                        ScrollView {
                            VStack(spacing: 12) {
                                TripNotes(option: option, reason: reason(for: option))
                                    .padding(.horizontal, 2)
                                TripFacts(option: option)
                                TripTimeline(option: option)
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .card()
                            }
                            .padding(.horizontal, Theme.gutter)
                            .padding(.bottom, 8)
                        }
                        .scrollIndicators(.hidden)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: isWide ? 400 : 360)
                map.padding(.trailing, Theme.gutter)
            }
            .padding(.vertical, isWide ? 8 : 4)
        } else {
            VStack(spacing: 10) {
                header
                map.padding(.horizontal, Theme.gutter)
                rainNote
                modes
                tripBar
            }
            .padding(.vertical, 6)
        }
    }

    private var header: some View {
        RouteHeader(origin: settings.origin, destination: settings.destination,
                    when: $model.when, prepMinutes: settings.prepMinutes,
                    presets: settings.departurePresets,
                    role: { settings.role(of: $0) },
                    // Tapping a field stops whatever is being calculated: a
                    // long trip holds the network and the map for seconds, and
                    // the plan one is about to replace is worth nothing.
                    onEdit: { model.cancel(); editing = $0 },
                    onQuickCommute: quickCommute,
                    onSwap: { settings.swapDirection(); model.applyDefaultWhen(settings: settings); refresh() },
                    onWhenChange: refresh)
    }

    /// The stamp rides in the radar bar, on the time axis it belongs to; since
    /// the page does not scroll it is also the way to plan again.
    private var map: some View {
        TripMapPanel(options: model.options, selectedID: model.selected?.id,
                     waypoints: settings.waypoints,
                     ends: [settings.origin?.coordinate, settings.destination?.coordinate].compactMap { $0 },
                     onSelect: { select($0) },
                     lastRun: model.lastRun, loading: model.isLoading,
                     // Ein Tipp auf den Zeitstempel ist eine Ansage: neu
                     // fragen, auch wenn die Antwort noch frisch wäre.
                     onRefresh: { model.refresh(settings: settings, force: true) })
            .frame(minHeight: 150, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            }
    }

    private func reason(for option: TripOption) -> String? {
        model.recommended?.id == option.id ? model.result.recommendation?.reason : nil
    }

    private var modes: some View {
        ModeStrip(model: model).padding(.horizontal, Theme.gutter)
    }

    @ViewBuilder private var tripBar: some View {
        if let option = model.selected {
            SelectedTripBar(model: model, option: option, onRecord: { record(option) })
                .padding(.horizontal, Theme.gutter)
        }
    }

    /// Double tap on the address box: the commute, without typing. Where one
    /// is standing decides which way round it is — at home it is the way in, at
    /// work the way back, and anywhere else the clock decides.
    ///
    /// The location is fetched the same way „Mein Standort" fetches it: once,
    /// on this tap, and forgotten again.
    private func quickCommute() {
        model.cancel()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        Task {
            let fix = try? await locator.current()
            if let fix {
                settings.origin = await locator.place(for: fix)
            }
            if let destination = AppSettings.commuteDestination(from: fix?.coordinate,
                                                                home: settings.homePlace,
                                                                work: settings.workPlace,
                                                                workArrivalMinutes: settings.workArrivalMinutes) {
                settings.destination = destination
            }
            model.applyDefaultWhen(settings: settings)
            refresh()
        }
    }

    /// Starts recording the trip that is on screen. The lit junctions of *this*
    /// route come along — they decide later which standstill was a red light,
    /// and a replan half way must not be able to change that answer.
    private func record(_ option: TripOption) {
        let planned = option.bikeRoute?.stats?.signalPoints ?? option.carRoute?.signalPoints ?? []
        // What OpenStreetMap knows, plus what this rider has learned. The
        // learned ones are the point: the crossing that is only a light in
        // practice is exactly the one no map has.
        let signals = planned + settings.learnedSignals.map(\.coordinate)
        // Am Lenker gilt, was am Lenker zuletzt galt — nicht, wie die App
        // sich sonst dreht.
        settings.rideOrientation.apply()
        tracker.start(subject: RideTracker.Subject(origin: settings.origin?.shortName ?? "Start",
                                                   destination: settings.destination?.shortName ?? "Ziel",
                                                   mode: option.mode.rawValue,
                                                   plannedSeconds: option.duration,
                                                   plannedMeters: option.totalDistance,
                                                   plannedSignals: planned.count),
                      signals: signals,
                      route: RideTrackingView.route(of: model.options, selected: option.id),
                      roadPoints: option.bikeRoute?.roadPoints ?? [],
                      signalSeconds: TimeInterval(settings.signalStopSeconds),
                      replanOffRouteMeters: settings.replanOffRouteMeters,
                      replanOffRouteMinutes: settings.replanOffRouteMinutes,
                      autoStopMinutes: settings.autoStopMinutes,
                      plannedSignals: planned)
    }

    /// Was schiefging — und zwar **im Wortlaut**.
    ///
    /// Der Planer formuliert brauchbare Sätze („Kein Bahnhof mit Radmitnahme
    /// im Umkreis von 5 km"), und angezeigt wurde davon bis 1.4 nichts: in
    /// der Box stand „Fehler", der Satz lag unbenutzt im Ergebnis. Hier steht
    /// er, für die Kategorie, die gerade offen ist.
    @ViewBuilder private var rainNote: some View {
        if let failure = model.result.failures[model.activeMode] {
            Label(failure, systemImage: "exclamationmark.triangle")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.orange)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, Theme.gutter + 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(L("%@ ist nicht gegangen: %@", model.activeMode.title, failure))
        } else if let rainFailure = model.result.rainFailure {
            Label(rainFailure, systemImage: "cloud.slash")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.orange)
                .lineLimit(1)
                .padding(.horizontal, Theme.gutter + 4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Everything that is not the plan itself, behind one quiet button.
    ///
    /// A popover rather than a `Menu`: an iOS menu renders plain text only, so
    /// the version, the copyright and the sources could be neither small nor
    /// italic nor on lines of their own in one.
    private var menu: some View {
        Button { showMenu = true } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .semibold))
        }
        .accessibilityLabel(L("Menü"))
        .popover(isPresented: $showMenu) {
            VStack(alignment: .leading, spacing: 0) {
                menuRow(L("Fahrten"), "list.bullet.rectangle") { showRides = true }
                Divider().padding(.leading, 44)
                ForEach(SettingsPage.allCases) { page in
                    menuRow(page.title, page.symbol) { settingsPage = page }
                    Divider().padding(.leading, 44)
                }
                menuRow(L("Anleitung"), "questionmark.circle") { showHelp = true }
                Divider()
                languageRow
                Divider().padding(.top, 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text("RadPendler \(Self.version)")
                    Text("© 2026 AK")
                    Text("inspired by Oleg")
                    // Names only. The links this text used to carry live in
                    // the settings, where there is room for them to look like
                    // links instead of like grey lines in a footer.
                    Text(L("Datenquellen: VBB · Transitous/MOTIS · Apple Karten · BRouter und OpenStreetMap · DWD · Open-Meteo"))
                        .font(Self.sourceFont)
                        .padding(.top, 5)
                }
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 14)
                .accessibilityElement(children: .combine)
            }
            .frame(width: 280)
            .presentationCompactAdaptation(.popover)
        }
    }

    /// Die Sprache, als Zeile im Menü. Sie steht hier und nicht in den
    /// Einstellungen, weil sie dort niemand suchen würde, der die App gerade
    /// nicht lesen kann: das Menü ist drei Fähnchen weit von jedem Zustand
    /// entfernt.
    ///
    /// Die Wirkung ist sofort — siehe `AppLanguage`.
    @ViewBuilder private var languageRow: some View {
        @Bindable var settings = settings
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .font(.system(size: 15))
                .frame(width: 22)
            Picker("", selection: $settings.language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text("\(lang.flag)  \(lang.title)").tag(lang)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            Spacer(minLength: 0)
        }
        .font(.system(.body, design: .rounded))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .onChange(of: settings.language) { _, _ in showMenu = false }
    }

    /// Same size as the copyright lines above it, but slanted — and therefore
    /// **not** rounded: SF Rounded has no italic face, and neither SwiftUI nor
    /// the renderer synthesises one, so `.italic()` on it comes out upright.
    private static let sourceFont = Font.system(.caption2).italic()

    private func menuRow(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            showMenu = false
            // One runloop later: a sheet presented while the popover is still
            // going away is swallowed.
            DispatchQueue.main.async(execute: action)
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(.body, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Everything the scheduled warnings depend on: which trip, when it wants
    /// one to get going, and which minutes are armed.
    private var alarmKey: String {
        let option = model.activeCountdown
        return [option?.id.uuidString ?? "-",
                String(Int(option?.getReady.timeIntervalSince1970 ?? 0)),
                settings.alertsOn ? settings.alertMinutes.map(String.init).joined(separator: ",") : "off"]
            .joined(separator: "|")
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "v\(v) (\(b))"
    }

    private func refresh() {
        model.refresh(settings: settings)
    }

    /// Nur, wenn sich wirklich etwas geändert hat. Die Ausrichtung, die
    /// Hilfetexte und alles, was nur die Anzeige betrifft, stehen nicht in der
    /// Wertkopie — dafür wird nichts neu geholt.
    private func refreshIfSettingsChanged() {
        let mark = settingsMark
        settingsMark = nil
        guard mark == nil || mark != settingsNow else { return }
        refresh()
    }

    /// Was nach jeder Fahrt passiert, egal wer sie beendet hat: nachmessen,
    /// dazulernen, die Ausrichtung wieder freigeben.
    private func afterRide() {
        // Where this ride stood — and where it rolled straight through — is
        // what the next one knows: the junctions no map has, and what the
        // known ones really cost.
        settings.learn(stops: tracker.meter.stops,
                       track: tracker.meter.points,
                       junctions: tracker.meter.signals)
        // Und was sie über das Tempo dieses Fahrers weiß, steht ab jetzt in
        // den Einstellungen.
        settings.calibrate(from: rides.rides)
        // Die Fahrt ist vorbei: die App dreht sich wieder wie jede andere.
        settings.orientation = .auto
        settings.orientation.apply()
    }

    private func select(_ id: TripOption.ID) {
        guard let option = model.options.first(where: { $0.id == id }) else { return }
        withAnimation(.snappy(duration: 0.2)) {
            model.activeMode = option.mode
            model.selection[option.mode] = id
        }
    }

}

/// From, to, departure-or-arrival, and the time chips.
private struct RouteHeader: View {
    var origin: Place?
    var destination: Place?
    @Binding var when: PlanModel.When
    var prepMinutes: Int
    var presets: [DeparturePreset]
    /// Whether this address is the user's home or work, for the little mark.
    var role: (Place?) -> PlaceRole?
    var onEdit: (ContentView.PlaceField) -> Void
    /// Double tap anywhere on the box: the commute, without typing.
    var onQuickCommute: () -> Void
    var onSwap: () -> Void
    var onWhenChange: () -> Void

    @State private var swapTurns = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Abfahrt/Ankunft rides beside the two addresses: two lines there,
            // two lines here, and a whole row saved.
            HStack(alignment: .center, spacing: 10) {
                rail
                VStack(alignment: .leading, spacing: 10) {
                    field(origin, placeholder: L("Start wählen"), field: .origin)
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
        .onTapGesture(count: 2, perform: onQuickCommute)
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

    /// Street big, postal code and town small beside it — in Berlin a street
    /// name alone is not an address.
    /// Not a `Button`: a button would swallow the first of the two taps, and
    /// the shortcut has to work on the address rows as well as beside them.
    /// `exclusively(before:)` gives the double tap the first refusal and lets
    /// the single tap through when it does not come.
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
        .gesture(TapGesture(count: 2).onEnded(onQuickCommute)
            .exclusively(before: TapGesture().onEnded { onEdit(field) }))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel((field == .origin ? L("Start: ") : L("Ziel: ")) + (place?.name ?? L("nicht gesetzt")))
        .accessibilityAction { onEdit(field) }
        .accessibilityAction(named: L("Pendelstrecke einsetzen"), onQuickCommute)
    }
}

/// Abfahrt or Ankunft as two small pills, stacked to the height of the two
/// address lines they sit next to.
private struct ArrivalToggle: View {
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
