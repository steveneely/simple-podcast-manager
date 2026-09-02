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
    private var planningTask: Task<SyncPlan, Error>?

    public init(planner: SyncPlanner = SyncPlanner()) {
        self.planner = planner
        self.plan = nil
        self.isPlanning = false
        self.lastErrorMessage = nil
    }

    public func buildPlan(
        device: DeviceInfo?,
        preparedEpisodes: [PreparedEpisode],
        subscriptions: [FeedSubscription],
        manualDeleteTargets: Set<URL> = [],
        cleanupPolicy: DeviceCleanupPolicy = DeviceCleanupPolicy(),
        excludedCleanupTargets: Set<URL> = [],
        managedInventory: ManagedDeviceLibraryInventory? = nil,
        ejectAfterSync: Bool
    ) async {
        planningTask?.cancel()
        let planningID = UUID()
        latestPlanningID = planningID

        guard let device else {
            plan = nil
            isPlanning = false
            lastErrorMessage = "Select a compatible device before building a sync plan."
            return
        }

        isPlanning = true
        plan = nil
        lastErrorMessage = nil

        do {
            let planner = planner
            let task = Task.detached(priority: .userInitiated) {
                try planner.makePlan(
                    device: device,
                    preparedEpisodes: preparedEpisodes,
                    subscriptions: subscriptions,
                    manualDeleteTargets: manualDeleteTargets,
                    cleanupPolicy: cleanupPolicy,
                    excludedCleanupTargets: excludedCleanupTargets,
                    managedInventory: managedInventory,
                    ejectAfterSync: ejectAfterSync
                )
            }
            planningTask = task
            let updatedPlan = try await task.value
            guard latestPlanningID == planningID else { return }

            plan = updatedPlan
            lastErrorMessage = nil
            planningTask = nil
        } catch is CancellationError {
            return
        } catch {
            guard latestPlanningID == planningID else { return }
            plan = nil
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            planningTask = nil
        }
        if latestPlanningID == planningID {
            isPlanning = false
        }
    }

    /// Immediately prevents an older plan from being started while a replacement is queued.
    public func prepareForPlanRebuild() {
        planningTask?.cancel()
        planningTask = nil
        latestPlanningID = nil
        plan = nil
        isPlanning = true
        lastErrorMessage = nil
    }

    public func cancelPlanning() {
        planningTask?.cancel()
        planningTask = nil
        latestPlanningID = nil
        isPlanning = false
    }
}
