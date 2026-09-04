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

        let confirmation = FeedDeletionConfirmation(
            subscriptions: [subscription],
            localDownloadCount: 2
        )

        #expect(confirmation.subscriptionIDs == [subscription.id])
        #expect(confirmation.title == "Delete Podcast Feed?")
        #expect(confirmation.message == """
        Are you sure you want to delete “Connected”?

        This will also delete 2 downloaded episodes stored on this Mac.

        Episodes already copied to a device will not be deleted.
        """)
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
        #expect(confirmation.message == """
        Are you sure you want to delete these 2 podcast feeds?

        Episodes already copied to a device will not be deleted.
        """)
        #expect(confirmation.deleteButtonTitle == "Delete Feeds")
    }
}
