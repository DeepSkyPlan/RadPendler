import MapKit
import SwiftUI

/// The screen while a ride is being recorded: the map, large, with the way
/// taken drawn on it in the colours of the speed it was taken at — and the
/// four numbers that are worth looking at on a bike.
///
/// It takes the whole screen on purpose. Everything the planning screen offers
/// is about a trip that has not started yet; this one has.
struct RideTrackingView: View {
    @Environment(RideTracker.self) private var tracker
    @Environment(AppSettings.self) private var settings
    @Environment(\.verticalSizeClass) private var heightClass
    @Environment(\.scenePhase) private var phase
    var options: [TripOption]
    var selectedID: TripOption.ID?
    /// Ends the ride and hands back its summary.
    var onStop: () -> Void

    @State private var following = true
    @State private var confirmStop = false
    /// Der Bildschirm, der nach einer Weile dunkel wird — und beim ersten
    /// Antippen wieder hell.
    @State private var screen = ScreenDim()
    /// Wann zuletzt etwas passiert ist, das den Bildschirm wachhält: eine
    /// Berührung, eine Abbiegung, ein Abweichen von der Route.
    @State private var lastTouch = Date.now
    /// Ob das Telefon am Strom hängt — dann wird gar nicht erst gedunkelt.
    @State private var onPower = ScreenDim.onPower
    /// When the map was last dragged. The camera comes back on its own after
    /// `Self.recenterAfter` — nobody wants to remember to press a button again
    /// while riding, and a map that stays where it was pushed is a map that
    /// stops being useful a hundred metres later.
    @State private var pannedAt: Date?
    static let recenterAfter: Duration = .seconds(30)

    private var isLandscape: Bool { heightClass == .compact }

    /// Die Farbskala dieser Fahrt. Ein Auto ist auf einer Radskala überall
    /// tiefgrün; dann sagt die Linie nichts mehr.
    private var scale: RideColors.Scale {
        .of(tracker.subject.flatMap { TravelMode(rawValue: $0.mode) })
    }

    /// Neu gesetzt heißt: die Uhr fängt von vorn an — auch, wenn das Telefon
    /// gerade an den Strom gekommen ist: sonst liefe der Schlafauftrag von
    /// vorhin weiter und dunkelte ab, obwohl längst geladen wird.
    private var dimKey: String { "\(Int(lastTouch.timeIntervalSince1970))|\(onPower)" }

    /// Beim Ziehen über die Karte kommen Dutzende Ereignisse je Sekunde. Die
    /// Uhr deshalb höchstens sekündlich neu stellen — sonst startet der
    /// Schlafauftrag mit jedem Fingerzucken neu.
    private func touched() {
        screen.wake()
        guard Date.now.timeIntervalSince(lastTouch) > 1 else { return }
        lastTouch = .now
    }

    var body: some View {
        @Bindable var settings = settings
        // No timeline around the whole screen: the clock needs a tick a
        // second, the map does not, and re-making the map view once a second
        // is work for nothing while a thumb is on it.
        ZStack(alignment: .topLeading) {
            map
            if isLandscape {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 8) {
                        banner
                        controls(settings: $settings.rideOrientation)
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                    panel.frame(width: 260)
                }
                .padding(10)
            } else {
                VStack(spacing: 8) {
                    banner
                    controls(settings: $settings.rideOrientation)
                    Spacer(minLength: 0)
                    panel
                }
                .padding(10)
            }
        }
        // Jede Berührung macht hell und stellt die Uhr zurück. `simultaneous`,
        // damit Knöpfe und Karte darunter weiter bedienbar bleiben.
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in touched() })
        // Und alles, was die App von sich aus zu sagen hat, macht ebenfalls
        // hell: eine Abbiegung, die ansteht, und der Weg zurück zur Route.
        .onChange(of: showsTurn) { _, on in if on { touched() } }
        .onChange(of: tracker.detour != nil) { _, off in if off { touched() } }
        // Während einer Pause ist ohnehin nichts zu sehen.
        .onChange(of: tracker.isPaused) { _, paused in if paused { screen.dim() } else { touched() } }
        // Am Lenker in der Ladeschale ist das Abdunkeln überflüssig: der
        // Bildschirm kostet dann nichts, was nicht nachkommt.
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
            onPower = ScreenDim.onPower
            if onPower { screen.wake() } else { lastTouch = .now }
        }
        .task(id: dimKey) {
            guard settings.rideDimSeconds > 0, !onPower else { return }
            try? await Task.sleep(for: .seconds(settings.rideDimSeconds))
            guard !Task.isCancelled else { return }
            screen.dim()
        }
        // Fahrtende, Wechsel in den Hintergrund, Abbruch: die Helligkeit
        // gehört dem ganzen Telefon, nicht dieser Ansicht.
        .onDisappear { screen.wake() }
        // Die Helligkeit gehört dem ganzen Telefon: wer die App verlässt, darf
        // sie nicht gedimmt vorfinden.
        .onChange(of: phase) { _, now in
            if now == .active { touched() } else { screen.wake() }
        }
        // Restarts whenever the map is dragged again, so thirty seconds means
        // thirty seconds since the *last* touch.
        .task(id: pannedAt) {
            guard pannedAt != nil else { return }
            try? await Task.sleep(for: Self.recenterAfter)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut) { following = true }
            pannedAt = nil
        }
        .confirmationDialog(L("Fahrt beenden?"), isPresented: $confirmStop, titleVisibility: .visible) {
            Button(L("Fahrt beenden"), role: .destructive, action: onStop)
            Button(L("Weiterfahren"), role: .cancel) {}
        } message: {
            Text(L("Die Aufzeichnung wird gespeichert und die Ortung hört auf."))
        }
    }

    /// The way that is actually ridden: the transit legs are somebody else's
    /// steering.
    static func route(of options: [TripOption], selected: TripOption.ID?) -> [CLLocationCoordinate2D] {
        guard let option = options.first(where: { $0.id == selected }) ?? options.first else { return [] }
        return option.legs.filter { !$0.isTransit }.flatMap(\.coordinates)
    }

    private var map: some View {
        RouteMapView(options: options, selectedID: selectedID, radarFrames: [], radarTime: nil,
                     track: tracker.meter.points, speedScale: scale,
                     trackStops: tracker.meter.stops,
                     // Nur die Ampeln **dieser** Route: `tracker.signals` hat
                     // zusätzlich alles Gelernte quer durch die Stadt.
                     signals: tracker.plannedSignals,
                     guidedLine: tracker.plannedRoute,
                     // Nach einer Neuplanung liegt die ursprüngliche Linie dünn
                     // daneben — sonst wüsste niemand, dass sich etwas geändert
                     // hat.
                     plannedLine: tracker.replans > 0 ? tracker.originalRoute : [],
                     rider: tracker.here, course: tracker.course, following: following,
                     showBoth: tracker.detour?.nearest,
                     onPan: {
                         following = false
                         pannedAt = .now
                     },
                     // Room for the turn banner, so MapKit's compass does not
                     // end up behind it.
                     topInset: !showsTurn && tracker.detour == nil ? 0 : 96)
            .ignoresSafeArea()
    }

    /// Neben der Route zählt nicht, wo man als Nächstes abbiegt — die
    /// Abbiegung liegt auf einer Straße, auf der man nicht ist. Dann zählt nur,
    /// wo die Route liegt, und das sagt ein Pfeil.
    @ViewBuilder private var banner: some View {
        if tracker.detour != nil { detourBanner } else if showsTurn { turnBanner }
    }

    /// So kurz vor einer Abbiegung steht der Pfeil da — und keinen Meter
    /// früher. Ein Pfeil, der zwei Kilometer lang „rechts" sagt, ist kein
    /// Hinweis, sondern Tapete: man sieht ihn nicht mehr an, wenn es so weit
    /// ist. Und er nimmt der Karte die obersten hundert Punkte.
    static let announceMeters = 250.0

    private var showsTurn: Bool {
        guard let next = tracker.nextTurn else { return false }
        return next.meters <= Self.announceMeters
    }

    /// Der Pfeil zeigt **auf der Karte**, nicht nach Norden. Die Karte ist in
    /// Fahrtrichtung gedreht, also ist die Richtung zur Route auf dem
    /// Bildschirm `Richtung − Kurs` — dieselbe Rechnung wie beim Fahrerpfeil.
    /// Ohne bekannten Kurs steht die Karte nach Norden, dann ist es die
    /// Richtung selbst.
    @ViewBuilder private var detourBanner: some View {
        if let detour = tracker.detour {
            HStack(spacing: 12) {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 34, weight: .heavy))
                    .rotationEffect(.degrees(detour.bearing - (tracker.course >= 0 ? tracker.course : 0)))
                    .frame(width: 46)
                VStack(alignment: .leading, spacing: -2) {
                    Text(Fmt.km(detour.meters))
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(detour.meters > OffRoute.replanMeters ? L("neben der Route — wird neu geplant")
                                                               : L("neben der Route"))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .opacity(0.9)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Rot: das hier ist das Einzige auf diesem Bildschirm, das
            // bedeutet „du bist falsch". Der Abbiegepfeil ist grün, weil er
            // das Gegenteil sagt.
            .background(Theme.gradient(.red), in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L("%@ neben der Route, Richtung %@", Fmt.km(detour.meters), Self.compass(detour.bearing)))
        }
    }

    /// Für die Ansage: aus Grad wird eine Himmelsrichtung. „Nordost" ist etwas,
    /// das man hören kann; „siebenundvierzig Grad" nicht.
    static func compass(_ degrees: Double) -> String {
        let names = [L("Norden"), L("Nordosten"), L("Osten"), L("Südosten"), L("Süden"), L("Südwesten"), L("Westen"), L("Nordwesten")]
        let i = Int(((degrees.truncatingRemainder(dividingBy: 360) + 360) / 45).rounded()) % 8
        return names[i]
    }

    /// The one line worth a glance at twenty km/h: what comes, and in how far.
    @ViewBuilder private var turnBanner: some View {
        if let next = tracker.nextTurn {
            HStack(spacing: 12) {
                Image(systemName: next.step.turn.symbol)
                    .font(.system(size: 38, weight: .heavy))
                    .frame(width: 46)
                VStack(alignment: .leading, spacing: -2) {
                    Text(Fmt.km(next.meters))
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(next.step.turn.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .opacity(0.9)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.gradient(LegKind.bike.color), in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L("Nächste Abbiegung %@ in %@", next.step.turn.title, Fmt.km(next.meters)))
        }
    }

    private func controls(settings orientation: Binding<OrientationLock>) -> some View {
        HStack(spacing: 8) {
            followButton
            OrientationButton(lock: orientation)
            automaticsButton
            Spacer(minLength: 0)
        }
    }

    /// Was die Aufzeichnung bei langem Stillstand von selbst tun darf —
    /// im Kreis: anhalten und beenden → nur beenden → durchfahren.
    ///
    /// Die Stellung gilt für **diese** Fahrt; beim nächsten Start steht sie
    /// wieder auf der ersten. Es ist ein Knopf für die Ausnahme, keine
    /// Einstellung — die steht in den Einstellungen.
    private var automaticsButton: some View {
        Button {
            tracker.cycleAutomatic()
        } label: {
            Image(systemName: tracker.automatic.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tracker.automatic == .full ? Theme.accent : .white)
                .frame(width: 36, height: 36)
                .background(tracker.automatic == .full ? AnyShapeStyle(.regularMaterial)
                                                      : AnyShapeStyle(Theme.gradient(tracker.automatic == .off ? .red : .orange)),
                            in: Circle())
        }
        .accessibilityLabel(L("Automatik: %@. Tippen für %@.",
                              tracker.automatic.title, tracker.automatic.next.title))
    }

    /// Following gives way to a hand on the map; this is the way back, and it
    /// says how long the map will stay put.
    private var followButton: some View {
        Button {
            following.toggle()
            pannedAt = following ? nil : .now
        } label: {
            Image(systemName: following ? "location.fill" : "location")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(following ? .white : Theme.accent)
                .frame(width: 36, height: 36)
                .background(following ? AnyShapeStyle(Theme.gradient(Theme.accent))
                                      : AnyShapeStyle(.regularMaterial), in: Circle())
        }
        .accessibilityLabel(following ? L("Karte folgt dir") : L("Karte folgt dir nicht, kommt in 30 Sekunden zurück"))
    }

    private var panel: some View {
        VStack(spacing: 8) {
            header
            // Only these two numbers run on a clock.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 8) {
                    clock(now: context.date)
                    numbers(now: context.date)
                    signalRow(now: context.date)
                    if let left = remaining {
                        arrivalRow(left, now: context.date)
                    }
                }
            }
            HStack(spacing: 8) {
                pauseButton
                stopButton
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let mode = tracker.subject.flatMap({ TravelMode(rawValue: $0.mode) }) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(mode.color)
            }
            Text("\(tracker.subject?.origin ?? "") → \(tracker.subject?.destination ?? "")")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            // Wie oft unterwegs neu geplant wurde. Steht nur da, wenn es
            // passiert ist — und dann als Zahl, nicht als Gefühl: „die Route
            // hat sich nie angepasst" ist sonst nicht von „sie hat sich
            // dreimal angepasst und sah jedes Mal gleich aus" zu unterscheiden.
            if tracker.replans > 0 {
                Label(L("%d×", tracker.replans), systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel(L("%d× neu geplant", tracker.replans))
            }
            if tracker.isPaused {
                Label(tracker.autoPaused ? L("hält") : L("Pause"), systemImage: "pause.circle.fill")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
            } else if tracker.meter.isStanding {
                Label(L("steht"), systemImage: "pause.circle.fill")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
            }
        }
    }

    private func clock(now: Date) -> some View {
        Text(Fmt.clock(tracker.seconds(at: now)))
            .font(.system(size: 46, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(L("Fahrzeit %@", Fmt.clock(tracker.seconds(at: now))))
    }

    /// The current speed is the number one looks at while riding, so it gets
    /// the room: big, heavy, in the colour the line is being drawn in. The
    /// average and the distance are for afterwards and may be small.
    private func numbers(now: Date) -> some View {
        HStack(spacing: 8) {
            VStack(spacing: -4) {
                Text(Fmt.kmh(tracker.meter.currentSpeed * 3.6))
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(scale.color(tracker.meter.currentSpeed * 3.6))
                Text(L("jetzt"))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: Theme.innerCorner))
            VStack(spacing: 6) {
                averageTile(now: now)
                tile(L("Strecke"), Fmt.km(tracker.meter.meters), tint: .primary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Der gefahrene Schnitt und der geplante in **einem** Feld: „13,2 / 14,7
    /// Plan". Zwei Felder nebeneinander waren zweimal dieselbe Frage, und die
    /// interessante Antwort ist ohnehin der Unterschied. Grün, solange man
    /// schneller ist als angekündigt.
    private func averageTile(now: Date) -> some View {
        let measured = tracker.averageKmh(at: now)
        let planned = tracker.plannedAverageKmh
        let ahead = planned.map { measured >= $0 } ?? true
        return VStack(spacing: -1) {
            Text(planned == nil ? L("Ø") : L("Ø / Plan"))
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
            Text(planned.map { "\(Fmt.kmh(measured)) / \(($0).formatted(.number.precision(.fractionLength(1))))" }
                 ?? Fmt.kmh(measured))
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(planned == nil ? Theme.accent : (ahead ? .green : .orange))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: Theme.innerCorner))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(planned.map { L("Schnitt %@, geplant %@", Fmt.kmh(measured), Fmt.kmh($0)) }
                            ?? L("Schnitt %@", Fmt.kmh(measured)))
    }

    /// The count the whole recording is for.
    /// Ampelhalts, die dort verbrachte Zeit — und daneben, was **insgesamt**
    /// gestanden wurde. Die beiden Zahlen sind nicht dasselbe: an der Ampel
    /// wartet man, im Stau und vor der eigenen Haustür auch, und auf einer
    /// Pendelfahrt ist der Unterschied genau das, was man wissen will.
    private func signalRow(now: Date) -> some View {
        // Einschließlich des Halts, an dem man **gerade** steht: eine
        // Wartezeit, die erst beim Losfahren um eine Minute springt, ist keine
        // Anzeige. Sekündlich, weil der Kasten ohnehin sekündlich tickt.
        let live = tracker.meter.liveSignals(at: now)
        let stops = live.stops
        let total = live.wait
        let planned = tracker.progress?.plannedSignals ?? 0
        let standing = max(0, tracker.meter.seconds(at: now) - tracker.meter.movingSeconds)
        return HStack(spacing: 8) {
            TrafficLightIcon()
            VStack(alignment: .leading, spacing: 0) {
                // „3/9": gehalten von geplant. Ohne Plan bleibt es bei der Zahl.
                Text(planned > 0 ? L("%d/%d Ampeln", stops, planned)
                                 : L(stops == 1 ? "%d Ampelhalt" : "%d Ampelhalts", stops))
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(stops == 0 ? L("noch keine Wartezeit")
                     : L("%@ gewartet · Ø %@", Fmt.clock(total), Fmt.clock(total / Double(stops))))
                    .font(.system(size: 11, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                Text(Fmt.clock(standing))
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(tracker.meter.otherStops > 0
                     ? L("gestanden · %d sonst", tracker.meter.otherStops)
                     : L("gestanden"))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: Theme.innerCorner))
    }

    /// Was noch kommt: Strecke, Restzeit, Ankunft. Gerechnet wird mit
    /// demselben Modell wie beim Planen — Strecke durch Rolltempo plus
    /// Wartezeit für die Ampeln, die noch vor einem liegen.
    var remaining: RideRemaining? {
        RideRemaining.from(progress: tracker.progress, tracker: tracker, settings: settings)
    }

    private func arrivalRow(_ left: RideRemaining, now: Date) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(LegKind.bike.color)
            VStack(alignment: .leading, spacing: 0) {
                Text(L("noch %@", Fmt.duration(left.seconds)))
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("\(Fmt.km(left.meters))\(left.signals > 0 ? " · \(left.signals) Ampeln" : "")")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                Text(Fmt.time(now.addingTimeInterval(left.seconds)))
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(L("Ankunft")).font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: Theme.innerCorner))
    }

    /// Eine gewollte Unterbrechung: Einkauf, Kaffee, Panne. Die Uhr steht,
    /// die Ortung auch — die Pause zählt weder zur Fahrzeit noch als Halt,
    /// und der Empfänger bleibt so lange aus. Das ist zugleich der einzige
    /// Knopf dieses Bildschirms, der wirklich Strom spart.
    private var pauseButton: some View {
        Button {
            if tracker.isPaused { tracker.resume() } else { tracker.pause() }
        } label: {
            Label(tracker.isPaused ? L("Weiter") : L("Pause"),
                  systemImage: tracker.isPaused ? "play.circle.fill" : "pause.circle.fill")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.gradient(tracker.isPaused ? LegKind.bike.color : .orange), in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tracker.isPaused ? L("Fahrt fortsetzen") : L("Fahrt anhalten"))
    }

    private var stopButton: some View {
        Button { confirmStop = true } label: {
            Label(L("Fahrt beenden"), systemImage: "stop.circle.fill")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.gradient(.red), in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private func tile(_ title: String, _ value: String, tint: Color) -> some View {
        VStack(spacing: -1) {
            Text(title)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: Theme.innerCorner))
    }
}

/// Was von einer laufenden Fahrt noch übrig ist: Strecke, Ampeln, Zeit.
///
/// Gerechnet wie beim Planen — Strecke durch das rollende Tempo plus die
/// Wartezeit für die Ampeln, die noch kommen —, und mit derselben Regel: wo
/// es einen gemessenen Schnitt gibt, gilt der.
struct RideRemaining: Equatable {
    var meters: Double
    var signals: Int
    var seconds: TimeInterval

    /// Wie lange es noch dauert — **in dem Tempo, das diese Fahrt hat**.
    ///
    /// Bis 1.4 rechnete das hier immer mit dem Rolltempo des Fahrrads und dem
    /// gemessenen Radschnitt, auch wenn gerade Auto gefahren wurde: dreißig
    /// Kilometer Landstraße kamen als anderthalb Stunden heraus, weil zwanzig
    /// km/h eingesetzt wurden. Jetzt zählt in dieser Reihenfolge:
    ///
    /// 1. **Was diese Fahrt bisher wirklich geschafft hat**, sobald genug
    ///    davon zurückliegt (`enoughToJudge`). Das ist die ehrlichste Zahl: sie
    ///    kennt den Stau, den Gegenwind und die Ampeln dieses Tages.
    /// 2. **Was der Plan versprochen hat** — Strecke durch Zeit, also der
    ///    Schnitt der geplanten Fahrt, mit ihren Ampeln darin.
    /// 3. Erst wenn beides fehlt, das eingestellte Rolltempo plus Wartezeit je
    ///    Ampel; das gilt dann für ein Rad, denn nur dafür ist es gedacht.
    @MainActor
    static func from(progress: RideTracker.Progress?, tracker: RideTracker,
                     settings: AppSettings, now: Date = .now) -> RideRemaining? {
        from(progress: progress, ridden: tracker.meter.meters,
             rideKmh: tracker.averageKmh(at: now), plannedKmh: tracker.plannedAverageKmh,
             settings: settings)
    }

    /// Die Rechnung selbst, ohne Tracker — so lässt sie sich prüfen, ohne
    /// einen Ortungsdienst zu starten.
    static func from(progress: RideTracker.Progress?, ridden: Double, rideKmh: Double,
                     plannedKmh: Double?, settings: AppSettings) -> RideRemaining? {
        guard let p = progress, p.plannedMeters > 0, p.metersLeft > 10 else { return nil }
        let left = p.metersLeft
        if ridden >= enoughToJudge, rideKmh > 1 {
            return RideRemaining(meters: left, signals: p.signalsLeft,
                                 seconds: (left / (rideKmh / 3.6)).rounded())
        }
        if let planned = plannedKmh, planned > 1 {
            return RideRemaining(meters: left, signals: p.signalsLeft,
                                 seconds: (left / (planned / 3.6)).rounded())
        }
        let rolling = Swift.max(5.0, settings.bikeSpeedKmh) / 3.6
        var seconds = left / rolling + Double(p.signalsLeft * settings.signalWaitSeconds)
        if settings.measuredRides >= AppSettings.calibrationRides,
           let kmh = settings.measuredOverallKmh, kmh > 0 {
            seconds = left / (kmh / 3.6)
        }
        return RideRemaining(meters: left, signals: p.signalsLeft, seconds: seconds.rounded())
    }

    /// So viel muss gefahren sein, bevor der laufende Schnitt die Restzeit
    /// bestimmt. Darunter ist er das Ausrollen aus der Einfahrt: nach
    /// dreihundert Metern steht dort eine Zahl, die nichts über die nächsten
    /// dreißig Kilometer sagt.
    static let enoughToJudge = 2_000.0
}

/// Während einer Fahrt steht in der Leiste nicht mehr, wann man losgehen soll
/// — man ist los. Statt dessen: wie lange es noch dauert und wann man da ist.
///
/// Eigene Uhr statt `TimelineView`, aus demselben Grund wie beim Countdown:
/// ein `TimelineView` in einer Werkzeugleiste legt die Leiste bei jedem Takt
/// neu aus und dreht den Hauptthread mit voller Bildrate im Kreis.
struct RideArrivalPill: View {
    @Environment(RideTracker.self) private var tracker
    @Environment(AppSettings.self) private var settings
    @State private var now = Date.now

    var body: some View {
        let left = RideRemaining.from(progress: tracker.progress, tracker: tracker, settings: settings)
        HStack(spacing: 4) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 9, weight: .bold))
            Text(left.map { Fmt.duration($0.seconds) } ?? L("läuft"))
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
            if let left {
                Text(Fmt.time(now.addingTimeInterval(left.seconds)))
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .padding(.horizontal, 3).padding(.vertical, 0.5)
                    .background(.white.opacity(0.25), in: RoundedRectangle(cornerRadius: 3))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.gradient(LegKind.bike.color), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(left.map { L("Noch %@, Ankunft %@", Fmt.duration($0.seconds), Fmt.time(now.addingTimeInterval($0.seconds))) }
                            ?? L("Fahrt läuft"))
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                now = .now
            }
        }
    }
}

/// What the ride was, right after it ended — the one moment one actually wants
/// to read the numbers.
struct RideSummarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RideStore.self) private var store
    @Environment(RideTracker.self) private var tracker
    var ride: Ride
    @State private var track: RideTrack?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if tracker.stoppedByItself {
                        Label(L("Von selbst beendet: du standst lange an derselben Stelle, und dort ist keine Ampel. Gezählt wurde bis zum Anfang des Stillstands."),
                              systemImage: "stopwatch")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    RideFacts(ride: ride, track: track)
                    RideMapCard(ride: ride)
                        .frame(height: 260)
                }
                .padding(Theme.gutter)
            }
            .task { track = await store.track(for: ride) }
            .background(Theme.background)
            .navigationTitle(L("Angekommen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Fertig")) { dismiss() } }
            }
        }
    }
}
