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

    /// Device files that remain absent after this plan completes.
    /// A target deleted and then copied back in the same plan is a replacement,
    /// not an episode removal.
    public var removalTargetURLs: [URL] {
        let copyDestinations = Set(actions.compactMap { action -> URL? in
            guard case .copyToDevice(_, let destinationURL, _) = action else { return nil }
            return destinationURL.standardizedFileURL
        })

        return actions.compactMap { action -> URL? in
            guard case .deleteFromDevice(let targetURL, _) = action else { return nil }
            let standardizedTargetURL = targetURL.standardizedFileURL
            return copyDestinations.contains(standardizedTargetURL) ? nil : standardizedTargetURL
        }
    }
}
