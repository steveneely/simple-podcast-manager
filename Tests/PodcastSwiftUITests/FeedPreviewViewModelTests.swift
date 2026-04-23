import Foundation
import Testing
@testable import PodcastSwiftCore
@testable import PodcastSwiftUI

@MainActor
struct FeedPreviewViewModelTests {
    @Test
    func refreshPreviewLoadsEpisodesAndFailures() async throws {
        let viewModel = FeedPreviewViewModel(
            service: MockFeedService(
                result: FeedFetchResult(
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
                    ]
                )
            )
        )

        await viewModel.refreshPreview(for: [])

        #expect(viewModel.selectedEpisodes.count == 1)
        #expect(viewModel.failures.count == 1)
        #expect(viewModel.lastErrorMessage == nil)
    }
}

private struct MockFeedService: FeedService {
    let result: FeedFetchResult

    func fetchLatestEpisodes(for subscriptions: [FeedSubscription]) async throws -> FeedFetchResult {
        result
    }
}
