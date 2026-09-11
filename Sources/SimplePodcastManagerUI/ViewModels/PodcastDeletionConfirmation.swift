import Foundation
import SimplePodcastManagerCore

struct PodcastDeletionConfirmation: Equatable {
    let subscriptionIDs: [PodcastSubscription.ID]
    let title: String
    let message: String
    let cancelButtonTitle = "Cancel"
    let deleteButtonTitle: String

    init(
        subscriptions: [PodcastSubscription],
        localDownloadCount: Int = 0,
        playlistEntryCount: Int = 0,
        automaticPlaylistCount: Int = 0
    ) {
        subscriptionIDs = subscriptions.map(\.id)
        let localDownloadMessage = localDownloadCount > 0
            ? "\n\nThis will also delete \(localDownloadCount) downloaded episode\(localDownloadCount == 1 ? "" : "s") stored on this Mac."
            : ""
        let deviceMessage = "\n\nEpisodes already copied to a device will not be deleted."
        let playlistMessage = playlistEntryCount > 0
            ? "\n\nThis will also remove \(playlistEntryCount) episode entr\(playlistEntryCount == 1 ? "y" : "ies") from your playlists."
            : ""
        let automaticPlaylistMessage = automaticPlaylistCount > 0
            ? "\n\nThis will also update automatic additions in \(automaticPlaylistCount) playlist\(automaticPlaylistCount == 1 ? "" : "s")."
            : ""

        if subscriptions.count == 1, let subscription = subscriptions.first {
            title = "Delete Podcast?"
            message = "Are you sure you want to delete “\(subscription.title)”?\(localDownloadMessage)\(playlistMessage)\(automaticPlaylistMessage)\(deviceMessage)"
            deleteButtonTitle = "Delete Podcast"
        } else {
            title = "Delete Podcasts?"
            message = "Are you sure you want to delete these \(subscriptions.count) podcasts?\(localDownloadMessage)\(playlistMessage)\(automaticPlaylistMessage)\(deviceMessage)"
            deleteButtonTitle = "Delete Podcasts"
        }
    }
}
