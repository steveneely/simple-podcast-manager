import Foundation

public protocol SyncExecuting: Sendable {
    func execute(plan: SyncPlan) throws -> SyncResult
}
