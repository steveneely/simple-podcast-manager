import Foundation
import SimplePodcastManagerCore

/// Keeps cleanup rows in review order when playlist membership changes their classification.
struct SyncCleanupReview {
    private(set) var candidates: [DeviceCleanupCandidate] = []
    private(set) var lastErrorMessage: String?
    private var deviceDirectory: URL?

    mutating func update(plan: SyncPlan) {
        let directory = plan.device.podcastDirectoryURL.standardizedFileURL
        if deviceDirectory != directory {
            candidates = []
            lastErrorMessage = nil
            deviceDirectory = directory
        }
        let currentIDs = Set(plan.cleanupCandidates.map(\.id)
            + plan.playlistProtectedCleanupCandidates.map(\.id))
        candidates.removeAll { !currentIDs.contains($0.id) }
        let existingIDs = Set(candidates.map(\.id))
        candidates.append(contentsOf: plan.cleanupCandidates.filter { !existingIDs.contains($0.id) })
    }

    func episode(
        for candidate: DeviceCleanupCandidate,
        subscriptions: [PodcastSubscription],
        knownEpisodes: [Episode],
        deviceFile: (Episode) -> URL?
    ) -> Episode? {
        let matches = knownEpisodes.filter {
            $0.subscriptionID == candidate.subscriptionID
                && deviceFile($0)?.standardizedFileURL == candidate.id
        }
        if let first = matches.first,
           Set(matches.map(\.id)).count == 1 { return first }
        guard let subscription = subscriptions.first(where: { $0.id == candidate.subscriptionID }) else {
            return nil
        }
        // Use the same stable identity as device-only episodes in playlist presentation.
        return Episode(
            id: "device-file::\(candidate.targetURL.lastPathComponent)",
            subscriptionID: candidate.subscriptionID,
            podcastTitle: candidate.podcastTitle,
            title: candidate.episodeTitle,
            publicationDate: candidate.publicationDate,
            enclosureURL: candidate.targetURL,
            sourceFeedURL: subscription.rssURL
        )
    }

    @MainActor
    mutating func togglePlaylist(
        for episode: Episode,
        candidate: DeviceCleanupCandidate,
        playlist: PodcastPlaylist,
        playlists: PodcastPlaylistViewModel,
        excludedCleanupTargets: inout Set<URL>,
        manualDeletionTargets: inout Set<URL>,
        protectedDeletionTargets: inout Set<URL>
    ) -> Bool {
        do {
            if playlist.contains(episode) {
                try playlists.remove(episode, from: playlist.id)
            } else {
                try playlists.add(episode, to: playlist.id, deviceFileURL: candidate.targetURL)
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
        lastErrorMessage = nil
        excludedCleanupTargets.insert(candidate.id)
        manualDeletionTargets.remove(candidate.id)
        protectedDeletionTargets.remove(candidate.id)
        return true
    }
}
