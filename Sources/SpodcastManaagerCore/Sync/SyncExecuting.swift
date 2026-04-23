import Foundation

public protocol SyncExecuting: Sendable {
    func execute(
        plan: SyncPlan,
        progress: (@Sendable (SyncExecutionProgress) -> Void)?
    ) throws -> SyncResult
}
