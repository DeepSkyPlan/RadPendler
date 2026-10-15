import Network
import StoreKit
import SwiftUI
import TipKit

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
    @Environment(\.requestReview) private var requestReview
    @Environment(\.verticalSizeClass) private var heightClass
    @State private var model = PlanModel()
    /// Welche der vier Einstellungsseiten offen ist; nil heißt keine.
    @State private var settingsPage: SettingsPage?
    /// Der Stand der Einstellungen, als die Seite aufging. Beim Zumachen wird
    /// verglichen: wer nur nachgesehen hat, bekommt keine neue Suche — die
    /// kostet ein halbes Dutzend Anfragen und wirft die Auswahl weg.
    @State private var settingsMark: SettingsMark?
    @State private var showHelp = false
    @State private var showWaypoints = false
    @State private var showMenu = false
    @State private var showRides = false
    @State private var editing: PlaceField?
    /// For the commute button and the ride button; a single fix, then forgotten.
    @State private var locator = LocationService()
    /// Warum der Knopf „Fahrt“ gerade nicht aufgezeichnet hat.
    @State private var startNote: String?
    /// Der Knopf „Fahrt“ wartet gerade auf die Ortung; ein zweiter Tipp zählt nicht.
    @State private var checkingStart = false

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

    /// Das Wetter für die Leiste: das der gewählten Fahrt — oder, wo die
    /// keine Radstrecke hat (Auto, Bahn), das der ersten, die eine hat. Es ist
    /// derselbe Himmel.
    private var weather: RainAssessment? {
        let own = model.selected?.rain
        if let own, own.hasData { return own }
        return model.options.compactMap(\.rain).first(where: \.hasData)
    }

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
                    // Während einer Fahrt ist der Name im Weg: er liegt über
                    // dem Abbiegepfeil und über den drei Knöpfen links. Das
                    // Zeichen allein reicht — man weiß, welche App man fährt.
                    // Und sonst das Wetter auf der gewählten Strecke statt des
                    // Namens (Nutzer, 13.10.2026): ob es die Regenjacke
                    // braucht, ist die eine Auskunft, für die man vor dem
                    // Losfahren bisher den Radar bedienen musste. Während der
                    // Fahrt die Uhrzeit — der Fahrtbildschirm lässt keine
                    // Statusleiste übrig. Der Name steht, solange es noch
                    // kein Wetter gibt.
                    HStack(spacing: 8) {
                        AppMark(size: 32)
                        if tracker.isRecording {
                            RideClock(weather: weather)
                        } else if let weather {
                            WeatherPill(rain: weather)
                        } else {
                            Text("RadPendler").display(.headline)
                        }
                    }
                    // Without this the bar hands the leading item as little
                    // width as it likes and drops the name.
                    .fixedSize()
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(tracker.isRecording || weather == nil ? "RadPendler"
                                        : "RadPendler, " + WeatherPill.spoken(weather))
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
            .sheet(isPresented: $showWaypoints, onDismiss: refresh) { WaypointSheet() }
            .sheet(isPresented: $showRides) { RidesView() }
            // Right after arriving is the one moment the numbers get read.
            .sheet(item: Binding(get: { tracker.finished }, set: { if $0 == nil { tracker.clearFinished() } }),
                   onDismiss: askForReviewIfDue) { ride in
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
                tracker.onAutoStop = { [tracker, settings, rides, model] in
                    if RideSession.finish(tracker: tracker, settings: settings, rides: rides) {
                        model.applyDefaultWhen(settings: settings)
                        model.refresh(settings: settings)
                    }
                }
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
                                 // Am Ziel: gleich die Rückfahrt planen.
                                 if RideSession.stop(tracker: tracker, settings: settings, rides: rides) {
                                     model.applyDefaultWhen(settings: settings)
                                     refresh()
                                 }
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
                    onWhenChange: refresh,
                    waypoints: settings.isReady ? settings.waypoints : nil,
                    onWaypoints: { model.cancel(); showWaypoints = true })
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
        if let startNote {
            Label(startNote, systemImage: "arrow.trianglehead.swap")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, Theme.gutter)
                .transition(.opacity)
                .task(id: startNote) {
                    try? await Task.sleep(for: .seconds(10))
                    withAnimation { self.startNote = nil }
                }
        }
        if let option = model.selected {
            SelectedTripBar(model: model, option: option, onRecord: { record(option) })
                .padding(.horizontal, Theme.gutter)
        }
    }

    /// So jung muss die Ortung sein, um den Start zu versetzen.
    static let freshFix: TimeInterval = 15

    /// Der Knopf „Fahrt“. Steht man am **Ziel** der Route statt an ihrem
    /// Start, gilt noch die Richtung vom letzten Mal — morgens geplant, abends
    /// zurück (Fahrt 01.10.2026). Dann wird gedreht und neu geplant statt
    /// aufgezeichnet; der nächste Tipp nimmt den richtigen Weg. Gefragt wird
    /// die Ortung, die das System schon hat, sonst eine frische — höchstens
    /// drei Sekunden lang (1.10.1 nahm nur die gespeicherte, und die fehlte
    /// meist). Kommt keine, dreht sich die Fahrt beim ersten Fix selbst um
    /// (`RideTracker.startsAtEnd`).
    private func record(_ option: TripOption) {
        guard !checkingStart else { return }
        checkingStart = true
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        Task {
            defer { checkingStart = false }
            let fix = await locator.current(within: 3)
            let here = fix?.coordinate
            if let here, let from = settings.origin?.coordinate, let to = settings.destination?.coordinate,
               RideTracker.startsAtEnd(here, route: [from, to]) {
                settings.swapDirection()
                model.applyDefaultWhen(settings: settings)
                refresh()
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                withAnimation { startNote = L("Du stehst am Ziel — Richtung gedreht. Gleich noch einmal auf „Fahrt“ tippen.") }
                return
            }
            // Weder am Start noch auf der Linie: der Plan gilt einer anderen
            // Strecke. Dann ist der Start hier, und geplant wird neu. Nur mit
            // einer Ortung von eben — die gespeicherte darf fünf Minuten alt
            // sein, und im Auto sind das Kilometer.
            if let fix, abs(fix.timestamp.timeIntervalSinceNow) < Self.freshFix,
               let from = settings.origin?.coordinate,
               RideTracker.startsElsewhere(fix.coordinate, origin: from,
                                           route: RidePlan.route(of: model.options, selected: option.id)) {
                settings.origin = await locator.place(for: fix)
                model.applyDefaultWhen(settings: settings)
                refresh()
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                withAnimation {
                    startNote = L("Du stehst nicht am Start — Start auf deinen Standort gesetzt. Gleich noch einmal auf „Fahrt“ tippen.")
                }
                return
            }
            startNote = nil
            RideSession.start(option, options: model.options, settings: settings, tracker: tracker)
        }
    }

    /// The commute button in the address box: the commute, without typing. Where one
    /// is standing decides which way round it is — at home it is the way in, at
    /// work the way back, and anywhere else the clock decides.
    ///
    /// The location is fetched the same way „Mein Standort" fetches it: once,
    /// on this tap, and forgotten again.
    private func quickCommute() {
        QuickCommuteTip().invalidate(reason: .actionPerformed)
        model.cancel()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        Task {
            let fix = await Log.attemptAsync("Ortung") { try await locator.current() }
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
    /// the version line could not be small and grey in one, and the language
    /// picker would not fit.
    private var menu: some View {
        Button { showMenu = true } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .semibold))
        }
        .accessibilityLabel(L("Menü"))
        .popover(isPresented: $showMenu) {
            // Scrollbar, weil das Menü im Querformat höher ist als der
            // Bildschirm: dort fehlte die erste Zeile — „Fahrten" — komplett,
            // und zwar oben abgeschnitten, wo niemand danach sucht.
            ScrollView {
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
                // Nur die Version. Rechte und Datenquellen stehen in den
                // Einstellungen, mit Links — hier standen sie bis 1.9.1 ein
                // zweites Mal, als graue Zeilen ohne.
                Text("RadPendler \(Self.version)")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
            }
            }
            .scrollBounceBehavior(.basedOnSize)
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
        return [option?.id ?? "-",
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

    /// Einmal je neuer Fassung nach einer Bewertung im App Store fragen
    /// (Nutzer, 15.10.2026) — siehe `ReviewPrompt`.
    private func askForReviewIfDue() {
        let defaults = UserDefaults.standard
        guard ReviewPrompt.due(version: ReviewPrompt.currentVersion,
                               asked: defaults.string(forKey: ReviewPrompt.key),
                               rides: rides.rides.count) else { return }
        defaults.set(ReviewPrompt.currentVersion, forKey: ReviewPrompt.key)
        Task {
            // Erst, wenn die Zusammenfassung ganz weg ist: ein Fenster über
            // einem, das gerade zugeht, verschluckt iOS.
            try? await Task.sleep(for: .seconds(1))
            requestReview()
        }
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

    private func select(_ id: TripOption.ID) {
        guard let option = model.options.first(where: { $0.id == id }) else { return }
        withAnimation(.snappy(duration: 0.2)) {
            model.activeMode = option.mode
            model.selection[option.mode] = id
        }
    }

}

/// Wetter auf der gewählten Strecke, in der Leiste neben dem Zeichen: wie warm
/// beim Losfahren, und ob und ab wann es regnet.
struct WeatherPill: View {
    var rain: RainAssessment

    var body: some View {
        VStack(alignment: .leading, spacing: -1) {
            HStack(spacing: 4) {
                Image(systemName: rain.level.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(rain.level == .dry ? Color.orange : rain.level.color)
                if let t = rain.temperature {
                    Text(Self.degrees(t))
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                }
            }
            Text(rain.short)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(rain.level == .dry ? Color.secondary : rain.level.color)
                .lineLimit(1)
        }
    }

    /// Über `Int`, nicht über die Rundung allein: aus −0,4 würde sonst „-0°“.
    static func degrees(_ celsius: Double) -> String { "\(Int(celsius.rounded()))°" }

    static func spoken(_ rain: RainAssessment?) -> String {
        guard let rain else { return "" }
        return [rain.temperature.map { L("%d Grad", Int($0.rounded())) }, rain.short]
            .compactMap { $0 }.joined(separator: ", ")
    }
}

/// Während einer Fahrt das, was sonst die Statusleiste sagt — und das Wetter.
///
/// Im Querformat blendet iOS auf einem iPhone mit Kameraaussparung die
/// Statusleiste aus, und keine App kann sie dort zurückholen. Am Lenker liegt
/// die Fahrt aber quer. Deshalb stehen Uhrzeit, Akku und „kein Netz“ hier
/// (Nutzer, 15.10.2026), dazu die Temperatur. Die Stärke des Mobilfunks gibt
/// iOS keiner App heraus; was sich sagen lässt, ist, ob Netz da ist.
///
/// Eigene Uhr statt `TimelineView`: in einer Werkzeugleiste legt ein
/// `TimelineView` die Leiste bei jedem Takt neu aus (der Hänger aus 1.2) —
/// hier ändert sich einmal je Minute ein Text.
struct RideClock: View {
    var weather: RainAssessment?
    @State private var now = Date.now
    @State private var battery = RideClock.batteryPercent()
    private var network = NetworkWatch.shared

    init(weather: RainAssessment?) { self.weather = weather }

    var body: some View {
        VStack(alignment: .leading, spacing: -2) {
            Text(Fmt.time(now))
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .monospacedDigit()
            HStack(spacing: 5) {
                if let battery {
                    Label("\(battery) %", systemImage: Self.batterySymbol(battery))
                        .foregroundStyle(battery <= 20 ? Color.red : .secondary)
                }
                if !network.online {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .foregroundStyle(.orange)
                }
                if let weather, let t = weather.temperature {
                    Label(WeatherPill.degrees(t), systemImage: weather.level.symbol)
                        .foregroundStyle(weather.level == .dry ? Color.secondary : weather.level.color)
                }
            }
            .labelStyle(TightLabel())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([L("Uhrzeit %@", Fmt.time(now)), battery.map { L("Akku %d %%", $0) },
                             network.online ? nil : L("kein Netz"), WeatherPill.spoken(weather)]
                            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
            battery = Self.batteryPercent()
        }
        .task {
                while !Task.isCancelled {
                    // Bis zur nächsten vollen Minute, dann stimmt die Anzeige
                    // mit der Uhr überein, ohne sekündlich zu ticken.
                    let wait = 60 - now.timeIntervalSince1970.truncatingRemainder(dividingBy: 60) + 0.2
                    try? await Task.sleep(for: .seconds(wait))
                    now = .now
                    battery = Self.batteryPercent()
                }
            }
    }

    /// Der Akku in Prozent; nil im Simulator und wo iOS es nicht weiß.
    static func batteryPercent() -> Int? {
        if !UIDevice.current.isBatteryMonitoringEnabled { UIDevice.current.isBatteryMonitoringEnabled = true }
        let level = UIDevice.current.batteryLevel
        return level < 0 ? nil : Int((level * 100).rounded())
    }

    static func batterySymbol(_ percent: Int) -> String {
        switch percent {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }

    /// Zeichen und Text enger als ein `Label` von sich aus.
    struct TightLabel: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 2) { configuration.icon; configuration.title }
        }
    }
}

/// Ob gerade Netz da ist — für die Zeile, die während der Fahrt die
/// Statusleiste ersetzt.
@MainActor @Observable
final class NetworkWatch {
    static let shared = NetworkWatch()
    private(set) var online = true
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let up = path.status == .satisfied
            Task { @MainActor in NetworkWatch.shared.online = up }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkWatch"))
    }
}
