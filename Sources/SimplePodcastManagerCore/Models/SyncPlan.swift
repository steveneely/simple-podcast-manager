import Foundation

public struct SyncPlan: Equatable, Sendable {
    public var device: DeviceInfo
    public var actions: [SyncAction]
    public var warnings: [String]

    public init(
        device: DeviceInfo,
        actions: [SyncAction] = [],
        warnings: [String] = []
    ) {
        self.device = device
        self.actions = actions
        self.warnings = warnings
    }
}
