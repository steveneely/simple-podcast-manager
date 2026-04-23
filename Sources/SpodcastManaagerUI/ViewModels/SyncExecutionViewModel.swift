import Foundation
import Observation
import SpodcastManaagerCore

@MainActor
@Observable
public final class SyncExecutionViewModel {
    public private(set) var isSyncing: Bool
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
        self.lastResult = nil
        self.lastErrorMessage = nil
        self.lastPlan = nil
    }

    public func sync(
        device: DeviceInfo?,
        preparedEpisodes: [PreparedEpisode],
        subscriptions: [FeedSubscription],
        ejectAfterSync: Bool,
        isDryRun: Bool
    ) async {
        guard let device else {
            lastErrorMessage = "Select a compatible device before syncing."
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let plan = try planner.makePlan(
                device: device,
                preparedEpisodes: preparedEpisodes,
                subscriptions: subscriptions,
                ejectAfterSync: ejectAfterSync,
                isDryRun: isDryRun
            )
            lastPlan = plan
            let result = if isDryRun {
                Self.previewResult(for: plan)
            } else {
                try executor.execute(plan: plan)
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
