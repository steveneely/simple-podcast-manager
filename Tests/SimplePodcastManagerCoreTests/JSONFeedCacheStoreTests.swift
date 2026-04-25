import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct JSONFeedCacheStoreTests {
    @Test
    func savesAndLoadsCachedFeedRoundTrip() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "SimplePodcastManagerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = JSONFeedCacheStore(directoryURL: directoryURL)
        let subscriptionID = UUID()
        let rssURL = URL(string: "https://example.com/feed.xml")!
        let subscription = FeedSubscription(id: subscriptionID, title: "Example", rssURL: rssURL)
        let cachedFeed = CachedFeed(
            subscriptionID: subscriptionID,
            rssURL: rssURL,
            fetchedAt: Date(timeIntervalSince1970: 1_713_713_388),
            etag: "\"abc123\"",
            lastModified: "Wed, 24 Apr 2026 12:00:00 GMT",
            summary: FeedSummary(
                subscriptionID: subscriptionID,
                title: "Example",
                artworkURL: URL(string: "https://example.com/artwork.jpg"),
                description: "Cached description."
            ),
            episodes: [
                Episode(
                    id: "ep-1",
                    subscriptionID: subscriptionID,
                    podcastTitle: "Example",
                    title: "Episode 1",
                    publicationDate: Date(timeIntervalSince1970: 1_713_713_388),
                    enclosureURL: URL(string: "https://cdn.example.com/ep1.mp3")!,
                    sourceFeedURL: rssURL
                )
            ]
        )

        try store.saveCachedFeed(cachedFeed)

        #expect(try store.loadCachedFeed(for: subscription) == cachedFeed)
    }

    @Test
    func ignoresCachedFeedForDifferentURL() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "SimplePodcastManagerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = JSONFeedCacheStore(directoryURL: directoryURL)
        let subscriptionID = UUID()
        try store.saveCachedFeed(
            CachedFeed(
                subscriptionID: subscriptionID,
                rssURL: URL(string: "https://example.com/old.xml")!,
                fetchedAt: Date(),
                summary: FeedSummary(subscriptionID: subscriptionID, title: "Old"),
                episodes: []
            )
        )

        let subscription = FeedSubscription(
            id: subscriptionID,
            title: "Example",
            rssURL: URL(string: "https://example.com/new.xml")!
        )

        #expect(try store.loadCachedFeed(for: subscription) == nil)
    }

    @Test
    func deletesCachedFeed() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "SimplePodcastManagerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = JSONFeedCacheStore(directoryURL: directoryURL)
        let subscriptionID = UUID()
        let subscription = FeedSubscription(
            id: subscriptionID,
            title: "Example",
            rssURL: URL(string: "https://example.com/feed.xml")!
        )
        try store.saveCachedFeed(
            CachedFeed(
                subscriptionID: subscriptionID,
                rssURL: subscription.rssURL,
                fetchedAt: Date(),
                summary: FeedSummary(subscriptionID: subscriptionID, title: "Example"),
                episodes: []
            )
        )

        try store.deleteCachedFeed(for: subscriptionID)

        #expect(try store.loadCachedFeed(for: subscription) == nil)
    }
}
