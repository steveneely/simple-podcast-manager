import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

struct FeedEditorPresentationTests {
    @Test
    func editingSubscriptionCarriesItsFeedURLIntoThePresentedDraft() throws {
        let feedURL = try #require(URL(string: "https://example.com/podcast/feed.xml"))
        let subscription = FeedSubscription(title: "Example Podcast", rssURL: feedURL)

        let presentation = FeedEditorPresentation(subscription: subscription)

        #expect(presentation.draft.id == subscription.id)
        #expect(presentation.draft.rssURLString == feedURL.absoluteString)
    }
}
