import Foundation

public struct ResolvedPodcastPlaylistEntries: Equatable, Sendable {
    public var explicit: [PodcastPlaylistEntry]
    public var automatic: [PodcastPlaylistEntry]

    public init(
        explicit: [PodcastPlaylistEntry],
        automatic: [PodcastPlaylistEntry]
    ) {
        self.explicit = explicit
        self.automatic = automatic
    }

    public var all: [PodcastPlaylistEntry] {
        explicit + automatic
    }
}

public enum PodcastPlaylistResolver {
    public static func entries(
        for playlist: PodcastPlaylist,
        from availableEpisodes: [Episode],
        recentlyDownloadedEntries: [PodcastPlaylistEntry] = []
    ) -> ResolvedPodcastPlaylistEntries {
        guard let rule = playlist.automaticRule else {
            return ResolvedPodcastPlaylistEntries(explicit: playlist.entries, automatic: [])
        }

        let explicitExclusionKeys = Set(playlist.entries.compactMap {
            PodcastPlaylistAutomaticExclusion(episode: $0.episode)
        })
        var automaticEntries: [PodcastPlaylistEntry]
        switch rule.source {
        case .recentlyDownloaded:
            var seenExclusionKeys: Set<PodcastPlaylistAutomaticExclusion> = []
            automaticEntries = recentlyDownloadedEntries.filter { entry in
                guard let exclusionKey = PodcastPlaylistAutomaticExclusion(episode: entry.episode),
                      !playlist.automaticExclusions.contains(exclusionKey),
                      !explicitExclusionKeys.contains(exclusionKey) else { return false }
                return seenExclusionKeys.insert(exclusionKey).inserted
            }
        case .allPodcasts, .selectedPodcasts:
            var entriesByExclusionKey: [PodcastPlaylistAutomaticExclusion: PodcastPlaylistEntry] = [:]
            for episode in availableEpisodes {
                guard let subscriptionID = episode.subscriptionID,
                      rule.source.includesPodcast(subscriptionID),
                      let entry = PodcastPlaylistEntry(episode: episode),
                      let exclusionKey = PodcastPlaylistAutomaticExclusion(episode: episode),
                      !playlist.automaticExclusions.contains(exclusionKey) else { continue }
                entriesByExclusionKey[exclusionKey] = entry
            }
            automaticEntries = entriesByExclusionKey
                .filter { !explicitExclusionKeys.contains($0.key) }
                .map(\.value)
                .sorted(by: isNewer)
        }

        if let maximumEpisodeCount = rule.maximumEpisodeCount {
            guard maximumEpisodeCount > 0 else {
                return ResolvedPodcastPlaylistEntries(explicit: playlist.entries, automatic: [])
            }
            automaticEntries = Array(automaticEntries.prefix(maximumEpisodeCount))
        }
        return ResolvedPodcastPlaylistEntries(
            explicit: playlist.entries,
            automatic: automaticEntries
        )
    }

    private static func isNewer(
        _ lhs: PodcastPlaylistEntry,
        _ rhs: PodcastPlaylistEntry
    ) -> Bool {
        switch (lhs.episode.publicationDate, rhs.episode.publicationDate) {
        case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
            return lhsDate > rhsDate
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            break
        }

        let podcastComparison = lhs.episode.podcastTitle.localizedCaseInsensitiveCompare(
            rhs.episode.podcastTitle
        )
        if podcastComparison != .orderedSame {
            return podcastComparison == .orderedAscending
        }
        return lhs.episode.title.localizedCaseInsensitiveCompare(rhs.episode.title) == .orderedAscending
    }
}
