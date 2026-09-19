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

    func options(for mode: TravelMode) -> [TripOption] {
        options.filter { $0.mode == mode }
    }

    func refresh(settings: AppSettings) {
        task?.cancel()
        let start: Date
        switch startTime {
        case .now: start = .now
        case .at(let d): start = d
        }
        let req = PlanRequest(origin: settings.origin, destination: settings.destination,
                              start: start, settings: settings.snapshot)
        isLoading = true
        task = Task {
            let r = await planner.plan(req)
            guard !Task.isCancelled else { return }
            result = r
            selectedID = r.recommendation?.optionID
            lastRun = .now
            isLoading = false
        }
    }
}
