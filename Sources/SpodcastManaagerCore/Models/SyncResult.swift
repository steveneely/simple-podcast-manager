import Foundation

public struct SyncResult: Equatable, Sendable {
    public var startedAt: Date
    public var finishedAt: Date?
    public var isDryRun: Bool
    public var copiedCount: Int
    public var deletedCount: Int
    public var skippedCount: Int
    public var ejected: Bool
    public var warnings: [String]

    public init(
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        isDryRun: Bool,
        copiedCount: Int = 0,
        deletedCount: Int = 0,
        skippedCount: Int = 0,
        ejected: Bool = false,
        warnings: [String] = []
    ) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.isDryRun = isDryRun
        self.copiedCount = copiedCount
        self.deletedCount = deletedCount
        self.skippedCount = skippedCount
        self.ejected = ejected
        self.warnings = warnings
    }
}
