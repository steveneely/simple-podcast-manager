import Foundation

public struct SyncPlan: Equatable, Sendable {
    public var device: DeviceInfo
    public var actions: [SyncAction]
    public var cleanupCandidates: [DeviceCleanupCandidate]

    public init(
        device: DeviceInfo,
        actions: [SyncAction] = [],
        cleanupCandidates: [DeviceCleanupCandidate] = []
    ) {
        self.device = device
        self.actions = actions
        self.cleanupCandidates = cleanupCandidates
    }
}
