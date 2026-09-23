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
        let isSinglePodcast = subscriptions.count == 1
        let subject = isSinglePodcast ? "“\(subscriptions[0].title)”" : "these \(subscriptions.count) podcasts"
        let possessive = isSinglePodcast ? "its" : "their"
        let hasPlaylistChanges = playlistEntryCount > 0 || automaticPlaylistCount > 0
        let podcastNoun = isSinglePodcast ? "the podcast" : "the podcasts"
        let effects: String
        if localDownloadCount > 0 {
            let downloads = "\(possessive) \(localDownloadCount) downloaded episode\(localDownloadCount == 1 ? "" : "s")"
            effects = " also removes \(downloads)" + (hasPlaylistChanges ? " and excludes \(podcastNoun) from playlists" : "")
        } else if hasPlaylistChanges {
            effects = " excludes \(podcastNoun) from playlists"
        } else {
            effects = " removes \(isSinglePodcast ? "it" : "them") from your library"
        }

        title = ""
        message = "Deleting \(subject)\(effects).\n\nEpisodes already copied to your device will remain."
        deleteButtonTitle = isSinglePodcast ? "Delete Podcast" : "Delete Podcasts"
    }
}
