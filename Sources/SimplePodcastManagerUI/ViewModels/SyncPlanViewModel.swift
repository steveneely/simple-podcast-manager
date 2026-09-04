import Foundation
import Observation
import SimplePodcastManagerCore

@MainActor
@Observable
public final class SyncPlanViewModel {
    public private(set) var plan: SyncPlan?
    public private(set) var isPlanning: Bool
    public private(set) var planningErrorTitle: String?
    public private(set) var lastErrorMessage: String?
    public private(set) var incompleteCopyRecoveryTarget: URL?
    public private(set) var isReplacementPlanReady: Bool

    private let planner: SyncPlanner
    private var latestPlanningID: UUID?
    private var planningTask: Task<SyncPlan, Error>?

    public init(planner: SyncPlanner = SyncPlanner()) {
        self.planner = planner
        self.plan = nil
        self.isPlanning = false
        self.planningErrorTitle = nil
        self.lastErrorMessage = nil
        self.incompleteCopyRecoveryTarget = nil
        self.isReplacementPlanReady = false
    }

    public func buildPlan(
        device: DeviceInfo?,
        preparedEpisodes: [PreparedEpisode],
        subscriptions: [PodcastSubscription],
        manualDeleteTargets: Set<URL> = [],
        replacementTargets: Set<URL> = [],
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
            planningErrorTitle = "Cannot Start Sync"
            lastErrorMessage = "Select a compatible device before building a sync plan."
            incompleteCopyRecoveryTarget = nil
            isReplacementPlanReady = false
            return
        }

        isPlanning = true
        plan = nil
        planningErrorTitle = nil
        lastErrorMessage = nil
        incompleteCopyRecoveryTarget = nil
        isReplacementPlanReady = false

        do {
            let planner = planner
            let task = Task.detached(priority: .userInitiated) {
                try planner.makePlan(
                    device: device,
                    preparedEpisodes: preparedEpisodes,
                    subscriptions: subscriptions,
                    manualDeleteTargets: manualDeleteTargets,
                    replacementTargets: replacementTargets,
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
            planningErrorTitle = nil
            lastErrorMessage = nil
            incompleteCopyRecoveryTarget = nil
            isReplacementPlanReady = !replacementTargets.isEmpty
            planningTask = nil
        } catch is CancellationError {
            return
        } catch {
            guard latestPlanningID == planningID else { return }
            plan = nil
            planningErrorTitle = replacementTargets.isEmpty
                ? "Cannot Start Sync"
                : "Could Not Prepare Replacement"
            lastErrorMessage = Self.userFacingMessage(for: error)
            if let capacityError = error as? SyncCapacityError,
               case .incompleteExistingCopy(let targetURL, _, _) = capacityError {
                incompleteCopyRecoveryTarget = targetURL.standardizedFileURL
            } else {
                incompleteCopyRecoveryTarget = nil
            }
            isReplacementPlanReady = false
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
        planningErrorTitle = nil
        lastErrorMessage = nil
        incompleteCopyRecoveryTarget = nil
        isReplacementPlanReady = false
    }

    public func cancelPlanning() {
        planningTask?.cancel()
        planningTask = nil
        latestPlanningID = nil
        isPlanning = false
        planningErrorTitle = nil
        lastErrorMessage = nil
        incompleteCopyRecoveryTarget = nil
        isReplacementPlanReady = false
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
