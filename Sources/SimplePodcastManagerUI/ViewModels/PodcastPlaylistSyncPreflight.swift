import Foundation
import SimplePodcastManagerCore

enum PodcastPlaylistSyncChoice: CaseIterable {
    case download
    case remove
    case skip

    var continueButtonTitle: String {
        switch self {
        case .download: return "Download and Continue"
        case .remove: return "Remove and Continue"
        case .skip: return "Skip and Continue"
        }
    }

    func perform(download: () -> Void, remove: () -> Void, skip: () -> Void) {
        switch self {
        case .download: download()
        case .remove: remove()
        case .skip: skip()
        }
    }
}

struct PodcastPlaylistSyncPreflight: Equatable {
    let unavailableEpisodes: [Episode]
    let affectedPlaylistNames: [String]
    let unavailableEntryIDsByPlaylist: [PodcastPlaylist.ID: Set<PodcastPlaylistEpisodeID>]

    static func make(
        playlists: [PodcastPlaylist],
        isAvailable: (Episode) -> Bool
    ) -> PodcastPlaylistSyncPreflight? {
        var unavailableEpisodes: [Episode] = []
        var unavailableEpisodeIDs: Set<PodcastPlaylistEpisodeID> = []
        var affectedPlaylistNames: [String] = []
        var unavailableEntryIDsByPlaylist: [PodcastPlaylist.ID: Set<PodcastPlaylistEpisodeID>] = [:]

        for playlist in playlists {
            var playlistHasUnavailableEntry = false
            for entry in playlist.entries where !isAvailable(entry.episode) {
                playlistHasUnavailableEntry = true
                unavailableEntryIDsByPlaylist[playlist.id, default: []].insert(entry.id)
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
            affectedPlaylistNames: affectedPlaylistNames,
            unavailableEntryIDsByPlaylist: unavailableEntryIDsByPlaylist
        )
    }

    var title: String {
        unavailableEpisodes.count == 1
            ? "1 Playlist Episode Is Unavailable"
            : "\(unavailableEpisodes.count) Playlist Episodes Are Unavailable"
    }

    var message: String {
        unavailableEpisodes.count == 1
            ? "This episode in \(playlistDescription) isn’t on the device or downloaded locally:"
            : "These episodes in \(playlistDescription) aren’t on the device or downloaded locally:"
    }

    func choiceTitle(_ choice: PodcastPlaylistSyncChoice) -> String {
        switch choice {
        case .download: return "Download again"
        case .remove: return affectedPlaylistNames.count == 1 ? "Remove from playlist" : "Remove from playlists"
        case .skip: return "Skip for this sync"
        }
    }

    func choiceDetail(_ choice: PodcastPlaylistSyncChoice) -> String {
        switch choice {
        case .download:
            return "Download the episodes and keep them in the playlist."
        case .remove:
            return "Remove these entries and continue without downloading."
        case .skip:
            return "Keep the entries and decide next time."
        }
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
