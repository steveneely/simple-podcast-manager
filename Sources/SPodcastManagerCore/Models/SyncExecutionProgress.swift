import Foundation

public struct SyncExecutionProgress: Equatable, Sendable {
    public var totalCount: Int
    public var completedCount: Int
    public var currentActionDescription: String?

    public init(
        totalCount: Int,
        completedCount: Int,
        currentActionDescription: String? = nil
    ) {
        self.totalCount = totalCount
        self.completedCount = completedCount
        self.currentActionDescription = currentActionDescription
    }

    public var fractionCompleted: Double {
        guard totalCount > 0 else { return 1 }
        return Double(completedCount) / Double(totalCount)
    }
}
