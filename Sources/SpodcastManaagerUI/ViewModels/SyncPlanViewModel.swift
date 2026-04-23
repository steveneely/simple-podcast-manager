import Foundation
import Observation
import SpodcastManaagerCore

@MainActor
@Observable
public final class SyncPlanViewModel {
    public private(set) var plan: SyncPlan?
    public private(set) var isPlanning: Bool
    public private(set) var lastErrorMessage: String?

    private let planner: SyncPlanner

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
        ejectAfterSync: Bool,
        isDryRun: Bool
    ) {
        guard let device else {
            plan = nil
            lastErrorMessage = "Select a compatible device before building a sync plan."
            return
        }

        isPlanning = true
        defer { isPlanning = false }

        do {
            plan = try planner.makePlan(
                device: device,
                preparedEpisodes: preparedEpisodes,
                subscriptions: subscriptions,
                manualDeleteTargets: manualDeleteTargets,
                ejectAfterSync: ejectAfterSync,
                isDryRun: isDryRun
            )
            lastErrorMessage = nil
        } catch {
            plan = nil
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func clearPlan() {
        plan = nil
        lastErrorMessage = nil
    }
}
