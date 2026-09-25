import Foundation
import Observation

@MainActor
@Observable
final class PlanModel {
    /// What the user asked for: leave now, leave at a time, or be there at a time.
    enum When: Equatable {
        case departNow
        case departAt(Date)
        case arriveAt(Date)

        var isArrival: Bool { if case .arriveAt = self { true } else { false } }

        var date: Date? {
            switch self {
            case .departNow: nil
            case .departAt(let d), .arriveAt(let d): d
            }
        }
    }

    /// Die drei, die zusammen bestimmen, worauf der Countdown zählt. Sie
    /// werden auch von außen gesetzt — ein Tipp auf eine Beschriftung der
    /// Karte, ein Wechsel der Verkehrsmittel-Box —, und was der Countdown
    /// zählt, muss die im Hintergrund geweckte App erfahren. Deshalb hängt das
    /// Mitschreiben an den Zuständen selbst und nicht an den Methoden: eine
    /// Methode kann man umgehen, eine Zuweisung nicht.
    var when: When = .departNow { didSet { rememberCountdown() } }
    private(set) var result = PlanResult()
    private(set) var isLoading = false
    private(set) var lastRun: Date?
    /// Chosen option per mode; the map draws the one of the active mode in colour.
    var selection: [TravelMode: TripOption.ID] = [:] { didSet { rememberCountdown() } }
    var activeMode: TravelMode = .bike { didSet { rememberCountdown() } }
    private(set) var needsAddresses = false
    /// Straight line between the two ends of the current plan, in kilometres.
    private(set) var directKm = 0.0
    private var longTripKm = PlanSettings().longTripKm
    private var order = TravelMode.defaultOrder

    private let planner: TripPlanner
    private var task: Task<Void, Never>?
    private var lastDirection: String?
    /// Names of the two ends of the current plan, for the copy on the watch.
    private var places: (from: String, to: String)?

    init(planner: TripPlanner = TripPlanner()) {
        self.planner = planner
    }

    var options: [TripOption] { result.options }

    /// A trip across town is a bike ride; Berlin to Hamburg is not.
    var isLongTrip: Bool { directKm > longTripKm }

    /// Order of the four boxes. Beyond `longTripKm` the whole way by bike goes
    /// last — there the answer is the car, the train, or the bike in the train.
    var modeOrder: [TravelMode] {
        isLongTrip ? order.filter { $0 != .bike } + [.bike] : order
    }

    var recommended: TripOption? {
        result.recommendation.flatMap { r in options.first { $0.id == r.optionID } }
    }

    var selected: TripOption? {
        selected(for: activeMode) ?? recommended
    }

    func options(for mode: TravelMode) -> [TripOption] {
        let own = options.filter { $0.mode == mode }
        let sorted = own.filter { !$0.isAlternative } + own.filter(\.isAlternative)
        return sorted.filter(\.passesWaypoints) + sorted.filter { !$0.passesWaypoints }
    }

    func selected(for mode: TravelMode) -> TripOption? {
        let own = options(for: mode)
        return selection[mode].flatMap { id in own.first { $0.id == id } } ?? own.first
    }

    /// Countdown target — only where a departure is actually fixed: a trip with
    /// a train or a bus in it, or any trip once an arrival time is wanted.
    /// Bike and car with "leave now" have nothing to count down to, and the box
    /// stays away instead of showing someone else's train.
    /// Switched off by tapping the pill. Grey then, and no warnings — a plan
    /// one is not going to take should not shout. Forgotten again as soon as a
    /// different departure takes over.
    private(set) var countdownStopped = false
    private var stoppedFor: TripOption.ID?

    /// What the countdown actually runs on: nothing while it is switched off.
    var activeCountdown: TripOption? { countdownStopped ? nil : countdownOption }

    /// Tap on the pill.
    func toggleCountdown() {
        countdownStopped.toggle()
        stoppedFor = countdownStopped ? countdownOption?.id : nil
        publishToWatch()
    }

    /// A new departure is a new question; the old "no thanks" does not carry.
    private func forgetStopIfDepartureChanged() {
        guard countdownStopped, stoppedFor != countdownOption?.id else { return }
        countdownStopped = false
        stoppedFor = nil
    }

    var countdownOption: TripOption? {
        guard let trip = selected else { return nil }
        if when.isArrival { return trip }
        return trip.transitLegs.isEmpty ? nil : trip
    }

    /// Going to work means "be there at 9", coming home means "leave now" —
    /// applied when the direction changes, never overriding a manual choice.
    func applyDefaultWhen(settings: AppSettings) {
        let direction = "\(settings.origin?.name ?? "")→\(settings.destination?.name ?? "")"
        guard direction != lastDirection else { return }
        lastDirection = direction
        if settings.isWork(settings.destination) {
            when = .arriveAt(DeparturePreset.clock(settings.workArrivalMinutes / 60,
                                                   settings.workArrivalMinutes % 60).date())
        } else {
            when = .departNow
        }
    }

    /// Stops whatever is in flight. Tapping an address field calls this: a
    /// long-distance search occupies the network and the main thread for
    /// seconds, and waiting for it before one can even type a new destination
    /// is the wrong way round — the old plan is worthless anyway.
    func cancel() {
        task?.cancel()
        task = nil
        isLoading = false
    }

    /// Pull-to-refresh: run and stay in flight until the plan is in, so the
    /// spinner lives as long as the search does. **Immer**: wer von Hand
    /// nachfragt, will eine neue Antwort, auch wenn die alte noch frisch ist.
    func refreshAndWait(settings: AppSettings) async {
        refresh(settings: settings, force: true)
        await task?.value
    }

    /// Woran eine Planung hängt — die beiden Adressen, die Frage und die
    /// Wertkopie der Einstellungen. Ist alles davon gleich geblieben, kommt
    /// dieselbe Antwort heraus.
    private struct Mark: Equatable {
        var origin: Place
        var destination: Place
        var when: When
        var settings: PlanSettings
    }

    private var lastMark: Mark?
    /// So lange gilt eine Antwort als frisch genug, um sie nicht zu
    /// wiederholen. Eine volle Planung sind gut zwei Dutzend Anfragen; sie
    /// zweimal in derselben Minute für dieselbe Frage zu stellen, ist
    /// verschenkter Strom. Von Hand nachfragen (`force`) geht immer.
    static let reuseWithin: TimeInterval = 60

    /// What the wrist picked, applied here. The watch shows the phone's plan,
    /// so a choice made there means the same trip as a choice made here.
    func apply(_ choice: WatchChoice) {
        guard let mode = TravelMode(rawValue: choice.mode) else { return }
        let own = options(for: mode)
        guard !own.isEmpty else { return }
        activeMode = mode
        selection[mode] = own[min(max(choice.index, 0), own.count - 1)].id
        forgetStopIfDepartureChanged()
        publishToWatch()
    }

    /// Tap on an already-chosen mode: step to its next option (bike variants,
    /// the next connection) and wrap around at the end.
    func cycle(_ mode: TravelMode) {
        let own = options(for: mode)
        guard own.count > 1 else { return }
        let current = selected(for: mode)?.id
        let i = own.firstIndex { $0.id == current } ?? 0
        selection[mode] = own[(i + 1) % own.count].id
        forgetStopIfDepartureChanged()
        publishToWatch()
    }

    /// Long press on a mode: back to its first option, which is its best one.
    func selectFirst(_ mode: TravelMode) {
        guard let first = options(for: mode).first else { return }
        selection[mode] = first.id
        forgetStopIfDepartureChanged()
        publishToWatch()
    }

    /// Hands the watch the plan and the trip its countdown should run on.
    /// Called after every search and whenever the chosen trip changes — the
    /// watch never plans anything itself, it mirrors what the phone decided.
    func publishToWatch() {
        rememberCountdown()
        guard let places, !options.isEmpty else { return }
        WatchLink.shared.send(TripSnapshot(origin: places.from, destination: places.to,
                                           options: options,
                                           recommendedID: recommended?.id,
                                           countdownID: activeCountdown?.id,
                                           computedAt: lastRun ?? .now,
                                           arrivalSearch: when.isArrival,
                                           order: modeOrder))
    }

    /// Was der Countdown gerade zählt, für die App, die iOS im Hintergrund
    /// weckt. Sie stellt damit dieselbe Frage wie dieser Bildschirm — eine
    /// geweckte App, die sich selbst eine Verbindung sucht, warnt zuverlässig
    /// vor dem falschen Zug.
    private func rememberCountdown() {
        guard let trip = activeCountdown else { return BackgroundReplan.remember(nil) }
        BackgroundReplan.remember(.init(mode: trip.mode.rawValue, date: when.date,
                                        isArrival: when.isArrival))
    }

    func refresh(settings: AppSettings, force: Bool = false) {
        guard let origin = settings.origin, let destination = settings.destination else {
            task?.cancel()
            needsAddresses = true
            result = PlanResult()
            isLoading = false
            lastMark = nil
            return
        }
        needsAddresses = false
        // Dieselbe Frage, gerade erst beantwortet: die Antwort steht schon da.
        let mark = Mark(origin: origin, destination: destination, when: when, settings: settings.snapshot)
        if !force, mark == lastMark, !options.isEmpty,
           let lastRun, Date.now.timeIntervalSince(lastRun) < Self.reuseWithin {
            return
        }
        task?.cancel()
        lastMark = mark
        let target: PlanTarget = switch when {
        case .departNow: .departAfter(.now)
        case .departAt(let d): .departAfter(d)
        case .arriveAt(let d): .arriveBy(d)
        }
        let req = PlanRequest(origin: origin, destination: destination, target: target,
                              settings: settings.snapshot)
        places = (origin.shortName, destination.shortName)
        directKm = origin.coordinate.distance(to: destination.coordinate) / 1000
        longTripKm = settings.snapshot.longTripKm
        order = settings.modeOrder
        isLoading = true
        task = Task { @MainActor [weak self] in
            // Zwischenstände: jeder Modus, sobald er da ist. Die Auswahl
            // bleibt unangetastet — sie wird erst gesetzt, wenn alles steht,
            // sonst springt die aktive Box, während man schon darauf tippt.
            let r = await planner.plan(req) { partial in
                guard let self, !Task.isCancelled else { return }
                self.result = partial
            }
            guard let self, !Task.isCancelled else { return }
            result = r
            selection = [:]
            if let rec = r.recommendation.flatMap({ rid in r.options.first { $0.id == rid.optionID } }) {
                selection[rec.mode] = rec.id
            }
            // Aktiv ist die **erste Kategorie der eigenen Reihenfolge**, die
            // etwas gefunden hat — nicht die empfohlene. Wer das Rad nach oben
            // gestellt hat, will die Radroute sehen; der Stern sagt trotzdem,
            // was die App für die bessere Wahl hält.
            if let first = modeOrder.first(where: { m in r.options.contains { $0.mode == m } }) {
                activeMode = first
            }
            lastRun = .now
            isLoading = false
            forgetStopIfDepartureChanged()
            // Whatever lines this plan used go into the list the user judges.
            settings.noteLines(r.options.flatMap(\.transitLegs).compactMap { leg in
                leg.lineName.map { ($0, leg.bikeCarriage) }
            })
            publishToWatch()
            #if DEBUG
            for o in r.options {
                print("PLAN", o.mode.rawValue, o.bikeRoute?.title ?? "", Fmt.time(o.leave), Fmt.time(o.arrival),
                      o.transitLegs.compactMap(\.lineName))
            }
            #endif
        }
    }
}
