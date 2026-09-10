import Foundation

public struct SyncPlan: Equatable, Sendable {
    public var device: DeviceInfo
    public var actions: [SyncAction]
    public var cleanupCandidates: [DeviceCleanupCandidate]
    /// Explicit ownership inventory for sidecar cleanup, including episodes not copied this sync.
    public var existingManagedEpisodeURLs: [URL]

    public init(
        device: DeviceInfo,
        actions: [SyncAction] = [],
        cleanupCandidates: [DeviceCleanupCandidate] = [],
        existingManagedEpisodeURLs: [URL] = []
    ) {
        self.device = device
        self.actions = actions
        self.cleanupCandidates = cleanupCandidates
        self.existingManagedEpisodeURLs = existingManagedEpisodeURLs
    }

    public var hasWork: Bool {
        !metadataCleanupTargets.isEmpty || actions.contains { action in
            switch action {
            case .copyToDevice, .deleteFromDevice, .ejectDevice: true
            case .skip: false
            }
        }
    }

    public var metadataCleanupTargets: [URL] {
        let copyTargets = actions.compactMap { action -> URL? in
            guard case .copyToDevice(_, let destination, _) = action else { return nil }
            return destination
        }
        return Set((existingManagedEpisodeURLs + copyTargets).map(\.standardizedFileURL))
            .subtracting(removalTargetURLs)
            .sorted { $0.path < $1.path }
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
