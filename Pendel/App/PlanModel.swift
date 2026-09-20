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

    private let planner: TripPlanner
    private var task: Task<Void, Never>?
    private var lastDirection: String?

    init(planner: TripPlanner = TripPlanner()) {
        self.planner = planner
    }

    var options: [TripOption] { result.options }

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

    /// Countdown target: with a wanted arrival every mode has a fixed leaving
    /// time, so the chosen trip counts. Otherwise only trains and buses do —
    /// bike and car leave whenever one feels like it.
    var countdownOption: TripOption? {
        if when.isArrival { return selected ?? recommended }
        let withTransit = options.filter { !$0.transitLegs.isEmpty && $0.passesWaypoints }
        if let rec = recommended, !rec.transitLegs.isEmpty { return rec }
        return withTransit.filter { $0.leave > .now }.min { $0.leave < $1.leave } ?? withTransit.first
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
            #if DEBUG
            for o in r.options {
                print("PLAN", o.mode.rawValue, o.bikeRoute?.title ?? "", Fmt.time(o.leave), Fmt.time(o.arrival),
                      o.transitLegs.compactMap(\.lineName))
            }
            #endif
        }
    }
}
