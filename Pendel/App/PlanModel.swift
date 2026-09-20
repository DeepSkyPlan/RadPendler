import Foundation
import Observation

@MainActor
@Observable
final class PlanModel {
    enum StartTime: Equatable {
        case now
        case at(Date)
    }

    var startTime: StartTime = .now
    private(set) var result = PlanResult()
    private(set) var isLoading = false
    private(set) var lastRun: Date?
    var selectedID: TripOption.ID?

    private let planner: TripPlanner
    private var task: Task<Void, Never>?

    init(planner: TripPlanner = TripPlanner()) {
        self.planner = planner
    }

    var options: [TripOption] { result.options }

    var recommended: TripOption? {
        result.recommendation.flatMap { r in options.first { $0.id == r.optionID } }
    }

    var selected: TripOption? {
        options.first { $0.id == selectedID } ?? recommended ?? options.first
    }

    /// The trip the header counts down to: the recommended one if it uses a
    /// train or bus, otherwise the next such trip that has not left yet.
    var countdownOption: TripOption? {
        let withTransit = options.filter { !$0.transitLegs.isEmpty && $0.passesWaypoints }
        if let rec = recommended, !rec.transitLegs.isEmpty { return rec }
        return withTransit.filter { $0.leave > .now }.min { $0.leave < $1.leave } ?? withTransit.first
    }

    func options(for mode: TravelMode) -> [TripOption] {
        // Stable: U-Bahn/tram alternatives after the S-Bahn/regional connections.
        let own = options.filter { $0.mode == mode }
        let sorted = own.filter { !$0.isAlternative } + own.filter(\.isAlternative)
        return sorted.filter(\.passesWaypoints) + sorted.filter { !$0.passesWaypoints }
    }

    /// True until both addresses are set — the list then explains instead of searching.
    private(set) var needsAddresses = false

    func refresh(settings: AppSettings) {
        task?.cancel()
        guard let origin = settings.origin, let destination = settings.destination else {
            needsAddresses = true
            result = PlanResult()
            isLoading = false
            return
        }
        needsAddresses = false
        let start: Date
        switch startTime {
        case .now: start = .now
        case .at(let d): start = d
        }
        let req = PlanRequest(origin: origin, destination: destination,
                              start: start, settings: settings.snapshot)
        isLoading = true
        task = Task {
            let r = await planner.plan(req)
            guard !Task.isCancelled else { return }
            result = r
            #if DEBUG
            for o in r.options {
                let st = o.bikeRoute?.stats
                print("PLAN", o.mode.rawValue, o.bikeRoute?.title ?? "", Fmt.time(o.leave), Fmt.time(o.arrival),
                      Int(o.bikeDistance), st.map { "signals \($0.signals) crossings \($0.crossings) main \(Int($0.mainRoadMeters))" } ?? "",
                      o.transitLegs.compactMap(\.lineName))
            }
            #endif
            selectedID = r.recommendation?.optionID
            lastRun = .now
            isLoading = false
        }
    }
}
