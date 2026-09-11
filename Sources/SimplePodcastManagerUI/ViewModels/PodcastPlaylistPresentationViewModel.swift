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
            managedInventory: managedInventory,
            plannedRemovalURLs: plannedRemovalURLs,
            replacementTargets: replacementTargets
        )
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

    private static func availableEpisodes(
        subscriptions: [PodcastSubscription],
        episodes: [Episode],
        preparedEpisodeIDs: Set<PodcastPlaylistEpisodeID>,
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

        for subscription in subscriptions {
            guard !Task.isCancelled else { return [] }
            let currentEpisodes = episodesBySubscriptionID[subscription.id] ?? []
            let deviceFiles = managedInventory?.files(for: subscription) ?? []
            var deviceFilesByStem: [String: URL] = [:]
            for fileURL in deviceFiles {
                let fileStem = fileURL.deletingPathExtension().lastPathComponent
                if deviceFilesByStem[fileStem] == nil {
                    deviceFilesByStem[fileStem] = fileURL
                }
            }
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
        return availableEpisodes
    }
}

@MainActor
@Observable
final class PodcastPlaylistPresentationViewModel {
    private(set) var presentation = PodcastPlaylistPresentation.empty

    private var latestRefreshID: UUID?
    private var workerTask: Task<PodcastPlaylistPresentation, Never>?
    private var resultTask: Task<Void, Never>?

    func refresh(
        playlists: [PodcastPlaylist],
        subscriptions: [PodcastSubscription],
        episodes: [Episode],
        preparedEpisodes: [PreparedEpisode],
        recentlyDownloadedEntries: [PodcastPlaylistEntry],
        managedInventory: ManagedDeviceLibraryInventory?,
        plannedRemovalURLs: Set<URL>,
        replacementTargets: Set<URL>
    ) {
        workerTask?.cancel()
        resultTask?.cancel()
        let refreshID = UUID()
        latestRefreshID = refreshID
        let preparedEpisodeIDs = Set(preparedEpisodes.compactMap {
            PodcastPlaylistEpisodeID(episode: $0.episode)
        })

        let workerTask = Task.detached(priority: .userInitiated) {
            PodcastPlaylistPresentationBuilder.build(
                playlists: playlists,
                subscriptions: subscriptions,
                episodes: episodes,
                preparedEpisodeIDs: preparedEpisodeIDs,
                recentlyDownloadedEntries: recentlyDownloadedEntries,
                managedInventory: managedInventory,
                plannedRemovalURLs: plannedRemovalURLs,
                replacementTargets: replacementTargets
            )
        }
        self.workerTask = workerTask
        resultTask = Task { [weak self] in
            let updatedPresentation = await workerTask.value
            guard !Task.isCancelled, self?.latestRefreshID == refreshID else { return }
            self?.presentation = updatedPresentation
            self?.workerTask = nil
            self?.resultTask = nil
        }
    }
}
