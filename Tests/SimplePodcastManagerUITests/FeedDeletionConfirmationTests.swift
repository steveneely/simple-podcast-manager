import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

struct FeedDeletionConfirmationTests {
    @Test
    func namesThePodcastAndRequiresAnExplicitDelete() {
        let subscription = FeedSubscription(
            title: "Connected",
            rssURL: URL(string: "https://relay.fm/connected/feed")!
        )

        let confirmation = FeedDeletionConfirmation(subscriptions: [subscription])

        #expect(confirmation.subscriptionIDs == [subscription.id])
        #expect(confirmation.title == "Delete Podcast Feed?")
        #expect(confirmation.message.contains("“Connected”"))
        #expect(confirmation.cancelButtonTitle == "Cancel")
        #expect(confirmation.deleteButtonTitle == "Delete Feed")
    }

    @Test
    func describesDeletingMultipleFeeds() {
        let subscriptions = [
            FeedSubscription(title: "Connected", rssURL: URL(string: "https://relay.fm/connected/feed")!),
            FeedSubscription(title: "ATP", rssURL: URL(string: "https://atp.fm/rss")!),
        ]

        let confirmation = FeedDeletionConfirmation(subscriptions: subscriptions)

        #expect(confirmation.subscriptionIDs == subscriptions.map(\.id))
        #expect(confirmation.title == "Delete Podcast Feeds?")
        #expect(confirmation.message.contains("these 2 podcast feeds"))
        #expect(confirmation.deleteButtonTitle == "Delete Feeds")
    }
}
