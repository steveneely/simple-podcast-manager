import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

@MainActor
struct PodcastPreviewViewModelTests {
    @Test
    func refreshPreviewLoadsEpisodesAndFailures() async throws {
        let subscriptionID = UUID()
        let viewModel = PodcastPreviewViewModel(
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
                    failures: [
                        FeedFetchFailure(
                            subscriptionID: UUID(),
                            subscriptionTitle: "Broken Feed",
                            message: "The RSS feed data could not be parsed."
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
        #expect(viewModel.failures.count == 1)
        #expect(viewModel.episodes(for: subscriptionID).map(\.id) == ["ep-1"])
        #expect(viewModel.failures(for: viewModel.failures[0].subscriptionID).count == 1)
        #expect(viewModel.artworkURL(for: subscriptionID) == URL(string: "https://cdn.example.com/artwork.jpg"))
        #expect(viewModel.lastErrorMessage == nil)
    }

    @Test
    func loadCachedPreviewLoadsPersistedEpisodesAndSummary() async throws {
        let subscriptionID = UUID()
        let rssURL = URL(string: "https://example.com/feed.xml")!
        let subscription = PodcastSubscription(id: subscriptionID, title: "Example", rssURL: rssURL)
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
        let viewModel = PodcastPreviewViewModel(service: MockFeedService(result: FeedFetchResult()), cacheStore: store)

        await viewModel.loadCachedPreview(for: [subscription])

        #expect(viewModel.allEpisodes.map(\.title) == ["Cached Episode"])
        #expect(viewModel.episodes(for: subscriptionID).map(\.title) == ["Cached Episode"])
        #expect(viewModel.artworkURL(for: subscriptionID) == URL(string: "https://cdn.example.com/artwork.jpg"))
        #expect(viewModel.description(for: subscriptionID) == "Cached description.")
    }

    @Test
    func refreshSingleSubscriptionReplacesOnlyThatSubscription() async throws {
        let firstSubscription = PodcastSubscription(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "First",
            rssURL: URL(string: "https://example.com/first.xml")!
        )
        let secondSubscription = PodcastSubscription(
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
                feedSummaries: [
                    FeedSummary(subscriptionID: firstSubscription.id, title: "First Old"),
                    FeedSummary(subscriptionID: secondSubscription.id, title: "Second Old"),
                ]
            ),
            FeedFetchResult(
                allEpisodes: [
                    makeEpisode(id: "first-new", subscription: firstSubscription, title: "First New"),
                ],
                feedSummaries: [
                    FeedSummary(subscriptionID: firstSubscription.id, title: "First New"),
                ]
            ),
        ])
        let viewModel = PodcastPreviewViewModel(service: service)

        await viewModel.refreshPreview(for: [firstSubscription, secondSubscription])
        await viewModel.refreshPreview(for: firstSubscription)

        #expect(service.requestedSubscriptionIDs == [
            [firstSubscription.id, secondSubscription.id],
            [firstSubscription.id],
        ])
        #expect(viewModel.allEpisodes.map(\.title) == ["First New", "Second Old"])
        #expect(viewModel.feedSummaries[firstSubscription.id]?.title == "First New")
        #expect(viewModel.feedSummaries[secondSubscription.id]?.title == "Second Old")
    }

    @Test
    func refreshNewSubscriptionsFetchesBatchAndPreservesExistingPreviewData() async throws {
        let existingSubscription = PodcastSubscription(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "Existing",
            rssURL: URL(string: "https://example.com/existing.xml")!
        )
        let firstNewSubscription = PodcastSubscription(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            title: "First New",
            rssURL: URL(string: "https://example.com/first-new.xml")!
        )
        let secondNewSubscription = PodcastSubscription(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            title: "Second New",
            rssURL: URL(string: "https://example.com/second-new.xml")!
        )
        let service = SequencedFeedService(results: [
            FeedFetchResult(
                allEpisodes: [makeEpisode(id: "existing-old", subscription: existingSubscription, title: "Existing Episode")],
                feedSummaries: [FeedSummary(subscriptionID: existingSubscription.id, title: "Existing")]
            ),
            FeedFetchResult(
                allEpisodes: [
                    makeEpisode(id: "first-new", subscription: firstNewSubscription, title: "First Episode"),
                    makeEpisode(id: "second-new", subscription: secondNewSubscription, title: "Second Episode"),
                ],
                feedSummaries: [
                    FeedSummary(subscriptionID: firstNewSubscription.id, title: "First New"),
                    FeedSummary(subscriptionID: secondNewSubscription.id, title: "Second New"),
                ]
            ),
        ])
        let viewModel = PodcastPreviewViewModel(service: service)

        await viewModel.refreshPreview(for: [existingSubscription])
        await viewModel.refreshPreview(forNewSubscriptions: [firstNewSubscription, secondNewSubscription])

        #expect(service.requestedSubscriptionIDs == [
            [existingSubscription.id],
            [firstNewSubscription.id, secondNewSubscription.id],
        ])
        #expect(Set(viewModel.allEpisodes.map(\.title)) == ["Existing Episode", "First Episode", "Second Episode"])
        #expect(viewModel.feedSummaries[existingSubscription.id]?.title == "Existing")
    }

    @Test
    func indexedEpisodeLookupPerformanceComparison() async throws {
        guard ProcessInfo.processInfo.environment["SPM_RUN_PERFORMANCE_TESTS"] == "1" else { return }
        let subscriptions = (0..<50).map { number in
            PodcastSubscription(
                title: "Podcast \(number)",
                rssURL: URL(string: "https://example.com/feed-\(number).xml")!
            )
        }
        let cachedFeeds = Dictionary(uniqueKeysWithValues: subscriptions.map { subscription in
            let episodes = (0..<100).map { episodeNumber in
                makeEpisode(
                    id: "\(subscription.id)-\(episodeNumber)",
                    subscription: subscription,
                    title: "Episode \(episodeNumber)"
                )
            }
            return (
                subscription.id,
                CachedFeed(
                    subscriptionID: subscription.id,
                    rssURL: subscription.rssURL,
                    fetchedAt: Date(timeIntervalSince1970: 1),
                    summary: FeedSummary(subscriptionID: subscription.id, title: subscription.title),
                    episodes: episodes
                )
            )
        })
        let viewModel = PodcastPreviewViewModel(
            service: MockFeedService(result: FeedFetchResult()),
            cacheStore: InMemoryFeedCacheStore(cachedFeeds: cachedFeeds)
        )
        await viewModel.loadCachedPreview(for: subscriptions)

        let clock = ContinuousClock()
        var linearCount = 0
        let linearDuration = clock.measure {
            for _ in 0..<20 {
                for subscription in subscriptions {
                    linearCount += viewModel.allEpisodes.filter { $0.subscriptionID == subscription.id }.count
                }
            }
        }
        var indexedCount = 0
        let indexedDuration = clock.measure {
            for _ in 0..<20 {
                for subscription in subscriptions {
                    indexedCount += viewModel.episodes(for: subscription.id).count
                }
            }
        }

        print("Episode lookup benchmark — linear: \(linearDuration), indexed: \(indexedDuration)")
        #expect(indexedCount == linearCount)
        #expect(indexedDuration < linearDuration)
    }

    private func makeEpisode(id: String, subscription: PodcastSubscription, title: String) -> Episode {
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

    func fetchLatestEpisodes(for subscriptions: [PodcastSubscription]) async throws -> FeedFetchResult {
        result
    }
}

private final class SequencedFeedService: FeedService, @unchecked Sendable {
    private var results: [FeedFetchResult]
    private(set) var requestedSubscriptionIDs: [[UUID]] = []

    init(results: [FeedFetchResult]) {
        self.results = results
    }

    func fetchLatestEpisodes(for subscriptions: [PodcastSubscription]) async throws -> FeedFetchResult {
        requestedSubscriptionIDs.append(subscriptions.map(\.id))
        return results.removeFirst()
    }
}

private final class InMemoryFeedCacheStore: FeedCacheStore, @unchecked Sendable {
    var cachedFeeds: [UUID: CachedFeed]

    init(cachedFeeds: [UUID: CachedFeed] = [:]) {
        self.cachedFeeds = cachedFeeds
    }

    func loadCachedFeed(for subscription: PodcastSubscription) throws -> CachedFeed? {
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
