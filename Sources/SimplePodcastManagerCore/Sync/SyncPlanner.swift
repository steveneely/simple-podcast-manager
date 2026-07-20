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
        self.managedDirectoryResolver = ManagedDirectoryResolver()
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
                    let fileSizeBytes = try storageInspector.fileSize(at: preparedEpisode.preparedFileURL)
                    actions.append(.copyToDevice(
                        sourceURL: preparedEpisode.preparedFileURL,
                        destinationURL: destinationURL,
                        fileSizeBytes: fileSizeBytes
                    ))
                }
            }

            let manuallySelectedFiles = existingFiles
                .filter { manualDeleteTargets.contains($0.standardizedFileURL) }
                .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            for fileURL in manuallySelectedFiles where !plannedDeletionTargets.contains(fileURL.standardizedFileURL) {
                try safetyValidator.validateDeleteTarget(fileURL, on: device)
                let fileSizeBytes = try storageInspector.fileSize(at: fileURL)
                actions.append(.deleteFromDevice(targetURL: fileURL, fileSizeBytes: fileSizeBytes))
                plannedDeletionTargets.insert(fileURL.standardizedFileURL)
            }
        }

        if ejectAfterSync {
            actions.append(.ejectDevice(deviceRootURL: device.rootURL))
        }

        try storageInspector.ensurePlanFits(actions, on: device)
        let orderedActions = orderDeletionsBeforeCopies(actions)
        return SyncPlan(
            device: device,
            actions: orderedActions
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

    private func orderDeletionsBeforeCopies(_ actions: [SyncAction]) -> [SyncAction] {
        let deletionActions = actions.filter { if case .deleteFromDevice = $0 { true } else { false } }
        let remainingActions = actions.filter { if case .deleteFromDevice = $0 { false } else { true } }
        return deletionActions + remainingActions
    }
}
