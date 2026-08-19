import Foundation
import SimplePodcastManagerCore

struct FeedDeletionConfirmation: Equatable {
    let subscriptionIDs: [FeedSubscription.ID]
    let title: String
    let message: String
    let cancelButtonTitle = "Cancel"
    let deleteButtonTitle: String

    init(subscriptions: [FeedSubscription]) {
        subscriptionIDs = subscriptions.map(\.id)

        if subscriptions.count == 1, let subscription = subscriptions.first {
            title = "Delete Podcast Feed?"
            message = "Are you sure you want to delete “\(subscription.title)” from Simple Podcast Manager?"
            deleteButtonTitle = "Delete Feed"
        } else {
            title = "Delete Podcast Feeds?"
            message = "Are you sure you want to delete these \(subscriptions.count) podcast feeds from Simple Podcast Manager?"
            deleteButtonTitle = "Delete Feeds"
        }
    }
}
