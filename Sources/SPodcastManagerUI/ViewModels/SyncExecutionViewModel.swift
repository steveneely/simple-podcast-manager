import Foundation
import Observation
import SPodcastManagerCore

@MainActor
@Observable
public final class SyncExecutionViewModel {
    public private(set) var isSyncing: Bool
    public private(set) var progress: SyncExecutionProgress?
    public private(set) var lastResult: SyncResult?
    public private(set) var lastErrorMessage: String?
    public private(set) var lastPlan: SyncPlan?

    private let planner: SyncPlanner
    private let executor: any SyncExecuting

    public init(
        planner: SyncPlanner = SyncPlanner(),
        executor: any SyncExecuting = SyncExecutor()
    ) {
        self.planner = planner
        self.executor = executor
        self.isSyncing = false
        self.progress = nil
        self.lastResult = nil
        self.lastErrorMessage = nil
        self.lastPlan = nil
    }

    public func sync(
        device: DeviceInfo?,
        preparedEpisodes: [PreparedEpisode],
        subscriptions: [FeedSubscription],
        manualDeleteTargets: Set<URL> = [],
        ejectAfterSync: Bool,
        isDryRun: Bool
    ) async {
        guard let device else {
            lastErrorMessage = "Select a compatible device before syncing."
            return
        }

        do {
            let plan = try planner.makePlan(
                device: device,
                preparedEpisodes: preparedEpisodes,
                subscriptions: subscriptions,
                manualDeleteTargets: manualDeleteTargets,
                ejectAfterSync: ejectAfterSync,
                isDryRun: isDryRun
            )
            lastPlan = plan
            isSyncing = true
            progress = SyncExecutionProgress(totalCount: plan.actions.count, completedCount: 0)
            defer {
                isSyncing = false
                progress = nil
            }
            let result: SyncResult
            if isDryRun {
                result = Self.previewResult(for: plan)
            } else {
                let executor = self.executor
                result = try await Task.detached(priority: .userInitiated) { [weak self] in
                    try executor.execute(plan: plan) { progress in
                        Task { @MainActor in
                            self?.progress = progress
                        }
                    }
                }.value
            }
            lastResult = result
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private static func previewResult(for plan: SyncPlan) -> SyncResult {
        var copiedCount = 0
        var deletedCount = 0
        var skippedCount = 0

        for action in plan.actions {
            switch action {
            case .copyToDevice:
                copiedCount += 1
            case .deleteFromDevice:
                deletedCount += 1
            case .skip:
                skippedCount += 1
            case .clearDeviceTrash, .ejectDevice:
                break
            }
        }

        return SyncResult(
            startedAt: Date(),
            finishedAt: Date(),
            isDryRun: true,
            copiedCount: copiedCount,
            deletedCount: deletedCount,
            skippedCount: skippedCount,
            ejected: false,
            warnings: ["Dry run only. No device files were modified."]
        )
    }
}
