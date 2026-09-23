import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

struct PodcastDeletionConfirmationTests {
    @Test(arguments: [0, 1, 2])
    func onlyMentionsApplicablePlaylistChanges(kind: Int) {
        let podcast = PodcastSubscription(title: "News", rssURL: URL(string: "https://example.com/rss")!)
        let confirmation = PodcastDeletionConfirmation(
            subscriptions: [podcast], localDownloadCount: 1,
            playlistEntryCount: kind == 1 ? 2 : 0,
            automaticPlaylistCount: kind == 2 ? 1 : 0
        )
        let playlistText = kind == 0 ? "" : " and excludes the podcast from playlists"
        #expect(confirmation.title.isEmpty)
        #expect(confirmation.message == "Deleting “News” also removes its 1 downloaded episode\(playlistText).\n\nEpisodes already copied to your device will remain.")
    }

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
        #expect(confirmation.title.isEmpty)
        #expect(confirmation.message == """
        Deleting “Connected” also removes its 2 downloaded episodes.

        Episodes already copied to your device will remain.
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
        #expect(confirmation.title.isEmpty)
        #expect(confirmation.message == """
        Deleting these 2 podcasts removes them from your library.

        Episodes already copied to your device will remain.
        """)
        #expect(confirmation.deleteButtonTitle == "Delete Podcasts")
    }

    @Test
    func describesUpdatingAutomaticPlaylists() {
        let subscription = PodcastSubscription(
            title: "Connected",
            rssURL: URL(string: "https://relay.fm/connected/feed")!
        )

        let confirmation = PodcastDeletionConfirmation(
            subscriptions: [subscription],
            playlistEntryCount: 1,
            automaticPlaylistCount: 2
        )

        #expect(confirmation.message == """
        Deleting “Connected” excludes the podcast from playlists.

        Episodes already copied to your device will remain.
        """)
    }
}
