import Foundation

public struct SyncPlanner: Sendable {
    private let inventoryBuilder: ManagedDeviceLibraryInventoryBuilder
    private let storageInspector: any SyncStorageInspecting
    private let safetyValidator: SafetyValidator

    public init(
        deviceLibrary: any DeviceLibraryInspecting = FileSystemDeviceLibrary(),
        storageInspector: any SyncStorageInspecting = LocalSyncStorageInspector(),
        safetyValidator: SafetyValidator = SafetyValidator()
    ) {
        self.inventoryBuilder = ManagedDeviceLibraryInventoryBuilder(deviceLibrary: deviceLibrary)
        self.storageInspector = storageInspector
        self.safetyValidator = safetyValidator
    }

    public func makePlan(
        device: DeviceInfo,
        preparedEpisodes: [PreparedEpisode],
        subscriptions: [FeedSubscription],
        manualDeleteTargets: Set<URL> = [],
        cleanupPolicy: DeviceCleanupPolicy = DeviceCleanupPolicy(),
        excludedCleanupTargets: Set<URL> = [],
        managedInventory: ManagedDeviceLibraryInventory? = nil,
        ejectAfterSync: Bool
    ) throws -> SyncPlan {
        try Task.checkCancellation()
        try safetyValidator.validateDevice(device)

        let maximumEpisodesPerShow = try validatedMaximumEpisodesPerShow(for: cleanupPolicy)

        var actions: [SyncAction] = []
        var cleanupCandidates: [DeviceCleanupCandidate] = []
        var plannedDeletionTargets: Set<URL> = []

        let preparedBySubscription = Dictionary(grouping: preparedEpisodes.compactMap { preparedEpisode -> (UUID, PreparedEpisode)? in
            guard let subscriptionID = preparedEpisode.episode.subscriptionID else { return nil }
            return (subscriptionID, preparedEpisode)
        }, by: { $0.0 })
        let manualDeleteTargets = Set(manualDeleteTargets.map(\.standardizedFileURL))
        let excludedCleanupTargets = Set(excludedCleanupTargets.map(\.standardizedFileURL))
        let deviceInventory: ManagedDeviceLibraryInventory
        if let managedInventory,
           managedInventory.canBeUsed(on: device, subscriptions: subscriptions) {
            deviceInventory = managedInventory
        } else {
            deviceInventory = try inventoryBuilder.makeInventory(
                device: device,
                subscriptions: subscriptions
            )
        }

        for subscription in subscriptions {
            try Task.checkCancellation()
            let preparedEpisodes = preparedBySubscription[subscription.id]?.map(\.1) ?? []
            let managedDirectory = deviceInventory.managedDirectoryURL(for: subscription, on: device)
            let existingFiles = deviceInventory.files(for: subscription).filter {
                $0.deletingLastPathComponent().standardizedFileURL == managedDirectory.standardizedFileURL
                    && EpisodeFileName.isManagedEpisodeFile($0, for: subscription)
            }

            var cleanupCandidateSizesByURL: [URL: Int64] = [:]
            if let maximumEpisodesPerShow {
                let subscriptionCleanupCandidates = try makeCleanupCandidates(
                    existingFiles: existingFiles,
                    preparedEpisodes: preparedEpisodes,
                    managedDirectory: managedDirectory,
                    subscription: subscription,
                    manualDeleteTargets: manualDeleteTargets,
                    maximumEpisodesPerShow: maximumEpisodesPerShow,
                    device: device
                )
                for candidate in subscriptionCleanupCandidates {
                    cleanupCandidateSizesByURL[candidate.targetURL.standardizedFileURL] = candidate.fileSizeBytes
                    cleanupCandidates.append(candidate)
                }
            }

            let selectedFiles = existingFiles
                .filter { fileURL in
                    let standardizedURL = fileURL.standardizedFileURL
                    let isManuallySelected = manualDeleteTargets.contains(standardizedURL)
                    let isSelectedCleanupCandidate = cleanupCandidateSizesByURL[standardizedURL] != nil
                        && !excludedCleanupTargets.contains(standardizedURL)
                    return isManuallySelected || isSelectedCleanupCandidate
                }
                .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            let selectedFileURLs = Set(selectedFiles.map(\.standardizedFileURL))

            for preparedEpisode in preparedEpisodes {
                try Task.checkCancellation()
                let destinationURL = managedDirectory.appendingPathComponent(preparedEpisode.preparedFileURL.lastPathComponent, isDirectory: false)

                if let existingFileURL = existingFiles.first(where: {
                    $0.lastPathComponent == destinationURL.lastPathComponent
                }) {
                    if selectedFileURLs.contains(existingFileURL.standardizedFileURL) {
                        actions.append(.skip(reason: "Selected for removal from device: \(preparedEpisode.episode.title)"))
                    } else {
                        try verifyExistingCopy(existingFileURL, matches: preparedEpisode.preparedFileURL)
                        actions.append(.skip(reason: "Already on device: \(preparedEpisode.episode.title)"))
                    }
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

            for fileURL in selectedFiles where !plannedDeletionTargets.contains(fileURL.standardizedFileURL) {
                try Task.checkCancellation()
                try safetyValidator.validateDeleteTarget(fileURL, on: device)
                let fileSizeBytes: Int64
                if let cleanupCandidateSize = cleanupCandidateSizesByURL[fileURL.standardizedFileURL] {
                    fileSizeBytes = cleanupCandidateSize
                } else {
                    fileSizeBytes = try storageInspector.fileSize(at: fileURL)
                }
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
            actions: orderedActions,
            cleanupCandidates: cleanupCandidates.sorted(by: cleanupCandidateSort)
        )
    }

    private func validatedMaximumEpisodesPerShow(
        for policy: DeviceCleanupPolicy
    ) throws -> Int? {
        guard let maximumEpisodesPerShow = policy.maximumEpisodesPerShow else { return nil }
        guard DeviceCleanupPolicy.allowedMaximumEpisodesPerShow.contains(maximumEpisodesPerShow) else {
            throw DeviceCleanupPolicyError.invalidMaximumEpisodesPerShow(maximumEpisodesPerShow)
        }
        return maximumEpisodesPerShow
    }

    private func makeCleanupCandidates(
        existingFiles: [URL],
        preparedEpisodes: [PreparedEpisode],
        managedDirectory: URL,
        subscription: FeedSubscription,
        manualDeleteTargets: Set<URL>,
        maximumEpisodesPerShow: Int,
        device: DeviceInfo
    ) throws -> [DeviceCleanupCandidate] {
        var retentionEntriesByURL: [URL: CleanupRetentionEntry] = [:]

        for fileURL in existingFiles {
            let standardizedURL = fileURL.standardizedFileURL
            guard !manualDeleteTargets.contains(standardizedURL),
                  let metadata = EpisodeFileName.parsedMetadata(from: fileURL),
                  let publicationDate = metadata.publicationDate else {
                continue
            }
            retentionEntriesByURL[standardizedURL] = CleanupRetentionEntry(
                targetURL: fileURL,
                episodeTitle: metadata.episodeTitle,
                publicationDate: publicationDate,
                existsOnDevice: true
            )
        }

        for preparedEpisode in preparedEpisodes {
            let destinationURL = managedDirectory.appendingPathComponent(
                preparedEpisode.preparedFileURL.lastPathComponent,
                isDirectory: false
            )
            let standardizedURL = destinationURL.standardizedFileURL
            guard !manualDeleteTargets.contains(standardizedURL),
                  retentionEntriesByURL[standardizedURL] == nil,
                  let publicationDate = EpisodeFileName.parsedMetadata(from: destinationURL)?.publicationDate else {
                continue
            }
            retentionEntriesByURL[standardizedURL] = CleanupRetentionEntry(
                targetURL: destinationURL,
                episodeTitle: preparedEpisode.episode.title,
                publicationDate: publicationDate,
                existsOnDevice: false
            )
        }

        let orderedEntries = retentionEntriesByURL.values.sorted(by: CleanupRetentionEntry.isNewer)
        guard orderedEntries.count > maximumEpisodesPerShow else { return [] }
        let oldestRetainedDate = orderedEntries[maximumEpisodesPerShow - 1].publicationDate
        let excessExistingEpisodes = orderedEntries
            .dropFirst(maximumEpisodesPerShow)
            .filter { entry in
                entry.existsOnDevice && entry.publicationDate < oldestRetainedDate
            }

        return try excessExistingEpisodes.map { entry in
            try safetyValidator.validateDeleteTarget(entry.targetURL, on: device)
            return DeviceCleanupCandidate(
                targetURL: entry.targetURL,
                subscriptionID: subscription.id,
                podcastTitle: subscription.title,
                episodeTitle: entry.episodeTitle,
                publicationDate: entry.publicationDate,
                fileSizeBytes: try storageInspector.fileSize(at: entry.targetURL)
            )
        }
    }

    private struct CleanupRetentionEntry {
        var targetURL: URL
        var episodeTitle: String
        var publicationDate: Date
        var existsOnDevice: Bool

        static func isNewer(_ lhs: Self, _ rhs: Self) -> Bool {
            if lhs.publicationDate != rhs.publicationDate {
                return lhs.publicationDate > rhs.publicationDate
            }
            return lhs.targetURL.lastPathComponent.localizedCaseInsensitiveCompare(
                rhs.targetURL.lastPathComponent
            ) == .orderedDescending
        }
    }

    private func cleanupCandidateSort(
        _ lhs: DeviceCleanupCandidate,
        _ rhs: DeviceCleanupCandidate
    ) -> Bool {
        if lhs.publicationDate != rhs.publicationDate {
            return lhs.publicationDate < rhs.publicationDate
        }
        if lhs.podcastTitle != rhs.podcastTitle {
            return lhs.podcastTitle.localizedCaseInsensitiveCompare(rhs.podcastTitle) == .orderedAscending
        }
        return lhs.episodeTitle.localizedCaseInsensitiveCompare(rhs.episodeTitle) == .orderedAscending
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
