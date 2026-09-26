import MapKit
import SwiftUI

/// Die Einstellungen, auf vier Seiten verteilt.
///
/// Es war **eine** Seite mit sechzehn Abschnitten; darin etwas wiederzufinden
/// war Glückssache. Jetzt gibt es vier Einträge im Menü, und jeder beantwortet
/// eine Frage: wohin fahre ich, wie soll geplant werden, womit fahre ich, und
/// wie sieht es dabei aus.
///
/// `Page` ist die Klammer darum: Titel, „Fertig", und das Nachfragen der
/// Mitteilungsrechte — das braucht jede Seite gleich.
private struct Page<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @State private var notifications: Alarm.Permission = .unknown

    var body: some View {
        NavigationStack {
            Form { content }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button(L("Fertig")) { dismiss() } }
                }
                // Asking iOS every time the sheet opens, so the hint disappears
                // as soon as the permission is granted somewhere else.
                .task { notifications = await Alarm.permission() }
                .onChange(of: settings.alertsOn) { _, on in
                    guard on else { return }
                    Task { notifications = await Alarm.requestPermission() ? .granted : .denied }
                }
        }
    }
}

/// Ein Hilfetext unter einem Abschnitt — zusammengeklappt, solange er länger
/// ist als zwei Zeilen.
///
/// Die Einstellungsseiten waren zuletzt mehr Fließtext als Einstellung: wer
/// eine Zahl ändern wollte, scrollte an Absätzen vorbei, die er beim ersten
/// Mal gelesen hatte. Jetzt stehen zwei Zeilen da und der Rest auf Tippen.
/// Kurze Hinweise bleiben, wie sie sind — ein „mehr" unter einem Halbsatz
/// wäre albern.
struct Hint: View {
    var text: String
    @State private var open = false

    init(_ text: String) { self.text = text }

    /// Ab so vielen Zeichen wird es in der Fußnotenschrift mehr als zwei
    /// Zeilen. Gezählt statt gemessen: eine Höhenmessung je Fußnote kostet
    /// einen zweiten Layoutdurchgang, und die Grenze muss nicht genau sein.
    static let longEnough = 120

    var body: some View {
        if text.count <= Self.longEnough {
            Text(text)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text(text)
                    .lineLimit(open ? nil : 2)
                Text(open ? L("weniger") : L("mehr"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.snappy(duration: 0.2)) { open.toggle() } }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(text)
            .accessibilityHint(open ? L("Tippen zum Zuklappen") : L("Tippen für den ganzen Text"))
        }
    }
}

/// Wohin es geht: die beiden Adressen, die beiden festen Orte, die Fixpunkte.
struct AddressSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var notifications: Alarm.Permission = .unknown

    var body: some View {
        @Bindable var settings = settings
        Page(title: L("Adressen")) {
                Section {
                    NavigationLink {
                        AddressSearchView(title: L("Start"), offersLocation: true) { settings.origin = $0 }
                    } label: {
                        LabeledContent(L("Start"), value: settings.origin?.withArea ?? L("nicht gesetzt"))
                    }
                    NavigationLink {
                        AddressSearchView(title: L("Ziel")) { settings.destination = $0 }
                    } label: {
                        LabeledContent(L("Ziel"), value: settings.destination?.withArea ?? L("nicht gesetzt"))
                    }
                    Button(L("Beide Adressen löschen"), role: .destructive) { settings.clearPlaces() }
                } header: {
                    Text(L("Adressen"))
                } footer: {
                    Hint(CloudStore.shared.available
                         ? L("Die App wird ohne Adressen ausgeliefert. Start, Ziel, die benutzten Adressen und alle Einstellungen gleichen sich über deine iCloud mit deinen anderen Geräten ab. Zum Planen gehen die Koordinaten von Start und Ziel an die Dienste, die die Strecke rechnen (VBB, Transitous, BRouter, Apple Karten, Open-Meteo) — ohne Namen und ohne Adresstext. Sonst verlässt nichts davon deine Geräte und deine iCloud.")
                         : L("Die App wird ohne Adressen ausgeliefert. Start und Ziel bleiben nur auf diesem Gerät gespeichert. Mit einem angemeldeten iCloud-Konto gleichen sie sich mit deinen anderen Geräten ab."))
                }
                Section {
                    ForEach(PlaceRole.allCases, id: \.self) { role in
                        NavigationLink {
                            AddressSearchView(title: role.title, offersLocation: true) { settings.setPlace($0, for: role) }
                        } label: {
                            LabeledContent {
                                Text(settings.place(for: role)?.withArea ?? L("nicht gesetzt"))
                            } label: {
                                Label(role.title, systemImage: role.symbol)
                            }
                        }
                    }
                    if settings.homePlace != nil || settings.workPlace != nil {
                        Button(L("Beide vergessen"), role: .destructive) {
                            settings.homePlace = nil
                            settings.workPlace = nil
                        }
                    }
                    DatePicker(L("Bei der Arbeit sein um"), selection: Binding(
                        get: { DeparturePreset.clock(settings.workArrivalMinutes / 60, settings.workArrivalMinutes % 60).date() },
                        set: { d in
                            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                            settings.workArrivalMinutes = (c.hour ?? 9) * 60 + (c.minute ?? 0)
                        }), displayedComponents: .hourAndMinute)
                } header: {
                    Text(L("Zuhause und Arbeit"))
                } footer: {
                    Hint(L("Diese zwei bekommen überall ein Zeichen — in der Adresssuche, in der Liste der benutzten Adressen und oben auf der Hauptseite — und stehen in der Suche ganz oben. Fahrten zur Arbeit starten mit „Ankunft um …“, Fahrten nach Hause mit „Abfahrt jetzt“; von Hand umschaltbar."))
                }
                Section {
                    ForEach(settings.waypoints, id: \.self) { p in
                        Label(p.withArea, systemImage: "mappin.and.ellipse")
                    }
                    .onDelete { settings.waypoints.remove(atOffsets: $0) }
                    NavigationLink {
                        AddressSearchView(title: L("Fixpunkt")) { settings.waypoints.append($0) }
                    } label: {
                        Label(L("Fixpunkt hinzufügen"), systemImage: "plus.circle")
                    }
                    if settings.waypoints.count > 1 {
                        Toggle(L("Alle Fixpunkte verlangen"), isOn: $settings.requireAllWaypoints)
                    }
                } header: {
                    Text(L("Fixpunkte"))
                } footer: {
                    Hint(L("Punkte, über die die Strecke führen soll, z. B. „S Ostkreuz“ oder „Berlin Hauptbahnhof“. Verbindungen, die nicht daran vorbeikommen, werden ausgegraut ans Ende gestellt und nie empfohlen. Ohne Fixpunkte gilt keine Einschränkung."))
                }
        }
    }
}

/// Wie geplant wird: Rüstzeit, Puffer, Umsteigen, Startzeiten, Countdown.
struct NavigationSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var notifications: Alarm.Permission = .unknown

    var body: some View {
        @Bindable var settings = settings
        Page(title: L("Navigation")) {
                Section {
                    Stepper(L("Rüstzeit: %d min", settings.prepMinutes), value: $settings.prepMinutes, in: 0...30)
                } footer: {
                    Hint(L("Zeit vom Planen bis zum Losgehen. Gilt für jedes Verkehrsmittel."))
                }
                Section {
                    Stepper(L("Umstieg zählt wie %d min", settings.transferPenaltyMinutes), value: $settings.transferPenaltyMinutes, in: 0...30)
                } header: {
                    Text(L("Umsteigen"))
                } footer: {
                    Hint(L("Beim Sortieren und Empfehlen wird jeder Umstieg wie so viele Minuten längere Fahrt gewertet. Eine direkte Verbindung gewinnt also, solange die mit Umstieg nicht mehr als diese Zeit früher ankommt."))
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
                        Label(L("Zeitpunkt hinzufügen"), systemImage: "plus.circle")
                    }
                } header: {
                    Text(L("Startzeiten"))
                } footer: {
                    Hint(L("Diese Vorschläge stehen oben neben „Jetzt“ zur Wahl — relativ („in 15 min“) oder als Uhrzeit („um 8 Uhr“, heute oder morgen)."))
                }
                Section {
                    Stepper(L("Puffer vor der Abfahrt: %d min", settings.departureBufferMinutes),
                            value: $settings.departureBufferMinutes, in: 0...30)
                    Stepper(L("Puffer vor der Ankunft: %d min", settings.arrivalBufferMinutes),
                            value: $settings.arrivalBufferMinutes, in: 0...30)
                } header: {
                    Text(L("Puffer"))
                } footer: {
                    Hint(L("Der Abfahrtspuffer verschiebt das Losgehen nach vorn, der Ankunftspuffer lässt die Verbindung früher ankommen. Beide zählen nicht zur angezeigten Fahrzeit."))
                }
                Section {
                    Toggle(L("Warnung vor dem Losgehen"), isOn: $settings.alertsOn)
                    if settings.alertsOn {
                        ForEach([15, 10, 5, 3, 1], id: \.self) { m in
                            Toggle(L("%d min vorher", m), isOn: Binding(
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
                                Label(L("Mitteilungen sind aus — in den iOS-Einstellungen erlauben"),
                                      systemImage: "bell.slash")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                } header: {
                    Text(L("Countdown"))
                } footer: {
                    Hint(L("Der Countdown oben rechts zählt bis zum Losgehen für Bahn und Bus — und bei „Ankunft um …“ für jede Fahrt. Warnungen kommen als Mitteilung, auch wenn die App zu ist; bei offener App zusätzlich als Ton."))
                }
                Section(L("Auto")) {
                    Stepper(L("Parkplatzsuche: %d min", settings.parkingMinutes), value: $settings.parkingMinutes, in: 0...30)
                }
        }
    }
}

/// Womit gefahren wird: wie viele Möglichkeiten, in welcher Reihenfolge, welcher Fahrplan, welche Linie nimmt das Rad mit.
struct ModeSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var notifications: Alarm.Permission = .unknown

    var body: some View {
        @Bindable var settings = settings
        Page(title: L("Verkehrsmittel")) {
                Section {
                    Picker(L("Möglichkeiten je Verkehrsmittel"), selection: $settings.optionsPerMode) {
                        ForEach(1...3, id: \.self) { n in Text("\(n)").tag(n) }
                    }
                    NavigationLink {
                        PriorityList(title: L("Verkehrsmittel"), items: $settings.modeOrder,
                                     footer: L("Von oben nach unten: was gewinnt, wenn zwei Fahrten fast gleichzeitig ankommen. Dieselbe Reihenfolge ordnet die vier Kästen auf der Hauptseite, entscheidet, welcher nach einer Suche geöffnet ist, und in welcher Folge sie sich füllen — das Oberste steht zuerst da, der Rest kommt nach."),
                                     label: \.title, symbol: \.symbol)
                    } label: {
                        LabeledContent(L("Verkehrsmittel"), value: settings.modeOrder.map(\.short).joined(separator: " › "))
                    }
                    NavigationLink {
                        PriorityList(title: L("Radrouten"), items: $settings.bikeVariantOrder,
                                     footer: "Die obersten so vieler, wie oben eingestellt — die erste wird vorgeschlagen, die anderen erreicht ein Tipp auf den Kasten. Was weiter unten steht, wird gar nicht erst berechnet und spart die Anfrage.\n\n„wenig Autos“ und „wenig Halts“ beantworten zwei verschiedene Fragen: die erste, wie lange man neben fahrenden Autos fährt, die zweite, wie oft man ihretwegen anhalten muss. Die kürzeste Strecke ist selten beides.",
                                     label: \.title, symbol: \.symbol)
                    } label: {
                        LabeledContent(L("Radrouten"), value: settings.bikeVariantOrder.first?.title ?? "")
                    }
                    NavigationLink {
                        PriorityList(title: L("Autorouten"), items: $settings.carVariantOrder,
                                     footer: L("Dasselbe fürs Auto. Apple Karten liefert meist zwei oder drei Linien; welche davon oben steht, entscheidet diese Liste."),
                                     label: \.title, symbol: { _ in nil })
                    } label: {
                        LabeledContent(L("Autorouten"), value: settings.carVariantOrder.first?.title ?? "")
                    }
                    Picker(L("Rad in die Bahn ab"), selection: $settings.rainSwitchLevel) {
                        ForEach([RainLevel.possible, .light, .rain, .heavy], id: \.self) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    Button(L("Zurück auf Werkseinstellung")) { settings.resetPriorities() }
                } header: {
                    Text(L("Vorlieben"))
                } footer: {
                    Hint(L("Womit die App plant, wenn sie die Wahl hat. Ab dem gewählten Regen wird nicht mehr die ganze Strecke geradelt, sondern das Rad in die Bahn gestellt — „starker Regen“ heißt also praktisch immer fahren."))
                }
                Section {
                    Stepper(value: $settings.bikeSpeedKmh, in: 10...45, step: 1) {
                        Text(L("Rolltempo ohne Ampeln: %d km/h", Int(settings.bikeSpeedKmh)))
                    }
                    Stepper(L("Puffer am Bahnhof: %d min", settings.bikeStationBufferMinutes),
                            value: $settings.bikeStationBufferMinutes, in: 0...10)
                    Stepper(L("Wartezeit je Ampel: %d s", settings.signalWaitSeconds),
                            value: $settings.signalWaitSeconds, in: 0...90, step: 5)
                    MeasuredSpeedRow()
                    MeasuredSignalRow()
                    Stepper(value: $settings.maxBikeToStationKm, in: 1...10, step: 0.5) {
                        Text(L("Radweg zum Bahnhof: bis %@ km", settings.maxBikeToStationKm.formatted(.number.precision(.fractionLength(0...1)))))
                    }
                } header: {
                    Text(L("Fahrrad"))
                } footer: {
                    Hint(L("Zwei verschiedene Geschwindigkeiten, und sie tun Verschiedenes. Das Rolltempo ist das Tempo beim Fahren, ohne Halte: daraus plus der Wartezeit je Ampelkreuzung und den Höhenmetern rechnet die App jede Linie durch — es entscheidet also, welche Linie die schnellste ist. Der Gesamtschnitt ist die Messung deiner eigenen Fahrten, Tür zu Tür, mit allen Ampeln und Halten darin — er entscheidet, wie lange es dauert. Wäre die Rechnung schneller als dein gemessener Gesamtschnitt, gilt der Gesamtschnitt; auch bei den Zubringern zum Bahnhof, dort aber nur, wenn er die vorsichtigere Zahl ist. Beide Werte schreibt die App nach jeder aufgezeichneten Fahrt selbst fort, aus dem Median der letzten Fahrten, sobald es genug davon gibt; von Hand gestellt gelten sie bis zur nächsten Fahrt. Die Ampelwartezeit ist ein Mittelwert (etwa jede zweite ist grün) und wird je Ampelkreuzung addiert — außer an den Kreuzungen, die deine eigenen Fahrten schon kennen: die kosten, was dort gemessen wurde. Der Puffer gilt je Bahnhof für Rad schieben, Aufzug und Bahnsteig. Rad + Bahn nimmt nur Züge, für die die VBB-Auskunft Fahrradmitnahme meldet."))
                }
                Section {
                    Picker(L("Fahrplan"), selection: $settings.timetableSource) {
                        ForEach(TimetableSource.allCases) { Text($0.title).tag($0) }
                    }
                    Link(destination: URL(string: "https://transitous.org/sources/")!) {
                        Label("transitous.org/sources", systemImage: "arrow.up.right.square")
                    }
                    Link(destination: URL(string: "https://www.openstreetmap.org/copyright")!) {
                        Label("openstreetmap.org/copyright", systemImage: "arrow.up.right.square")
                    }
                } header: {
                    Text(L("Fahrplanquelle"))
                } footer: {
                    Hint(L("„Automatisch“ fragt den VBB, solange Start und Ziel in Berlin/Brandenburg liegen — dort ist er genauer und sagt als Einziger, welcher Zug Räder mitnimmt. Alles darüber hinaus beantwortet Transitous, eine von Freiwilligen betriebene MOTIS-Instanz auf dem bundesweiten DELFI-Datensatz. Transitous plant Rad und Bahn in einem Zug und sucht sich die Bahnhöfe selbst. Woher deren Daten kommen, steht hinter dem Link."))
                }
                Section {
                    NavigationLink {
                        BikeLinesView()
                    } label: {
                        LabeledContent(L("Fahrradmitnahme")) {
                            let open = settings.bikeLines.filter { $0.allowed == nil }.count
                            Text(settings.bikeLines.isEmpty ? L("noch keine Linie")
                                 : (open == 0 ? L("alle geklärt") : L("%d offen", open)))
                                .foregroundStyle(open > 0 ? .orange : .secondary)
                        }
                    }
                } footer: {
                    Hint(L("Welche Linien das Rad mitnehmen, weißt du besser als jeder Fahrplan. Die Liste füllt sich mit den Linien, die in gefundenen Verbindungen vorkommen; was die Auskunft selbst zusichert, steht schon auf „ja“. Solange eine Linie offen ist, wird die Fahrt trotzdem vorgeschlagen — mit dem Hinweis, dass die Mitnahme ungeklärt ist."))
                }
        }
    }
}

/// Alles Übrige: Anzeige und Verhalten während einer Fahrt, Hilfe, Rechtliches.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var notifications: Alarm.Permission = .unknown

    var body: some View {
        @Bindable var settings = settings
        Page(title: L("Einstellungen")) {
                Section {
                    Picker(L("Ausrichtung"), selection: $settings.orientation) {
                        ForEach(OrientationLock.allCases, id: \.self) { o in
                            Label(o.title, systemImage: o.symbol).tag(o)
                        }
                    }
                    .onChange(of: settings.orientation) { settings.orientation.apply() }
                    Picker(L("Neu berechnen ab"), selection: $settings.replanOffRouteMeters) {
                        Text(L("aus")).tag(0.0)
                        ForEach([100.0, 200.0, 500.0, 1000.0], id: \.self) { m in
                            Text(L("%d m neben der Route", Int(m))).tag(m)
                        }
                    }
                    Picker(L("… oder nach"), selection: $settings.replanOffRouteMinutes) {
                        Text(L("aus")).tag(0.0)
                        ForEach([1.0, 2.0, 5.0, 10.0], id: \.self) { m in
                            Text(L("%d min daneben", Int(m))).tag(m)
                        }
                    }
                    Stepper(L("Ampelhalt ab %d s", settings.signalStopSeconds),
                            value: $settings.signalStopSeconds, in: 10...120, step: 5)
                    Picker(L("Bildschirm abdunkeln nach"), selection: $settings.rideDimSeconds) {
                        Text(L("aus")).tag(0.0)
                        ForEach([15.0, 30.0, 60.0, 120.0], id: \.self) { s in
                            Text(L("%d s ohne Berührung", Int(s))).tag(s)
                        }
                    }
                    Picker(L("Von selbst anhalten nach"), selection: $settings.autoPauseMinutes) {
                        Text(L("aus")).tag(0.0)
                        ForEach([1.0, 2.0, 3.0, 5.0, 10.0], id: \.self) { m in
                            Text(L("%d min Halt", Int(m))).tag(m)
                        }
                    }
                    Picker(L("Von selbst beenden nach"), selection: $settings.autoStopMinutes) {
                        Text(L("aus")).tag(0.0)
                        ForEach([10.0, 15.0, 20.0, 30.0, 60.0], id: \.self) { m in
                            Text(L("%d min Halt", Int(m))).tag(m)
                        }
                    }
                    HStack {
                        Label(L("Gelernte Ampeln"), systemImage: "light.beacon.max")
                        Spacer()
                        Text("\(settings.learnedSignals.count)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    if !settings.learnedSignals.isEmpty {
                        Button(L("Gelernte Ampeln vergessen"), role: .destructive) {
                            settings.forgetLearnedSignals()
                        }
                    }
                } header: {
                    Text(L("Fahrt aufzeichnen"))
                } footer: {
                    Hint(L("„Automatisch“ lässt den Bildschirm mitdrehen; am Lenker ist das oft im Weg. — Eine Fahrt beginnt quer, oder so, wie du es während der letzten Fahrt zuletzt eingestellt hast; der Knopf dafür steht oben links auf dem Fahrtbildschirm. — Steht die Aufzeichnung an derselben Stelle und ist dort keine bekannte Ampel, hält sie nach der ersten eingestellten Zeit von selbst an — und läuft weiter, sobald es weitergeht; die Ortung bleibt dabei an, aber sparsam. Nach der zweiten Zeit beendet sie sich und zählt bis zum Anfang des Stillstands: das ist der Fall „angekommen und vergessen, auf beenden zu tippen“. Der Knopf oben links auf dem Fahrtbildschirm schaltet beides für eine Fahrt ab, für den Stau, der gleich weitergeht. Eine gewollte Unterbrechung ist dagegen der Knopf „Pause“: er hält die Uhr an und schaltet die Ortung ganz ab, und die Pause zählt weder zur Fahrzeit noch als Halt — anders als das Stehen vor einer automatischen Pause, das ein Halt war wie jeder andere. — Während einer Aufzeichnung bleibt der Bildschirm an, bis du die Fahrt beendest; das kostet Strom und ist so gewollt. Er wird aber dunkel, solange du ihn nicht anfasst — und beim ersten Antippen wieder hell, ebenso wenn eine Abbiegung ansteht oder du neben der Route bist. Das ist während einer Fahrt der größte Posten auf der Stromrechnung, größer als die Ortung. Am Strom bleibt er hell, ohne dass du etwas umstellen musst. — Verlässt du die Route, zeigt ein Pfeil zurück. Neu berechnet wird, was zuerst eintritt: die eingestellte Entfernung (und dann erst nach ein paar Sekunden am Stück, damit ein Bogen um eine Baustelle keine Neuplanung auslöst) oder die eingestellte Zeit, egal wie weit — wer im Kreis um einen gesperrten Weg fährt, kommt nie weit genug weg. Beides „aus“ lässt es beim Pfeil. — Wer länger als die eingestellte Zeit steht, stand an einer Ampel, auch wenn keine Karte dort eine kennt — nur das Stehen vor dem Losfahren und nach dem Ankommen zählt nie, das ist die eigene Haustür. Solche Stellen merkt sich die App und rechnet sie beim nächsten Mal mit ein. Mitgezählt wird auch, wo eine Aufzeichnung ohne Halt durchkam: eine gelernte Kreuzung kostet beim Planen ihre gemessene Zeit über alle Vorbeifahrten, nicht den eingestellten Mittelwert. Sie bleiben auf deinen Geräten und in deiner iCloud."))
                }
                Section {
                    // Kontakt als Seite, nicht als Adresse: eine Adresse im
                    // Programm ist eine Adresse, die jeder mitliest.
                    Link(destination: URL(string: "https://deepskyplan.github.io/radpendler-app/#support")!) {
                        Label(L("Hilfe und Rückmeldung"), systemImage: "questionmark.circle")
                    }
                    Link(destination: URL(string: "https://deepskyplan.github.io/radpendler-privacy/")!) {
                        Label(L("Datenschutz"), systemImage: "hand.raised")
                    }
                    Link(destination: URL(string: "https://github.com/DeepSkyPlan/RadPendler")!) {
                        Label(L("Quelltext auf GitHub"), systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                } header: {
                    Text(L("Hilfe und Rechtliches"))
                } footer: {
                    Hint(L("Fragen, Fehler und Vorschläge gehen über die Support-Seite. Dort steht auch, was dabei hilft: Gerät, Version, Strecke und was die App gezeigt hat."))
                }
                Section {
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                } header: {
                    Text(L("Daten, Rechte und Version"))
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("Fahrplan und Echtzeit: VBB Verkehrsverbund Berlin-Brandenburg (HAFAS-Fahrinfo)."))
                        Text(L("Karten, Adresssuche und Autorouten: Apple Karten. © Apple Inc. und Mitwirkende."))
                        Text(L("Radrouten: BRouter (brouter.de), auf Basis von OpenStreetMap."))
                        Text(L("Ampeln, Straßen und Kartendaten: © OpenStreetMap-Mitwirkende, ODbL 1.0, abgefragt über die Overpass API."))
                        Text(L("Regenradar und Niederschlagsvorhersage: Deutscher Wetterdienst (DWD), Datenlizenz Deutschland – Namensnennung 2.0."))
                        Text(L("Regen entlang der Strecke: Open-Meteo.com, CC BY 4.0, auf Basis von DWD ICON-D2."))
                        Text(L("© 2026 AK. Alle Zeiten ohne Gewähr."))
                    }
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
                    TextField(L("Linie, z. B. RE 7"), text: $newLine)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .onSubmit(add)
                    Button(L("Hinzufügen"), action: add)
                        .disabled(newLine.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Hint(L("Für Linien, die noch in keiner Verbindung vorkamen."))
            }
            if settings.bikeLines.isEmpty {
                Section {
                    Text(L("Noch keine Linie. Sobald die App eine Verbindung mit Bahn oder Bus findet, stehen deren Linien hier."))
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
                                Text(L("Rad ja")).tag(Bool?.some(true))
                                Text(L("Rad nein")).tag(Bool?.some(false))
                                Text(L("offen")).tag(Bool?.none)
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .tint(line.allowed == nil ? .orange : .secondary)
                        }
                        .swipeActions {
                            Button(L("Löschen"), role: .destructive) {
                                settings.bikeLines.removeAll { $0.name == line.name }
                            }
                        }
                    }
                } header: {
                    Text(L("Gesehene Linien"))
                } footer: {
                    Hint(L("„offen“ heißt: die Verbindung wird weiter vorgeschlagen, aber mit dem Hinweis, dass die Mitnahme ungeklärt ist. „Rad nein“ nimmt sie aus den Rad + Bahn-Vorschlägen heraus."))
                }
            }
        }
        .navigationTitle(L("Fahrradmitnahme"))
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
                Hint(footer)
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
struct MeasuredSpeedRow: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        if settings.measuredRides >= AppSettings.calibrationRides,
           let moving = settings.measuredMovingKmh, let overall = settings.measuredOverallKmh {
            VStack(alignment: .leading, spacing: 3) {
                Label(L("Gemessen aus %d Fahrten", settings.measuredRides), systemImage: "speedometer")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                row(L("Gesamtschnitt"), Fmt.kmh(overall), L("Tür zu Tür, mit Ampeln und Halten — damit wird die Fahrzeit gerechnet"))
                row(L("Rolltempo"), Fmt.kmh(moving), L("nur die fahrende Zeit — daraus kommt die Einstellung darüber"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else {
            Label(L("Noch keine gemessenen Fahrten"), systemImage: "speedometer")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    /// Eine gemessene Zahl mit ihrem Namen und dem Satz, wofür sie gilt. Die
    /// beiden standen bis 1.3 in einer Zeile nebeneinander („rollend … · Tür
    /// zu Tür …") und waren dadurch nicht auseinanderzuhalten.
    private func row(_ title: String, _ value: String, _ what: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            Text(what)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

/// Und was an seinen Ampeln wirklich passiert: wie oft er hält und wie lange.
/// Daraus wird die Wartezeit je Ampel — der Anteil steht dabei, weil er die
/// Zahl erklärt: wer an jeder dritten Ampel eine halbe Minute steht, wartet je
/// Ampel zehn Sekunden.
struct MeasuredSignalRow: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        if let m = settings.signalMeasurement, m.passes >= AppSettings.signalCalibrationPasses {
            let share = Int((Double(m.stops) / Double(m.passes) * 100).rounded())
            let perStop = m.stops > 0 ? m.wait / Double(m.stops) : 0
            VStack(alignment: .leading, spacing: 1) {
                Label(L("An %d %% der Ampeln gehalten", share), systemImage: "light.beacon.max")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(L("Ø %@ je Halt · Ø %@ je Ampel · %d Vorbeifahrten", Fmt.clock(perStop), Fmt.clock(m.wait / Double(m.passes)), m.passes))
                    .font(.system(size: 11, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}
