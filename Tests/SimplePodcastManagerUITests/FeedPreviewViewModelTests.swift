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

    @Test
    func refreshSingleSubscriptionReplacesOnlyThatSubscription() async throws {
        let firstSubscription = FeedSubscription(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "First",
            rssURL: URL(string: "https://example.com/first.xml")!
        )
        let secondSubscription = FeedSubscription(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            title: "Second",
            rssURL: URL(string: "https://example.com/second.xml")!
        )
        let service = SequencedFeedService(results: [
            FeedFetchResult(
                allEpisodes: [
                    makeEpisode(id: "first-old", subscription: firstSubscription, title: "First Old"),
                    makeEpisode(id: "second-old", subscription: secondSubscription, title: "Second Old"),
                ],
                selectedEpisodes: [
                    makeEpisode(id: "first-old", subscription: firstSubscription, title: "First Old"),
                    makeEpisode(id: "second-old", subscription: secondSubscription, title: "Second Old"),
                ],
                feedSummaries: [
                    FeedSummary(subscriptionID: firstSubscription.id, title: "First Old"),
                    FeedSummary(subscriptionID: secondSubscription.id, title: "Second Old"),
                ]
            ),
            FeedFetchResult(
                allEpisodes: [
                    makeEpisode(id: "first-new", subscription: firstSubscription, title: "First New"),
                ],
                selectedEpisodes: [
                    makeEpisode(id: "first-new", subscription: firstSubscription, title: "First New"),
                ],
                feedSummaries: [
                    FeedSummary(subscriptionID: firstSubscription.id, title: "First New"),
                ]
            ),
        ])
        let viewModel = FeedPreviewViewModel(service: service)

        await viewModel.refreshPreview(for: [firstSubscription, secondSubscription])
        await viewModel.refreshPreview(for: firstSubscription)

        #expect(service.requestedSubscriptionIDs == [
            [firstSubscription.id, secondSubscription.id],
            [firstSubscription.id],
        ])
        #expect(viewModel.allEpisodes.map(\.title) == ["First New", "Second Old"])
        #expect(viewModel.selectedEpisodes.map(\.title) == ["First New", "Second Old"])
        #expect(viewModel.feedSummaries[firstSubscription.id]?.title == "First New")
        #expect(viewModel.feedSummaries[secondSubscription.id]?.title == "Second Old")
    }

    private func makeEpisode(id: String, subscription: FeedSubscription, title: String) -> Episode {
        Episode(
            id: id,
            subscriptionID: subscription.id,
            podcastTitle: subscription.title,
            title: title,
            publicationDate: Date(timeIntervalSince1970: id.contains("old") ? 1 : 2),
            enclosureURL: URL(string: "https://cdn.example.com/\(id).mp3")!,
            sourceFeedURL: subscription.rssURL
        )
    }
}

private struct MockFeedService: FeedService {
    let result: FeedFetchResult

    func fetchLatestEpisodes(for subscriptions: [FeedSubscription]) async throws -> FeedFetchResult {
        result
    }
}

private final class SequencedFeedService: FeedService, @unchecked Sendable {
    private var results: [FeedFetchResult]
    private(set) var requestedSubscriptionIDs: [[UUID]] = []

    init(results: [FeedFetchResult]) {
        self.results = results
    }

    func fetchLatestEpisodes(for subscriptions: [FeedSubscription]) async throws -> FeedFetchResult {
        requestedSubscriptionIDs.append(subscriptions.map(\.id))
        return results.removeFirst()
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
