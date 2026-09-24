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
                Button {
                    onTogglePlaylist(playlist)
                } label: {
                    switch playlistIndicator.membership(for: playlist.id) {
                    case .manual:
                        Label(playlist.name, systemImage: "checkmark")
                    case .automatic:
                        Label(
                            "\(playlist.name) — Automatically added",
                            systemImage: "gearshape"
                        )
                    case .none:
                        Text(playlist.name)
                    }
                }
            }
        }
    }
}
