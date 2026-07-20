import Foundation

public struct SyncPlan: Equatable, Sendable {
    public var device: DeviceInfo
    public var actions: [SyncAction]

    public init(
        device: DeviceInfo,
        actions: [SyncAction] = []
    ) {
        self.device = device
        self.actions = actions
    }
}
