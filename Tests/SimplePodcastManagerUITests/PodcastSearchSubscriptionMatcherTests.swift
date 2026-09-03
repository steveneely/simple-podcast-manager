import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

struct PodcastSearchSubscriptionMatcherTests {
    @Test
    func matchesAnExistingFeedAcrossCommonURLAliases() throws {
        let matcher = PodcastSearchSubscriptionMatcher(
            subscriptions: [
                FeedSubscription(
                    title: "Existing Show",
                    rssURL: try #require(URL(string: "https://feeds.example.com/show/"))
                )
            ]
        )
        let result = PodcastSearchResult(
            title: "Different Directory Title",
            feedURL: try #require(URL(string: "http://feeds.example.com/show"))
        )

        #expect(matcher.isSubscribed(result))
    }

    @Test
    func matchesAnExistingTitleWhenDirectoryURLsDiffer() throws {
        let matcher = PodcastSearchSubscriptionMatcher(
            subscriptions: [
                FeedSubscription(
                    title: "Café   Conversations",
                    rssURL: try #require(URL(string: "https://publisher.example.com/feed"))
                )
            ]
        )
        let result = PodcastSearchResult(
            title: "cafe conversations",
            feedURL: try #require(URL(string: "https://directory.example.com/feed"))
        )

        #expect(matcher.isSubscribed(result))
    }

    @Test
    func allowsAResultWithADifferentURLAndTitle() throws {
        let matcher = PodcastSearchSubscriptionMatcher(
            subscriptions: [
                FeedSubscription(
                    title: "Existing Show",
                    rssURL: try #require(URL(string: "https://feeds.example.com/existing"))
                )
            ]
        )
        let result = PodcastSearchResult(
            title: "New Show",
            feedURL: try #require(URL(string: "https://feeds.example.com/new"))
        )

        #expect(!matcher.isSubscribed(result))
    }
}
