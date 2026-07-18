import Foundation

public struct SyncPlanner: Sendable {
    private let deviceLibrary: any DeviceLibraryInspecting
    private let storageInspector: any SyncStorageInspecting
    private let safetyValidator: SafetyValidator
    private let managedDirectoryResolver: ManagedDirectoryResolver

    public init(
        deviceLibrary: any DeviceLibraryInspecting = FileSystemDeviceLibrary(),
        storageInspector: any SyncStorageInspecting = LocalSyncStorageInspector(),
        safetyValidator: SafetyValidator = SafetyValidator()
    ) {
        self.deviceLibrary = deviceLibrary
        self.storageInspector = storageInspector
        self.safetyValidator = safetyValidator
        self.managedDirectoryResolver = ManagedDirectoryResolver(deviceLibrary: deviceLibrary)
    }

    public func makePlan(
        device: DeviceInfo,
        preparedEpisodes: [PreparedEpisode],
        subscriptions: [FeedSubscription],
        manualDeleteTargets: Set<URL> = [],
        ejectAfterSync: Bool
    ) throws -> SyncPlan {
        try safetyValidator.validateDevice(device)

        var actions: [SyncAction] = []
        var plannedDeletionTargets: Set<URL> = []

        let preparedBySubscription = Dictionary(grouping: preparedEpisodes.compactMap { preparedEpisode -> (UUID, PreparedEpisode)? in
            guard let subscriptionID = preparedEpisode.episode.subscriptionID else { return nil }
            return (subscriptionID, preparedEpisode)
        }, by: { $0.0 })
        let manualDeleteTargets = Set(manualDeleteTargets.map(\.standardizedFileURL))
        let deviceSnapshot = try DeviceLibrarySnapshot(
            deviceLibrary: deviceLibrary,
            directoryURL: device.podcastDirectoryURL
        )

        for subscription in subscriptions {
            let preparedEpisodes = preparedBySubscription[subscription.id]?.map(\.1) ?? []
            let managedDirectory = managedDirectoryResolver.managedDirectoryURL(
                for: subscription,
                on: device,
                candidateDirectories: deviceSnapshot.directories
            )
            let existingFiles = deviceSnapshot.directFiles(in: managedDirectory)
                .filter { EpisodeFileName.isManagedEpisodeFile($0, for: subscription) }

            for preparedEpisode in preparedEpisodes {
                let destinationURL = managedDirectory.appendingPathComponent(preparedEpisode.preparedFileURL.lastPathComponent, isDirectory: false)

                if let existingFileURL = existingFiles.first(where: {
                    $0.lastPathComponent == destinationURL.lastPathComponent
                }) {
                    try verifyExistingCopy(existingFileURL, matches: preparedEpisode.preparedFileURL)
                    actions.append(.skip(reason: "Already on device: \(preparedEpisode.episode.title)"))
                } else {
                    try safetyValidator.validateWriteTarget(destinationURL, on: device)
                    actions.append(.copyToDevice(sourceURL: preparedEpisode.preparedFileURL, destinationURL: destinationURL))
                }
            }

            let manuallySelectedFiles = existingFiles
                .filter { manualDeleteTargets.contains($0.standardizedFileURL) }
                .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            for fileURL in manuallySelectedFiles where !plannedDeletionTargets.contains(fileURL.standardizedFileURL) {
                try safetyValidator.validateDeleteTarget(fileURL, on: device)
                actions.append(.deleteFromDevice(targetURL: fileURL))
                plannedDeletionTargets.insert(fileURL.standardizedFileURL)
            }
        }

        if ejectAfterSync {
            actions.append(.ejectDevice(deviceRootURL: device.rootURL))
        }

        let capacityAwarePlan = try orderActionsToFit(actions, on: device)
        return SyncPlan(
            device: device,
            actions: capacityAwarePlan.actions,
            warnings: capacityAwarePlan.movedDeletions
                ? ["Some selected deletions will run before copying so the sync has enough space."]
                : []
        )
    }

    private func verifyExistingCopy(_ deviceURL: URL, matches preparedURL: URL) throws {
        let expectedSize = try storageInspector.fileSize(at: preparedURL)
        let actualSize = try storageInspector.fileSize(at: deviceURL)
        guard expectedSize == actualSize else {
            throw SyncCapacityError.incompleteExistingCopy(
                fileName: deviceURL.lastPathComponent,
                expectedBytes: expectedSize,
                actualBytes: actualSize
            )
        }
    }

    private func orderActionsToFit(
        _ actions: [SyncAction],
        on device: DeviceInfo
    ) throws -> (actions: [SyncAction], movedDeletions: Bool) {
        guard actions.contains(where: { if case .copyToDevice = $0 { true } else { false } }) else {
            return (actions, false)
        }

        let initialCapacity = try storageInspector.availableCapacity(on: device)
        var availableCapacity = initialCapacity
        var remainingActions = actions
        var orderedActions: [SyncAction] = []
        var movedDeletions = false

        while !remainingActions.isEmpty {
            let action = remainingActions.removeFirst()

            switch action {
            case .copyToDevice(let sourceURL, _):
                let requiredCapacity = try storageInspector.fileSize(at: sourceURL)

                // Pull only deletions the user already approved forward, and only
                // when the next copy would otherwise not fit.
                while requiredCapacity > availableCapacity,
                      let deleteIndex = remainingActions.firstIndex(where: {
                          if case .deleteFromDevice = $0 { true } else { false }
                      }) {
                    let deleteAction = remainingActions.remove(at: deleteIndex)
                    guard case .deleteFromDevice(let targetURL) = deleteAction else { continue }
                    availableCapacity += try storageInspector.fileSize(at: targetURL)
                    orderedActions.append(deleteAction)
                    movedDeletions = true
                }

                guard requiredCapacity <= availableCapacity else {
                    throw SyncCapacityError.insufficientCapacity(
                        requiredBytes: requiredCapacity,
                        availableBytes: availableCapacity
                    )
                }
                availableCapacity -= requiredCapacity
                orderedActions.append(action)

            case .deleteFromDevice(let targetURL):
                availableCapacity += try storageInspector.fileSize(at: targetURL)
                orderedActions.append(action)

            case .skip, .ejectDevice:
                orderedActions.append(action)
            }
        }

        return (orderedActions, movedDeletions)
    }
}
