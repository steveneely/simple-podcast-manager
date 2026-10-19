import Foundation
import Observation
import SimplePodcastManagerCore

struct PodcastPlaylistPresentation: Equatable, Sendable {
    var entriesByPlaylistID: [PodcastPlaylist.ID: ResolvedPodcastPlaylistEntries]
    var episodeCountsByPlaylistID: [PodcastPlaylist.ID: Int]

    static let empty = PodcastPlaylistPresentation(
        entriesByPlaylistID: [:],
        episodeCountsByPlaylistID: [:]
    )

    func automaticPlaylistIDs(containing episode: Episode) -> Set<PodcastPlaylist.ID> {
        guard let episodeID = PodcastPlaylistEpisodeID(episode: episode) else { return [] }
        return Set(entriesByPlaylistID.compactMap { playlistID, entries in
            entries.automatic.contains(where: { $0.id == episodeID }) ? playlistID : nil
        })
    }

    func entries(reflecting playlist: PodcastPlaylist) -> ResolvedPodcastPlaylistEntries {
        let explicitEntryIDs = Set(playlist.entries.map(\.id))
        let automaticEntries = entriesByPlaylistID[playlist.id]?.automatic.filter {
            guard !explicitEntryIDs.contains($0.id) else { return false }
            guard let exclusion = PodcastPlaylistAutomaticExclusion(episode: $0.episode) else {
                return false
            }
            return !playlist.automaticExclusions.contains(exclusion)
        } ?? []
        return ResolvedPodcastPlaylistEntries(
            explicit: playlist.entries,
            automatic: automaticEntries
        )
    }
}

struct PodcastPlaylistAvailabilityInput: Equatable, Sendable {
    var subscriptions: [PodcastSubscription]
    var episodes: [Episode]
    var preparedEpisodeIDs: Set<PodcastPlaylistEpisodeID>
    var recentlyDownloadedEntries: [PodcastPlaylistEntry]
    var managedInventory: ManagedDeviceLibraryInventory?
    var plannedRemovalURLs: Set<URL>
    var replacementTargets: Set<URL>

    func availableEpisodes() -> [Episode] {
        PodcastPlaylistPresentationBuilder.availableEpisodes(
            subscriptions: subscriptions,
            episodes: episodes,
            preparedEpisodeIDs: preparedEpisodeIDs,
            downloadedEpisodeSnapshots: recentlyDownloadedEntries,
            managedInventory: managedInventory,
            plannedRemovalURLs: plannedRemovalURLs,
            replacementTargets: replacementTargets
        )
    }
}

enum PodcastPlaylistPresentationBuilder {
    static func build(
        playlists: [PodcastPlaylist],
        subscriptions: [PodcastSubscription],
        episodes: [Episode],
        preparedEpisodeIDs: Set<PodcastPlaylistEpisodeID>,
        recentlyDownloadedEntries: [PodcastPlaylistEntry],
        managedInventory: ManagedDeviceLibraryInventory?,
        plannedRemovalURLs: Set<URL>,
        replacementTargets: Set<URL>
    ) -> PodcastPlaylistPresentation {
        let availableEpisodes = availableEpisodes(
            subscriptions: subscriptions,
            episodes: episodes,
            preparedEpisodeIDs: preparedEpisodeIDs,
            downloadedEpisodeSnapshots: recentlyDownloadedEntries,
            managedInventory: managedInventory,
            plannedRemovalURLs: plannedRemovalURLs,
            replacementTargets: replacementTargets
        )
        return build(
            playlists: playlists,
            availableEpisodes: availableEpisodes,
            recentlyDownloadedEntries: recentlyDownloadedEntries
        )
    }

    static func build(
        playlists: [PodcastPlaylist],
        availableEpisodes: [Episode],
        recentlyDownloadedEntries: [PodcastPlaylistEntry]
    ) -> PodcastPlaylistPresentation {
        var entriesByPlaylistID: [PodcastPlaylist.ID: ResolvedPodcastPlaylistEntries] = [:]
        for playlist in playlists {
            guard !Task.isCancelled else { return .empty }
            entriesByPlaylistID[playlist.id] = PodcastPlaylistResolver.entries(
                for: playlist,
                from: availableEpisodes,
                recentlyDownloadedEntries: recentlyDownloadedEntries
            )
        }
        return PodcastPlaylistPresentation(
            entriesByPlaylistID: entriesByPlaylistID,
            episodeCountsByPlaylistID: entriesByPlaylistID.mapValues(\.all.count)
        )
    }

    fileprivate static func availableEpisodes(
        subscriptions: [PodcastSubscription],
        episodes: [Episode],
        preparedEpisodeIDs: Set<PodcastPlaylistEpisodeID>,
        downloadedEpisodeSnapshots: [PodcastPlaylistEntry],
        managedInventory: ManagedDeviceLibraryInventory?,
        plannedRemovalURLs: Set<URL>,
        replacementTargets: Set<URL>
    ) -> [Episode] {
        let episodesBySubscriptionID = Dictionary(
            grouping: episodes.compactMap { episode -> (PodcastSubscription.ID, Episode)? in
                guard let subscriptionID = episode.subscriptionID else { return nil }
                return (subscriptionID, episode)
            },
            by: \.0
        ).mapValues { $0.map(\.1) }
        var availableEpisodes: [Episode] = []
        var unavailableEpisodeIDs: Set<PodcastPlaylistEpisodeID> = []
        var unavailableEpisodeKeys: Set<PodcastPlaylistAutomaticExclusion> = []
        var deviceFileStemsBySubscriptionID: [PodcastSubscription.ID: Set<String>] = [:]

        for subscription in subscriptions {
            guard !Task.isCancelled else { return [] }
            let currentEpisodes = episodesBySubscriptionID[subscription.id] ?? []
            let deviceFiles = managedInventory?.files(for: subscription) ?? []
            var deviceFilesByStem: [String: URL] = [:]
            for fileURL in deviceFiles {
                if plannedRemovalURLs.contains(fileURL.standardizedFileURL),
                   !replacementTargets.contains(fileURL.standardizedFileURL) {
                    unavailableEpisodeKeys.insert(PodcastPlaylistAutomaticExclusion(
                        subscriptionID: subscription.id,
                        episodeFileStem: fileURL.deletingPathExtension().lastPathComponent
                    ))
                }
                let fileStem = fileURL.deletingPathExtension().lastPathComponent
                if deviceFilesByStem[fileStem] == nil {
                    deviceFilesByStem[fileStem] = fileURL
                }
            }
            deviceFileStemsBySubscriptionID[subscription.id] = Set(deviceFilesByStem.keys)
            let conservativeMatches = EpisodeFileName.uniqueConservativeMatches(
                in: deviceFiles,
                to: currentEpisodes,
                subscription: subscription
            )
            var matchedDeviceFiles: Set<URL> = []

            for episode in currentEpisodes {
                let deviceFileURL = deviceFilesByStem[EpisodeFileName.fileStem(for: episode)]
                    ?? conservativeMatches[episode.id]
                if let deviceFileURL {
                    matchedDeviceFiles.insert(deviceFileURL.standardizedFileURL)
                    if plannedRemovalURLs.contains(deviceFileURL.standardizedFileURL),
                       !replacementTargets.contains(deviceFileURL.standardizedFileURL) {
                        if let episodeID = PodcastPlaylistEpisodeID(episode: episode) {
                            unavailableEpisodeIDs.insert(episodeID)
                        }
                        continue
                    }
                }
                let isPrepared = PodcastPlaylistEpisodeID(episode: episode)
                    .map(preparedEpisodeIDs.contains) ?? false
                if isPrepared || deviceFileURL != nil {
                    availableEpisodes.append(episode)
                }
            }

            for fileURL in deviceFiles {
                let standardizedURL = fileURL.standardizedFileURL
                guard !matchedDeviceFiles.contains(standardizedURL),
                      !plannedRemovalURLs.contains(standardizedURL),
                      let metadata = EpisodeFileName.parsedMetadata(from: fileURL) else { continue }
                availableEpisodes.append(Episode(
                    id: "device-file::\(fileURL.lastPathComponent)",
                    subscriptionID: subscription.id,
                    podcastTitle: metadata.podcastTitle ?? subscription.title,
                    title: metadata.episodeTitle,
                    publicationDate: metadata.publicationDate,
                    enclosureURL: fileURL,
                    sourceFeedURL: subscription.rssURL
                ))
            }
        }

        let subscribedPodcastIDs = Set(subscriptions.map(\.id))
        var availableEpisodeIDs = Set(availableEpisodes.compactMap(PodcastPlaylistEpisodeID.init))
        for snapshot in downloadedEpisodeSnapshots {
            guard !Task.isCancelled else { return [] }
            // A mounted inventory is authoritative for device-only snapshots. Keep
            // offline history, but never resurrect a file known to be absent.
            if snapshot.episode.enclosureURL.isFileURL, managedInventory != nil {
                let stem = snapshot.episode.enclosureURL.deletingPathExtension().lastPathComponent
                guard deviceFileStemsBySubscriptionID[snapshot.id.subscriptionID]?.contains(stem) == true else {
                    continue
                }
            }
            let snapshotKey = PodcastPlaylistAutomaticExclusion(episode: snapshot.episode)
            let isSelectedForRemoval = snapshotKey.map(unavailableEpisodeKeys.contains) ?? false
            guard subscribedPodcastIDs.contains(snapshot.id.subscriptionID),
                  !unavailableEpisodeIDs.contains(snapshot.id),
                  !isSelectedForRemoval,
                  availableEpisodeIDs.insert(snapshot.id).inserted else { continue }
            availableEpisodes.append(snapshot.episode)
        }
        return availableEpisodes
    }
}

@MainActor
@Observable
final class PodcastPlaylistPresentationViewModel {
    private(set) var presentation = PodcastPlaylistPresentation.empty

    private struct Resolution: Sendable {
        var presentation: PodcastPlaylistPresentation
        var availableEpisodes: [Episode]
    }

    private let resolveAvailableEpisodes: @Sendable (PodcastPlaylistAvailabilityInput) -> [Episode]
    private var latestAvailabilityInput: PodcastPlaylistAvailabilityInput?
    private var latestPlaylists: [PodcastPlaylist]?
    private var cachedAvailabilityInput: PodcastPlaylistAvailabilityInput?
    private var cachedAvailableEpisodes: [Episode] = []
    private var onResolvedAutomaticEpisodes: @MainActor ([Episode]) -> Void = { _ in }
    private var latestRefreshID: UUID?
    private var workerTask: Task<Resolution, Never>?
    private var resultTask: Task<Void, Never>?

    init(
        resolveAvailableEpisodes: @escaping @Sendable (PodcastPlaylistAvailabilityInput) -> [Episode] = {
            $0.availableEpisodes()
        }
    ) {
        self.resolveAvailableEpisodes = resolveAvailableEpisodes
    }

    @discardableResult
    func refresh(
        playlists: [PodcastPlaylist],
        subscriptions: [PodcastSubscription],
        episodes: [Episode],
        preparedEpisodes: [PreparedEpisode],
        recentlyDownloadedEntries: [PodcastPlaylistEntry],
        managedInventory: ManagedDeviceLibraryInventory?,
        plannedRemovalURLs: Set<URL>,
        replacementTargets: Set<URL>,
        onResolvedAutomaticEpisodes: @escaping @MainActor ([Episode]) -> Void = { _ in }
    ) -> Task<Void, Never> {
        let availabilityInput = PodcastPlaylistAvailabilityInput(
            subscriptions: subscriptions,
            episodes: episodes,
            preparedEpisodeIDs: Set(preparedEpisodes.compactMap {
                PodcastPlaylistEpisodeID(episode: $0.episode)
            }),
            recentlyDownloadedEntries: recentlyDownloadedEntries,
            managedInventory: managedInventory,
            plannedRemovalURLs: plannedRemovalURLs,
            replacementTargets: replacementTargets
        )
        self.onResolvedAutomaticEpisodes = onResolvedAutomaticEpisodes
        // Keep identical work in flight rather than cancelling and starting it again.
        if latestAvailabilityInput == availabilityInput, latestPlaylists == playlists {
            if let resultTask { return resultTask }
            publishResolvedAutomaticEpisodes()
            return Task {}
        }

        workerTask?.cancel()
        resultTask?.cancel()
        let refreshID = UUID()
        latestRefreshID = refreshID
        latestAvailabilityInput = availabilityInput
        latestPlaylists = playlists
        let reusableEpisodes = cachedAvailabilityInput == availabilityInput ? cachedAvailableEpisodes : nil
        let resolveAvailableEpisodes = resolveAvailableEpisodes

        let workerTask = Task.detached(priority: .userInitiated) {
            let availableEpisodes = reusableEpisodes ?? resolveAvailableEpisodes(availabilityInput)
            return Resolution(presentation: PodcastPlaylistPresentationBuilder.build(
                playlists: playlists,
                availableEpisodes: availableEpisodes,
                recentlyDownloadedEntries: recentlyDownloadedEntries
            ), availableEpisodes: availableEpisodes)
        }
        self.workerTask = workerTask
        let resultTask = Task { [weak self] in
            let resolution = await workerTask.value
            guard !Task.isCancelled, let self, self.latestRefreshID == refreshID else { return }
            self.cachedAvailabilityInput = availabilityInput
            self.cachedAvailableEpisodes = resolution.availableEpisodes
            self.presentation = resolution.presentation
            self.workerTask = nil
            self.resultTask = nil
            self.publishResolvedAutomaticEpisodes()
        }
        self.resultTask = resultTask
        return resultTask
    }

    private func publishResolvedAutomaticEpisodes() {
        let onResolved = onResolvedAutomaticEpisodes
        onResolvedAutomaticEpisodes = { _ in }
        onResolved(
            presentation.entriesByPlaylistID.values.flatMap { $0.automatic.map(\.episode) }
        )
    }
}
