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
        cleanupPolicy: DeviceCleanupPolicy = DeviceCleanupPolicy(),
        excludedCleanupTargets: Set<URL> = [],
        currentDate: Date = Date(),
        ejectAfterSync: Bool
    ) throws -> SyncPlan {
        try safetyValidator.validateDevice(device)

        let cleanupCutoffDate = try cleanupCutoffDate(
            for: cleanupPolicy,
            currentDate: currentDate
        )

        var actions: [SyncAction] = []
        var cleanupCandidates: [DeviceCleanupCandidate] = []
        var plannedDeletionTargets: Set<URL> = []

        let preparedBySubscription = Dictionary(grouping: preparedEpisodes.compactMap { preparedEpisode -> (UUID, PreparedEpisode)? in
            guard let subscriptionID = preparedEpisode.episode.subscriptionID else { return nil }
            return (subscriptionID, preparedEpisode)
        }, by: { $0.0 })
        let manualDeleteTargets = Set(manualDeleteTargets.map(\.standardizedFileURL))
        let excludedCleanupTargets = Set(excludedCleanupTargets.map(\.standardizedFileURL))
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

            var cleanupCandidateSizesByURL: [URL: Int64] = [:]
            if let cleanupCutoffDate {
                for fileURL in existingFiles {
                    guard let metadata = EpisodeFileName.parsedMetadata(from: fileURL),
                          let publicationDate = metadata.publicationDate,
                          publicationDate < cleanupCutoffDate else {
                        continue
                    }

                    try safetyValidator.validateDeleteTarget(fileURL, on: device)
                    let standardizedURL = fileURL.standardizedFileURL
                    let fileSizeBytes = try storageInspector.fileSize(at: fileURL)
                    cleanupCandidateSizesByURL[standardizedURL] = fileSizeBytes
                    cleanupCandidates.append(
                        DeviceCleanupCandidate(
                            targetURL: fileURL,
                            subscriptionID: subscription.id,
                            podcastTitle: subscription.title,
                            episodeTitle: metadata.episodeTitle,
                            publicationDate: publicationDate,
                            fileSizeBytes: fileSizeBytes
                        )
                    )
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

    private func cleanupCutoffDate(
        for policy: DeviceCleanupPolicy,
        currentDate: Date
    ) throws -> Date? {
        guard policy.isEnabled else { return nil }
        guard DeviceCleanupPolicy.allowedEpisodeAgeDays.contains(policy.episodeAgeDays) else {
            throw DeviceCleanupPolicyError.invalidEpisodeAgeDays(policy.episodeAgeDays)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone(identifier: "GMT")!
        let currentDay = calendar.startOfDay(for: currentDate)
        return calendar.date(byAdding: .day, value: -policy.episodeAgeDays, to: currentDay)
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
