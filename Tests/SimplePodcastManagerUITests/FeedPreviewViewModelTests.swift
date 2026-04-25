import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

@MainActor
struct FeedPreviewViewModelTests {
    @Test
    func refreshPreviewLoadsEpisodesAndFailures() async throws {
        let subscriptionID = UUID()
        let viewModel = FeedPreviewViewModel(
            service: MockFeedService(
                result: FeedFetchResult(
                    allEpisodes: [
                        Episode(
                            id: "ep-1",
                            subscriptionID: subscriptionID,
                            podcastTitle: "Example Podcast",
                            title: "Episode 1",
                            publicationDate: Date(timeIntervalSince1970: 1_713_713_388),
                            enclosureURL: URL(string: "https://cdn.example.com/ep1.mp3")!,
                            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
                        )
                    ],
                    selectedEpisodes: [
                        Episode(
                            id: "ep-1",
                            subscriptionID: subscriptionID,
                            podcastTitle: "Example Podcast",
                            title: "Episode 1",
                            publicationDate: Date(timeIntervalSince1970: 1_713_713_388),
                            enclosureURL: URL(string: "https://cdn.example.com/ep1.mp3")!,
                            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
                        )
                    ],
                    failures: [
                        FeedFetchFailure(
                            subscriptionID: UUID(),
                            subscriptionTitle: "Broken Feed",
                            message: "The feed data could not be parsed."
                        )
                    ],
                    feedSummaries: [
                        FeedSummary(
                            subscriptionID: subscriptionID,
                            title: "Example Podcast",
                            artworkURL: URL(string: "https://cdn.example.com/artwork.jpg")
                        )
                    ]
                )
            )
        )

        await viewModel.refreshPreview(for: [])

        #expect(viewModel.allEpisodes.count == 1)
        #expect(viewModel.selectedEpisodes.count == 1)
        #expect(viewModel.failures.count == 1)
        #expect(viewModel.artworkURL(for: subscriptionID) == URL(string: "https://cdn.example.com/artwork.jpg"))
        #expect(viewModel.lastErrorMessage == nil)
    }

    @Test
    func loadCachedPreviewLoadsPersistedEpisodesAndSummary() throws {
        let subscriptionID = UUID()
        let rssURL = URL(string: "https://example.com/feed.xml")!
        let subscription = FeedSubscription(id: subscriptionID, title: "Example", rssURL: rssURL)
        let store = InMemoryFeedCacheStore(
            cachedFeeds: [
                subscriptionID: CachedFeed(
                    subscriptionID: subscriptionID,
                    rssURL: rssURL,
                    fetchedAt: Date(timeIntervalSince1970: 1_713_713_388),
                    summary: FeedSummary(
                        subscriptionID: subscriptionID,
                        title: "Cached Example",
                        artworkURL: URL(string: "https://cdn.example.com/artwork.jpg"),
                        description: "Cached description."
                    ),
                    episodes: [
                        Episode(
                            id: "ep-1",
                            subscriptionID: subscriptionID,
                            podcastTitle: "Cached Example",
                            title: "Cached Episode",
                            publicationDate: Date(timeIntervalSince1970: 1_713_713_388),
                            enclosureURL: URL(string: "https://cdn.example.com/ep1.mp3")!,
                            sourceFeedURL: rssURL
                        )
                    ]
                )
            ]
        )
        let viewModel = FeedPreviewViewModel(service: MockFeedService(result: FeedFetchResult(selectedEpisodes: [])), cacheStore: store)

        viewModel.loadCachedPreview(for: [subscription])

        #expect(viewModel.allEpisodes.map(\.title) == ["Cached Episode"])
        #expect(viewModel.selectedEpisodes.map(\.title) == ["Cached Episode"])
        #expect(viewModel.artworkURL(for: subscriptionID) == URL(string: "https://cdn.example.com/artwork.jpg"))
        #expect(viewModel.description(for: subscriptionID) == "Cached description.")
    }
}

private struct MockFeedService: FeedService {
    let result: FeedFetchResult

    func fetchLatestEpisodes(for subscriptions: [FeedSubscription]) async throws -> FeedFetchResult {
        result
    }
}

private final class InMemoryFeedCacheStore: FeedCacheStore, @unchecked Sendable {
    var cachedFeeds: [UUID: CachedFeed]

    init(cachedFeeds: [UUID: CachedFeed] = [:]) {
        self.cachedFeeds = cachedFeeds
    }

    func loadCachedFeed(for subscription: FeedSubscription) throws -> CachedFeed? {
        guard let cachedFeed = cachedFeeds[subscription.id], cachedFeed.rssURL == subscription.rssURL else {
            return nil
        }
        return cachedFeed
    }

    func saveCachedFeed(_ cachedFeed: CachedFeed) throws {
        cachedFeeds[cachedFeed.subscriptionID] = cachedFeed
    }

    func deleteCachedFeed(for subscriptionID: UUID) throws {
        cachedFeeds[subscriptionID] = nil
    }
}
