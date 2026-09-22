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

    var when: When = .departNow
    private(set) var result = PlanResult()
    private(set) var isLoading = false
    private(set) var lastRun: Date?
    /// Chosen option per mode; the map draws the one of the active mode in colour.
    var selection: [TravelMode: TripOption.ID] = [:]
    var activeMode: TravelMode = .bike
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

    /// Pull-to-refresh: run and stay in flight until the plan is in, so the
    /// spinner lives as long as the search does.
    func refreshAndWait(settings: AppSettings) async {
        refresh(settings: settings)
        await task?.value
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
        guard let places, !options.isEmpty else { return }
        WatchLink.shared.send(TripSnapshot(origin: places.from, destination: places.to,
                                           options: options,
                                           recommendedID: recommended?.id,
                                           countdownID: activeCountdown?.id,
                                           computedAt: lastRun ?? .now,
                                           arrivalSearch: when.isArrival,
                                           order: modeOrder))
    }

    func refresh(settings: AppSettings) {
        task?.cancel()
        guard let origin = settings.origin, let destination = settings.destination else {
            needsAddresses = true
            result = PlanResult()
            isLoading = false
            return
        }
        needsAddresses = false
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
        task = Task {
            let r = await planner.plan(req)
            guard !Task.isCancelled else { return }
            result = r
            selection = [:]
            if let rec = r.recommendation.flatMap({ rid in r.options.first { $0.id == rid.optionID } }) {
                selection[rec.mode] = rec.id
                activeMode = rec.mode
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
