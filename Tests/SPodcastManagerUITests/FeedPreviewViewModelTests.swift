import Foundation
import Testing
@testable import SPodcastManagerCore
@testable import SPodcastManagerUI

@MainActor
struct FeedPreviewViewModelTests {
    @Test
    func refreshPreviewLoadsEpisodesAndFailures() async throws {
        let viewModel = FeedPreviewViewModel(
            service: MockFeedService(
                result: FeedFetchResult(
                    allEpisodes: [
                        Episode(
                            id: "ep-1",
                            subscriptionID: UUID(),
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
                            subscriptionID: UUID(),
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
                            subscriptionID: UUID(uuidString: "A267D8AC-6904-43C7-96A8-8B58A36A5E50")!,
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
        #expect(viewModel.artworkURL(for: UUID(uuidString: "A267D8AC-6904-43C7-96A8-8B58A36A5E50")!) == URL(string: "https://cdn.example.com/artwork.jpg"))
        #expect(viewModel.lastErrorMessage == nil)
    }
}

private struct MockFeedService: FeedService {
    let result: FeedFetchResult

    func fetchLatestEpisodes(for subscriptions: [FeedSubscription]) async throws -> FeedFetchResult {
        result
    }
}
