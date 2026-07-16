import Foundation
import Observation
import SimplePodcastManagerCore

@MainActor
@Observable
public final class SyncPlanViewModel {
    public private(set) var plan: SyncPlan?
    public private(set) var isPlanning: Bool
    public private(set) var lastErrorMessage: String?

    private let planner: SyncPlanner
    private var latestPlanningID: UUID?

    public init(planner: SyncPlanner = SyncPlanner()) {
        self.planner = planner
        self.plan = nil
        self.isPlanning = false
        self.lastErrorMessage = nil
    }

    public var actionDescriptions: [String] {
        guard let plan else { return [] }
        return plan.actions.map(\.summaryDescription)
    }

    public func buildPlan(
        device: DeviceInfo?,
        preparedEpisodes: [PreparedEpisode],
        subscriptions: [FeedSubscription],
        manualDeleteTargets: Set<URL> = [],
        ejectAfterSync: Bool
    ) async {
        let planningID = UUID()
        latestPlanningID = planningID

        guard let device else {
            plan = nil
            isPlanning = false
            lastErrorMessage = "Select a compatible device before building a sync plan."
            return
        }

        isPlanning = true

        do {
            let planner = planner
            let updatedPlan = try await Task.detached(priority: .userInitiated) {
                try planner.makePlan(
                    device: device,
                    preparedEpisodes: preparedEpisodes,
                    subscriptions: subscriptions,
                    manualDeleteTargets: manualDeleteTargets,
                    ejectAfterSync: ejectAfterSync
                )
            }.value
            guard latestPlanningID == planningID else { return }

            plan = updatedPlan
            lastErrorMessage = nil
        } catch {
            guard latestPlanningID == planningID else { return }
            plan = nil
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        if latestPlanningID == planningID {
            isPlanning = false
        }
    }

    public func clearPlan() {
        latestPlanningID = nil
        plan = nil
        isPlanning = false
        lastErrorMessage = nil
    }
}
