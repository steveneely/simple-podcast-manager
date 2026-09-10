import Foundation

public struct SyncPlanner: Sendable {
    private let inventoryBuilder: ManagedDeviceLibraryInventoryBuilder
    private let deviceLibrary: any DeviceLibraryInspecting
    private let storageInspector: any SyncStorageInspecting
    private let safetyValidator: SafetyValidator

    public init(
        deviceLibrary: any DeviceLibraryInspecting = FileSystemDeviceLibrary(),
        storageInspector: any SyncStorageInspecting = LocalSyncStorageInspector(),
        safetyValidator: SafetyValidator = SafetyValidator()
    ) {
        self.deviceLibrary = deviceLibrary
        self.inventoryBuilder = ManagedDeviceLibraryInventoryBuilder(deviceLibrary: deviceLibrary)
        self.storageInspector = storageInspector
        self.safetyValidator = safetyValidator
    }

    public func makePlan(
        device: DeviceInfo,
        preparedEpisodes: [PreparedEpisode],
        subscriptions: [PodcastSubscription],
        manualDeleteTargets: Set<URL> = [],
        replacementTargets: Set<URL> = [],
        cleanupPolicy: DeviceCleanupPolicy = DeviceCleanupPolicy(),
        excludedCleanupTargets: Set<URL> = [],
        selectedPlaylistProtectedDeletionTargets: Set<URL> = [],
        managedInventory: ManagedDeviceLibraryInventory? = nil,
        podcastPlaylistLibrary: PodcastPlaylistLibrary = PodcastPlaylistLibrary(),
        ejectAfterSync: Bool
    ) throws -> SyncPlan {
        try Task.checkCancellation()
        try safetyValidator.validateDevice(device)

        let maximumEpisodesPerPodcast = try validatedMaximumEpisodesPerPodcast(for: cleanupPolicy)

        var actions: [SyncAction] = []
        var cleanupCandidates: [DeviceCleanupCandidate] = []
        var playlistProtectedCleanupCandidates: [PlaylistProtectedCleanupCandidate] = []
        var plannedDeletionTargets: Set<URL> = []

        let preparedBySubscription = Dictionary(grouping: preparedEpisodes.compactMap { preparedEpisode -> (UUID, PreparedEpisode)? in
            guard let subscriptionID = preparedEpisode.episode.subscriptionID else { return nil }
            return (subscriptionID, preparedEpisode)
        }, by: { $0.0 })
        let manualDeleteTargets = Set(manualDeleteTargets.map(\.standardizedFileURL))
        let replacementTargets = Set(replacementTargets.map(\.standardizedFileURL))
        let selectedPlaylistProtectedDeletionTargets = Set(
            selectedPlaylistProtectedDeletionTargets.map(\.standardizedFileURL)
        )
        let explicitDeleteTargets = manualDeleteTargets
            .union(replacementTargets)
            .union(selectedPlaylistProtectedDeletionTargets)
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
            let conservativeExistingFilesByEpisodeID = EpisodeFileName.uniqueConservativeMatches(
                in: existingFiles,
                to: preparedEpisodes.map(\.episode),
                subscription: subscription
            )

            var cleanupCandidateSizesByURL: [URL: Int64] = [:]
            if let maximumEpisodesPerPodcast {
                let protectedEntries = protectedPlaylistEntries(
                    for: subscription,
                    podcastPlaylistLibrary: podcastPlaylistLibrary
                )
                let protectedFilesByURL = protectedDeviceFilesByURL(
                    existingFiles: existingFiles,
                    protectedEntries: protectedEntries,
                    subscription: subscription
                )
                let protectedEpisodeIDs = Set(protectedEntries.map(\.entry.id))
                let cleanupReview = try makeCleanupReview(
                    existingFiles: existingFiles,
                    preparedEpisodes: preparedEpisodes,
                    managedDirectory: managedDirectory,
                    subscription: subscription,
                    manualDeleteTargets: explicitDeleteTargets,
                    replacementTargets: replacementTargets,
                    protectedFilesByURL: protectedFilesByURL,
                    protectedEpisodeIDs: protectedEpisodeIDs,
                    maximumEpisodesPerPodcast: maximumEpisodesPerPodcast,
                    device: device
                )
                for candidate in cleanupReview.cleanupCandidates {
                    cleanupCandidateSizesByURL[candidate.targetURL.standardizedFileURL] = candidate.fileSizeBytes
                    cleanupCandidates.append(candidate)
                }
                playlistProtectedCleanupCandidates.append(
                    contentsOf: cleanupReview.playlistProtectedCandidates
                )
            }

            let selectedFiles = existingFiles
                .filter { fileURL in
                    let standardizedURL = fileURL.standardizedFileURL
                    let isExplicitlySelected = explicitDeleteTargets.contains(standardizedURL)
                    let isSelectedCleanupCandidate = cleanupCandidateSizesByURL[standardizedURL] != nil
                        && !excludedCleanupTargets.contains(standardizedURL)
                    return isExplicitlySelected || isSelectedCleanupCandidate
                }
                .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            let selectedFileURLs = Set(selectedFiles.map(\.standardizedFileURL))

            for preparedEpisode in preparedEpisodes {
                try Task.checkCancellation()
                let destinationURL = managedDirectory.appendingPathComponent(preparedEpisode.preparedFileURL.lastPathComponent, isDirectory: false)

                if let existingFileURL = existingFiles.first(where: {
                    $0.lastPathComponent == destinationURL.lastPathComponent
                }) {
                    let standardizedExistingURL = existingFileURL.standardizedFileURL
                    if replacementTargets.contains(standardizedExistingURL) {
                        try safetyValidator.validateWriteTarget(destinationURL, on: device)
                        let fileSizeBytes = try storageInspector.fileSize(at: preparedEpisode.preparedFileURL)
                        actions.append(.copyToDevice(
                            sourceURL: preparedEpisode.preparedFileURL,
                            destinationURL: destinationURL,
                            fileSizeBytes: fileSizeBytes
                        ))
                    } else if selectedFileURLs.contains(standardizedExistingURL) {
                        actions.append(.skip(reason: "Selected for removal from device: \(preparedEpisode.episode.title)"))
                    } else {
                        try verifyExistingCopy(existingFileURL, matches: preparedEpisode.preparedFileURL)
                        actions.append(.skip(reason: "Already on device: \(preparedEpisode.episode.title)"))
                    }
                } else if let existingFileURL = conservativeExistingFilesByEpisodeID[preparedEpisode.episode.id] {
                    let standardizedExistingURL = existingFileURL.standardizedFileURL
                    if replacementTargets.contains(standardizedExistingURL) {
                        try safetyValidator.validateWriteTarget(destinationURL, on: device)
                        let fileSizeBytes = try storageInspector.fileSize(at: preparedEpisode.preparedFileURL)
                        actions.append(.copyToDevice(
                            sourceURL: preparedEpisode.preparedFileURL,
                            destinationURL: destinationURL,
                            fileSizeBytes: fileSizeBytes
                        ))
                    } else if selectedFileURLs.contains(standardizedExistingURL) {
                        actions.append(.skip(reason: "Selected for removal from device: \(preparedEpisode.episode.title)"))
                    } else {
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

        actions.append(contentsOf: try makePodcastPlaylistActions(
            library: podcastPlaylistLibrary,
            device: device,
            subscriptions: subscriptions,
            preparedEpisodes: preparedEpisodes,
            deviceInventory: deviceInventory,
            mediaActions: actions
        ))

        if ejectAfterSync {
            actions.append(.ejectDevice(deviceRootURL: device.rootURL))
        }

        try storageInspector.ensurePlanFits(actions, on: device)
        let orderedActions = orderDeletionsBeforeCopies(actions)
        return SyncPlan(
            device: device,
            actions: orderedActions,
            cleanupCandidates: cleanupCandidates.sorted(by: cleanupCandidateSort),
            playlistProtectedCleanupCandidates: playlistProtectedCleanupCandidates.sorted(
                by: playlistProtectedCleanupCandidateSort
            ),
            existingManagedEpisodeURLs: deviceInventory.allManagedFileURLs.sorted { $0.path < $1.path }
        )
    }

    private func validatedMaximumEpisodesPerPodcast(
        for policy: DeviceCleanupPolicy
    ) throws -> Int? {
        guard let maximumEpisodesPerPodcast = policy.maximumEpisodesPerPodcast else { return nil }
        guard DeviceCleanupPolicy.allowedMaximumEpisodesPerPodcast.contains(maximumEpisodesPerPodcast) else {
            throw DeviceCleanupPolicyError.invalidMaximumEpisodesPerPodcast(maximumEpisodesPerPodcast)
        }
        return maximumEpisodesPerPodcast
    }

    private func makeCleanupReview(
        existingFiles: [URL],
        preparedEpisodes: [PreparedEpisode],
        managedDirectory: URL,
        subscription: PodcastSubscription,
        manualDeleteTargets: Set<URL>,
        replacementTargets: Set<URL>,
        protectedFilesByURL: [URL: ProtectedPlaylistEntry],
        protectedEpisodeIDs: Set<PodcastPlaylistEpisodeID>,
        maximumEpisodesPerPodcast: Int,
        device: DeviceInfo
    ) throws -> CleanupReview {
        var retentionEntriesByURL: [URL: CleanupRetentionEntry] = [:]

        for fileURL in existingFiles {
            let standardizedURL = fileURL.standardizedFileURL
            guard !manualDeleteTargets.contains(standardizedURL),
                  protectedFilesByURL[standardizedURL] == nil,
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
            if let episodeID = PodcastPlaylistEpisodeID(episode: preparedEpisode.episode),
               protectedEpisodeIDs.contains(episodeID) {
                continue
            }
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
        guard orderedEntries.count >= maximumEpisodesPerPodcast else { return CleanupReview() }
        let oldestRetainedDate = orderedEntries[maximumEpisodesPerPodcast - 1].publicationDate
        let excessExistingEpisodes = orderedEntries
            .dropFirst(maximumEpisodesPerPodcast)
            .filter { entry in
                entry.existsOnDevice && entry.publicationDate < oldestRetainedDate
            }

        let cleanupCandidates = try excessExistingEpisodes.map { entry in
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

        let playlistProtectedCandidates = try protectedFilesByURL.compactMap {
            fileURL, protectedEntry -> PlaylistProtectedCleanupCandidate? in
            guard !replacementTargets.contains(fileURL),
                  let metadata = EpisodeFileName.parsedMetadata(from: fileURL),
                  let publicationDate = metadata.publicationDate,
                  publicationDate < oldestRetainedDate else { return nil }
            try safetyValidator.validateDeleteTarget(fileURL, on: device)
            return PlaylistProtectedCleanupCandidate(
                targetURL: fileURL,
                episode: protectedEntry.entry.episode,
                publicationDate: publicationDate,
                fileSizeBytes: try storageInspector.fileSize(at: fileURL),
                playlistNames: protectedEntry.playlistNames
            )
        }

        return CleanupReview(
            cleanupCandidates: cleanupCandidates,
            playlistProtectedCandidates: playlistProtectedCandidates
        )
    }

    private func protectedPlaylistEntries(
        for subscription: PodcastSubscription,
        podcastPlaylistLibrary: PodcastPlaylistLibrary
    ) -> [ProtectedPlaylistEntry] {
        let recentlyDownloadedEpisodes = podcastPlaylistLibrary.recentlyDownloadedEntries.map(\.episode)
        var entriesByID: [PodcastPlaylistEpisodeID: (PodcastPlaylistEntry, Set<String>)] = [:]

        for playlist in podcastPlaylistLibrary.playlists {
            var entries = playlist.entries
            if playlist.automaticRule?.source == .recentlyDownloaded {
                entries.append(contentsOf: PodcastPlaylistResolver.entries(
                    for: playlist,
                    from: recentlyDownloadedEpisodes,
                    recentlyDownloadedEntries: podcastPlaylistLibrary.recentlyDownloadedEntries
                ).automatic)
            }
            for entry in entries where entry.id.subscriptionID == subscription.id {
                let existing = entriesByID[entry.id]
                entriesByID[entry.id] = (
                    existing?.0 ?? entry,
                    (existing?.1 ?? []).union([playlist.name])
                )
            }
        }

        return entriesByID.values.map { entry, playlistNames in
            ProtectedPlaylistEntry(
                entry: entry,
                playlistNames: playlistNames.sorted {
                    $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                }
            )
        }
    }

    private func protectedDeviceFilesByURL(
        existingFiles: [URL],
        protectedEntries: [ProtectedPlaylistEntry],
        subscription: PodcastSubscription
    ) -> [URL: ProtectedPlaylistEntry] {
        let protectedEpisodes = protectedEntries.map(\.entry.episode)
        guard !protectedEpisodes.isEmpty else { return [:] }

        let conservativeMatches = EpisodeFileName.uniqueConservativeMatches(
            in: existingFiles,
            to: protectedEpisodes,
            subscription: subscription
        )
        var protectedEntriesByURL: [URL: ProtectedPlaylistEntry] = [:]
        for protectedEntry in protectedEntries {
            let episode = protectedEntry.entry.episode
            let matchedURL: URL?
            if let exactMatch = existingFiles.first(where: {
                EpisodeFileName.fileStem(for: episode) == $0.deletingPathExtension().lastPathComponent
            }) {
                matchedURL = exactMatch
            } else if let conservativeMatch = conservativeMatches[episode.id] {
                matchedURL = conservativeMatch
            } else {
                matchedURL = nil
            }
            guard let matchedURL else { continue }
            let standardizedURL = matchedURL.standardizedFileURL
            if let existing = protectedEntriesByURL[standardizedURL] {
                protectedEntriesByURL[standardizedURL] = ProtectedPlaylistEntry(
                    entry: existing.entry,
                    playlistNames: Array(Set(existing.playlistNames + protectedEntry.playlistNames)).sorted {
                        $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                    }
                )
            } else {
                protectedEntriesByURL[standardizedURL] = protectedEntry
            }
        }
        return protectedEntriesByURL
    }

    private func makePodcastPlaylistActions(
        library: PodcastPlaylistLibrary,
        device: DeviceInfo,
        subscriptions: [PodcastSubscription],
        preparedEpisodes: [PreparedEpisode],
        deviceInventory: ManagedDeviceLibraryInventory,
        mediaActions: [SyncAction]
    ) throws -> [SyncAction] {
        guard !library.playlists.isEmpty || library.deviceStates[device.id] != nil else { return [] }
        let encoder = M3UPlaylistEncoder()
        let subscriptionsByID = Dictionary(uniqueKeysWithValues: subscriptions.map { ($0.id, $0) })
        let plannedDeletionURLs = Set(mediaActions.compactMap { action -> URL? in
            guard case .deleteFromDevice(let targetURL, _) = action else { return nil }
            return targetURL.standardizedFileURL
        })
        let plannedCopyURLsByEpisodeID = Dictionary(uniqueKeysWithValues: preparedEpisodes.compactMap { prepared -> (PodcastPlaylistEpisodeID, URL)? in
            guard let entryID = PodcastPlaylistEpisodeID(episode: prepared.episode),
                  let copyAction = mediaActions.first(where: { action in
                      guard case .copyToDevice(let sourceURL, _, _) = action else { return false }
                      return sourceURL.standardizedFileURL == prepared.preparedFileURL.standardizedFileURL
                  }),
                  case .copyToDevice(_, let destinationURL, _) = copyAction else { return nil }
            return (entryID, destinationURL)
        })
        let deviceState = library.deviceStates[device.id] ?? PodcastPlaylistDeviceState()
        let activePlaylistFileNames = Set(library.playlists.map {
            PodcastPlaylistName.normalized($0.deviceFileName)
        })
        let rootFiles = try deviceLibrary.files(in: device.podcastDirectoryURL)
        let existingFileNames = Set(rootFiles.map {
            PodcastPlaylistName.normalized($0.lastPathComponent)
        })
        let ownedFileNames = Set(deviceState.ownedDeviceFileNames.map(PodcastPlaylistName.normalized))
        var playlistActions: [SyncAction] = []

        for playlist in library.playlists {
            try Task.checkCancellation()
            let destinationURL = device.podcastDirectoryURL.appendingPathComponent(
                playlist.deviceFileName,
                isDirectory: false
            )
            try safetyValidator.validatePodcastPlaylistTarget(destinationURL, on: device)
            let normalizedFileName = PodcastPlaylistName.normalized(playlist.deviceFileName)
            if existingFileNames.contains(normalizedFileName),
               !ownedFileNames.contains(normalizedFileName) {
                throw PodcastPlaylistPlanningError.fileNameCollision(destinationURL)
            }

            let explicitFileURLs = playlist.entries.compactMap { entry -> URL? in
                if let plannedCopyURL = plannedCopyURLsByEpisodeID[entry.id] {
                    return plannedCopyURL
                }
                guard let subscription = subscriptionsByID[entry.id.subscriptionID] else { return nil }
                let existingFiles = deviceInventory.files(for: subscription)
                let exactMatch = existingFiles.first {
                    EpisodeFileName.fileStem(for: entry.episode) == $0.deletingPathExtension().lastPathComponent
                }
                let matchedURL = exactMatch ?? EpisodeFileName.uniqueConservativeMatches(
                    in: existingFiles,
                    to: [entry.episode],
                    subscription: subscription
                )[entry.episode.id]
                guard let matchedURL,
                      !plannedDeletionURLs.contains(matchedURL.standardizedFileURL) else { return nil }
                return matchedURL
            }
            let explicitStandardizedURLs = Set(explicitFileURLs.map(\.standardizedFileURL))
            let automaticFileURLs = automaticPlaylistFileURLs(
                playlist: playlist,
                excluding: explicitStandardizedURLs,
                subscriptions: subscriptions,
                preparedEpisodes: preparedEpisodes,
                recentlyDownloadedEntries: library.recentlyDownloadedEntries,
                plannedCopyURLsByEpisodeID: plannedCopyURLsByEpisodeID,
                plannedDeletionURLs: plannedDeletionURLs,
                deviceInventory: deviceInventory
            )
            let episodeFileURLs = explicitFileURLs + automaticFileURLs
            let contents = try encoder.encode(fileURLs: episodeFileURLs, on: device)
            playlistActions.append(.writePodcastPlaylist(
                destinationURL: destinationURL,
                contents: contents,
                episodeCount: episodeFileURLs.count
            ))
        }

        for fileName in deviceState.pendingDeletedDeviceFileNames
            .filter({ !activePlaylistFileNames.contains(PodcastPlaylistName.normalized($0)) })
            .sorted() {
            let targetURL = device.podcastDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
            try safetyValidator.validatePodcastPlaylistTarget(targetURL, on: device)
            playlistActions.append(.deletePodcastPlaylist(targetURL: targetURL))
        }
        return playlistActions
    }

    private func automaticPlaylistFileURLs(
        playlist: PodcastPlaylist,
        excluding explicitFileURLs: Set<URL>,
        subscriptions: [PodcastSubscription],
        preparedEpisodes: [PreparedEpisode],
        recentlyDownloadedEntries: [PodcastPlaylistEntry],
        plannedCopyURLsByEpisodeID: [PodcastPlaylistEpisodeID: URL],
        plannedDeletionURLs: Set<URL>,
        deviceInventory: ManagedDeviceLibraryInventory
    ) -> [URL] {
        guard let rule = playlist.automaticRule else { return [] }

        if rule.source == .recentlyDownloaded {
            let subscriptionsByID = Dictionary(uniqueKeysWithValues: subscriptions.map { ($0.id, $0) })
            var includedURLs: Set<URL> = []
            var fileURLs: [URL] = []
            for entry in recentlyDownloadedEntries {
                guard let exclusion = PodcastPlaylistAutomaticExclusion(episode: entry.episode),
                      !playlist.automaticExclusions.contains(exclusion) else { continue }

                let fileURL: URL?
                if let plannedCopyURL = plannedCopyURLsByEpisodeID[entry.id] {
                    fileURL = plannedCopyURL
                } else if let subscription = subscriptionsByID[entry.id.subscriptionID] {
                    let existingFiles = deviceInventory.files(for: subscription)
                    fileURL = existingFiles.first {
                        EpisodeFileName.fileStem(for: entry.episode)
                            == $0.deletingPathExtension().lastPathComponent
                    } ?? EpisodeFileName.uniqueConservativeMatches(
                        in: existingFiles,
                        to: [entry.episode],
                        subscription: subscription
                    )[entry.episode.id]
                } else {
                    fileURL = nil
                }

                guard let fileURL else { continue }
                let standardizedURL = fileURL.standardizedFileURL
                guard !explicitFileURLs.contains(standardizedURL),
                      !plannedDeletionURLs.contains(standardizedURL),
                      includedURLs.insert(standardizedURL).inserted else { continue }
                fileURLs.append(fileURL)
            }
            if let maximumEpisodeCount = rule.maximumEpisodeCount {
                guard maximumEpisodeCount > 0 else { return [] }
                return Array(fileURLs.prefix(maximumEpisodeCount))
            }
            return fileURLs
        }

        var candidatesByURL: [URL: AutomaticPlaylistFileCandidate] = [:]

        for subscription in subscriptions where rule.source.includesPodcast(subscription.id) {
            for fileURL in deviceInventory.files(for: subscription) {
                let standardizedURL = fileURL.standardizedFileURL
                let exclusion = PodcastPlaylistAutomaticExclusion(
                    subscriptionID: subscription.id,
                    episodeFileStem: fileURL.deletingPathExtension().lastPathComponent
                )
                guard !explicitFileURLs.contains(standardizedURL),
                      !plannedDeletionURLs.contains(standardizedURL),
                      !playlist.automaticExclusions.contains(exclusion) else { continue }
                candidatesByURL[standardizedURL] = AutomaticPlaylistFileCandidate(
                    fileURL: fileURL,
                    publicationDate: EpisodeFileName.publicationDate(from: fileURL)
                )
            }
        }

        for preparedEpisode in preparedEpisodes {
            guard let entryID = PodcastPlaylistEpisodeID(episode: preparedEpisode.episode),
                  rule.source.includesPodcast(entryID.subscriptionID),
                  let plannedCopyURL = plannedCopyURLsByEpisodeID[entryID],
                  let exclusion = PodcastPlaylistAutomaticExclusion(episode: preparedEpisode.episode),
                  !playlist.automaticExclusions.contains(exclusion) else { continue }
            let standardizedURL = plannedCopyURL.standardizedFileURL
            guard !explicitFileURLs.contains(standardizedURL) else { continue }
            candidatesByURL[standardizedURL] = AutomaticPlaylistFileCandidate(
                fileURL: plannedCopyURL,
                publicationDate: preparedEpisode.episode.publicationDate
                    ?? EpisodeFileName.publicationDate(from: plannedCopyURL)
            )
        }

        let sortedCandidates = candidatesByURL.values.sorted(by: AutomaticPlaylistFileCandidate.isNewer)
        guard let maximumEpisodeCount = rule.maximumEpisodeCount else {
            return sortedCandidates.map(\.fileURL)
        }
        guard maximumEpisodeCount > 0 else { return [] }
        return sortedCandidates.prefix(maximumEpisodeCount).map(\.fileURL)
    }

    private struct AutomaticPlaylistFileCandidate {
        var fileURL: URL
        var publicationDate: Date?

        static func isNewer(_ lhs: Self, _ rhs: Self) -> Bool {
            switch (lhs.publicationDate, rhs.publicationDate) {
            case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
                return lhsDate > rhsDate
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return lhs.fileURL.lastPathComponent.localizedCaseInsensitiveCompare(
                    rhs.fileURL.lastPathComponent
                ) == .orderedAscending
            }
        }
    }

    private struct CleanupReview {
        var cleanupCandidates: [DeviceCleanupCandidate] = []
        var playlistProtectedCandidates: [PlaylistProtectedCleanupCandidate] = []
    }

    private struct ProtectedPlaylistEntry {
        var entry: PodcastPlaylistEntry
        var playlistNames: [String]
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

    private func playlistProtectedCleanupCandidateSort(
        _ lhs: PlaylistProtectedCleanupCandidate,
        _ rhs: PlaylistProtectedCleanupCandidate
    ) -> Bool {
        if lhs.publicationDate != rhs.publicationDate {
            return lhs.publicationDate < rhs.publicationDate
        }
        if lhs.episode.podcastTitle != rhs.episode.podcastTitle {
            return lhs.episode.podcastTitle.localizedCaseInsensitiveCompare(
                rhs.episode.podcastTitle
            ) == .orderedAscending
        }
        return lhs.episode.title.localizedCaseInsensitiveCompare(
            rhs.episode.title
        ) == .orderedAscending
    }

    private func verifyExistingCopy(_ deviceURL: URL, matches preparedURL: URL) throws {
        let expectedSize = try storageInspector.fileSize(at: preparedURL)
        let actualSize = try storageInspector.fileSize(at: deviceURL)
        guard expectedSize == actualSize else {
            throw SyncCapacityError.incompleteExistingCopy(
                targetURL: deviceURL,
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

public enum PodcastPlaylistPlanningError: LocalizedError, Equatable, Sendable {
    case fileNameCollision(URL)

    public var errorDescription: String? {
        switch self {
        case .fileNameCollision(let url):
            "SPM won’t replace the existing playlist \(url.lastPathComponent) because it did not create that file. Rename the playlist in SPM and try again."
        }
    }
}
