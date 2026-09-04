import Foundation
import SimplePodcastManagerCore

struct FeedDeletionConfirmation: Equatable {
    let subscriptionIDs: [FeedSubscription.ID]
    let title: String
    let message: String
    let cancelButtonTitle = "Cancel"
    let deleteButtonTitle: String

    init(subscriptions: [FeedSubscription], localDownloadCount: Int = 0) {
        subscriptionIDs = subscriptions.map(\.id)
        let localDownloadMessage = localDownloadCount > 0
            ? "\n\nThis will also delete \(localDownloadCount) downloaded episode\(localDownloadCount == 1 ? "" : "s") stored on this Mac."
            : ""
        let deviceMessage = "\n\nEpisodes already copied to a device will not be deleted."

        if subscriptions.count == 1, let subscription = subscriptions.first {
            title = "Delete Podcast Feed?"
            message = "Are you sure you want to delete “\(subscription.title)”?\(localDownloadMessage)\(deviceMessage)"
            deleteButtonTitle = "Delete Feed"
        } else {
            title = "Delete Podcast Feeds?"
            message = "Are you sure you want to delete these \(subscriptions.count) podcast feeds?\(localDownloadMessage)\(deviceMessage)"
            deleteButtonTitle = "Delete Feeds"
        }
    }
}
