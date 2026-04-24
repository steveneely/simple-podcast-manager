import Foundation

public struct SyncPlan: Equatable, Sendable {
    public var device: DeviceInfo
    public var isDryRun: Bool
    public var actions: [SyncAction]

    public init(
        device: DeviceInfo,
        isDryRun: Bool,
        actions: [SyncAction] = []
    ) {
        self.device = device
        self.isDryRun = isDryRun
        self.actions = actions
    }
}
