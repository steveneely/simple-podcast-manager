import Foundation

public struct SyncResult: Equatable, Sendable {
    public var startedAt: Date
    public var finishedAt: Date?
    public var copiedCount: Int
    public var copiedBytes: Int64
    public var deletedCount: Int
    public var deletedBytes: Int64
    public var skippedCount: Int
    public var ejected: Bool

    public init(
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        copiedCount: Int = 0,
        copiedBytes: Int64 = 0,
        deletedCount: Int = 0,
        deletedBytes: Int64 = 0,
        skippedCount: Int = 0,
        ejected: Bool = false
    ) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.copiedCount = copiedCount
        self.copiedBytes = copiedBytes
        self.deletedCount = deletedCount
        self.deletedBytes = deletedBytes
        self.skippedCount = skippedCount
        self.ejected = ejected
    }
}
