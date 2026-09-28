import SwiftUI
import SimplePodcastManagerCore

struct EpisodePlaylistMenu: View {
    let episode: Episode
    let playlists: [PodcastPlaylist]
    let automaticPlaylistIDs: Set<PodcastPlaylist.ID>
    let onTogglePlaylist: (PodcastPlaylist) -> Void

    var body: some View {
        let playlistIndicator = EpisodePlaylistIndicatorPresentation(
            episode: episode,
            playlists: playlists,
            automaticPlaylistIDs: automaticPlaylistIDs
        )
        HoverIconMenu(
            systemName: playlistIndicator.systemName,
            helpText: playlistIndicator.helpText,
            isActive: playlistIndicator.isIncluded
        ) {
            ForEach(playlists) { playlist in
                Toggle(isOn: Binding(
                    get: { playlistIndicator.membership(for: playlist.id) != .none },
                    set: { _ in onTogglePlaylist(playlist) }
                )) {
                    Text(playlistIndicator.membership(for: playlist.id) == .automatic
                        ? "\(playlist.name) (Auto)"
                        : playlist.name)
                }
            }
        }
    }
}
