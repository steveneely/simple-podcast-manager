import Foundation
import SimplePodcastManagerCore

struct PodcastPlaylistSyncPreflight: Equatable {
    let unavailableEpisodes: [Episode]
    let affectedPlaylistNames: [String]

    static func make(
        playlists: [PodcastPlaylist],
        isAvailable: (Episode) -> Bool
    ) -> PodcastPlaylistSyncPreflight? {
        var unavailableEpisodes: [Episode] = []
        var unavailableEpisodeIDs: Set<PodcastPlaylistEpisodeID> = []
        var affectedPlaylistNames: [String] = []

        for playlist in playlists {
            var playlistHasUnavailableEntry = false
            for entry in playlist.entries where !isAvailable(entry.episode) {
                playlistHasUnavailableEntry = true
                if unavailableEpisodeIDs.insert(entry.id).inserted {
                    unavailableEpisodes.append(entry.episode)
                }
            }
            if playlistHasUnavailableEntry {
                affectedPlaylistNames.append(playlist.name)
            }
        }

        guard !unavailableEpisodes.isEmpty else { return nil }
        return PodcastPlaylistSyncPreflight(
            unavailableEpisodes: unavailableEpisodes,
            affectedPlaylistNames: affectedPlaylistNames
        )
    }

    var title: String {
        unavailableEpisodes.count == 1
            ? "Download Playlist Episode?"
            : "Download Playlist Episodes?"
    }

    var downloadButtonTitle: String {
        "Download and Continue"
    }

    var message: String {
        if let episode = unavailableEpisodes.first, unavailableEpisodes.count == 1 {
            return "\(playlistDescription) contains “\(episode.title),” which is unavailable. Download it so it can be included when you sync?"
        }
        return "\(playlistDescription) contains \(unavailableEpisodes.count) unavailable manually added episodes: \(episodeTitleSummary). Download them so they can be included when you sync?"
    }

    private var episodeTitleSummary: String {
        let visibleTitles = unavailableEpisodes.prefix(2).map { "“\($0.title)”" }
        let joinedTitles = visibleTitles.joined(separator: " and ")
        let remainingCount = unavailableEpisodes.count - visibleTitles.count
        guard remainingCount > 0 else { return joinedTitles }
        return "\(joinedTitles), and \(remainingCount) more"
    }

    private var playlistDescription: String {
        switch affectedPlaylistNames.count {
        case 0:
            return "A playlist"
        case 1:
            return "“\(affectedPlaylistNames[0])”"
        case 2:
            return "“\(affectedPlaylistNames[0])” and “\(affectedPlaylistNames[1])”"
        default:
            return "\(affectedPlaylistNames.count) playlists"
        }
    }
}

struct PodcastPlaylistSyncDownloadFailure: Equatable {
    let unavailableEpisodes: [Episode]
    let detail: String?

    var title: String {
        unavailableEpisodes.count == 1
            ? "Episode Couldn’t Be Downloaded"
            : "Some Episodes Couldn’t Be Downloaded"
    }

    var message: String {
        let summary: String
        if unavailableEpisodes.count == 1, let episode = unavailableEpisodes.first {
            summary = "“\(episode.title)” remains unavailable and will not be included when you sync."
        } else {
            summary = "\(unavailableEpisodes.count) episodes remain unavailable and will not be included when you sync."
        }
        guard let detail, !detail.isEmpty else { return summary }
        return "\(summary) \(detail)"
    }
}
