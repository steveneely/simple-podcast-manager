import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

struct PodcastDeletionConfirmationTests {
    @Test
    func namesThePodcastAndRequiresAnExplicitDelete() {
        let subscription = PodcastSubscription(
            title: "Connected",
            rssURL: URL(string: "https://relay.fm/connected/feed")!
        )

        let confirmation = PodcastDeletionConfirmation(
            subscriptions: [subscription],
            localDownloadCount: 2
        )

        #expect(confirmation.subscriptionIDs == [subscription.id])
        #expect(confirmation.title == "Delete Podcast?")
        #expect(confirmation.message == """
        Are you sure you want to delete “Connected”?

        This will also delete 2 downloaded episodes stored on this Mac.

        Episodes already copied to a device will not be deleted.
        """)
        #expect(confirmation.cancelButtonTitle == "Cancel")
        #expect(confirmation.deleteButtonTitle == "Delete Podcast")
    }

    @Test
    func describesDeletingMultiplePodcasts() {
        let subscriptions = [
            PodcastSubscription(title: "Connected", rssURL: URL(string: "https://relay.fm/connected/feed")!),
            PodcastSubscription(title: "ATP", rssURL: URL(string: "https://atp.fm/rss")!),
        ]

        let confirmation = PodcastDeletionConfirmation(subscriptions: subscriptions)

        #expect(confirmation.subscriptionIDs == subscriptions.map(\.id))
        #expect(confirmation.title == "Delete Podcasts?")
        #expect(confirmation.message == """
        Are you sure you want to delete these 2 podcasts?

        Episodes already copied to a device will not be deleted.
        """)
        #expect(confirmation.deleteButtonTitle == "Delete Podcasts")
    }
}
