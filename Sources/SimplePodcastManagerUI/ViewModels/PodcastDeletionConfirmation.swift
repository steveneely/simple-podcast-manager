import Foundation
import SimplePodcastManagerCore

struct PodcastDeletionConfirmation: Equatable {
    let subscriptionIDs: [PodcastSubscription.ID]
    let title: String
    let message: String
    let cancelButtonTitle = "Cancel"
    let deleteButtonTitle: String

    init(subscriptions: [PodcastSubscription], localDownloadCount: Int = 0) {
        subscriptionIDs = subscriptions.map(\.id)
        let localDownloadMessage = localDownloadCount > 0
            ? "\n\nThis will also delete \(localDownloadCount) downloaded episode\(localDownloadCount == 1 ? "" : "s") stored on this Mac."
            : ""
        let deviceMessage = "\n\nEpisodes already copied to a device will not be deleted."

        if subscriptions.count == 1, let subscription = subscriptions.first {
            title = "Delete Podcast?"
            message = "Are you sure you want to delete “\(subscription.title)”?\(localDownloadMessage)\(deviceMessage)"
            deleteButtonTitle = "Delete Podcast"
        } else {
            title = "Delete Podcasts?"
            message = "Are you sure you want to delete these \(subscriptions.count) podcasts?\(localDownloadMessage)\(deviceMessage)"
            deleteButtonTitle = "Delete Podcasts"
        }
    }
}
