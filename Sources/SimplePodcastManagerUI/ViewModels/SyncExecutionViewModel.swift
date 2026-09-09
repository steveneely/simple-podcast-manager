import Foundation
import Observation
import SimplePodcastManagerCore

@MainActor
@Observable
public final class SyncExecutionViewModel {
    public private(set) var isSyncing: Bool
    public private(set) var progress: SyncExecutionProgress?
    public private(set) var lastResult: SyncResult?
    public private(set) var lastErrorMessage: String?
    public private(set) var lastPlan: SyncPlan?

    private var activeSyncID: UUID?
    private let executor: any SyncExecuting

    public init(executor: any SyncExecuting = SyncExecutor()) {
        self.executor = executor
        self.isSyncing = false
        self.progress = nil
        self.lastResult = nil
        self.lastErrorMessage = nil
        self.lastPlan = nil
    }

    public func sync(plan: SyncPlan?) async {
        guard !isSyncing else { return }
        clearLastResult()
        guard let plan else {
            lastErrorMessage = "Build and review a sync plan before syncing."
            return
        }

        do {
            let syncID = UUID()
            activeSyncID = syncID
            lastPlan = plan
            isSyncing = true
            progress = SyncExecutionProgress(totalCount: plan.actions.count, completedCount: 0)
            defer {
                activeSyncID = nil
                isSyncing = false
                progress = nil
            }
            let executor = self.executor
            let result = try await Task.detached(priority: .userInitiated) { [weak self] in
                try executor.execute(plan: plan) { progress in
                    Task { @MainActor in
                        guard self?.activeSyncID == syncID else { return }
                        self?.progress = progress
                    }
                }
            }.value
            lastResult = result
            lastErrorMessage = nil
        } catch let failure as SyncExecutionFailure {
            lastResult = failure.result
            lastErrorMessage = failure.localizedDescription
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func clearLastResult() {
        lastResult = nil
        lastErrorMessage = nil
        lastPlan = nil
    }
}
