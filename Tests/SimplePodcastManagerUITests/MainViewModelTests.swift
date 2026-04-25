import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

@MainActor
struct MainViewModelTests {
    @Test
    func loadReflectsStoredConfiguration() throws {
        let store = InMemoryConfigurationStore(
            configuration: AppConfiguration(
                settings: AppSettings(
                    ffmpegExecutablePath: "/usr/local/bin/ffmpeg"
                ),
                feedSubscriptions: [
                    FeedSubscription(title: "ATP", rssURL: URL(string: "https://atp.fm/rss")!)
                ]
            )
        )
        let viewModel = MainViewModel(store: store)

        viewModel.load()

        #expect(viewModel.hasLoadedConfiguration)
        #expect(viewModel.feedSubscriptions.count == 1)
        #expect(viewModel.settings.ffmpegExecutablePath == "/usr/local/bin/ffmpeg")
    }

    @Test
    func addUpdateAndRemoveFeedPersistThroughStore() async throws {
        let store = InMemoryConfigurationStore()
        let viewModel = MainViewModel(
            store: store,
            metadataResolver: MockFeedMetadataResolver(
                summariesByURL: [
                    "https://relay.fm/connected/feed": FeedSummary(
                        subscriptionID: UUID(),
                        title: "Connected",
                        artworkURL: URL(string: "https://relay.fm/connected.png"),
                        description: "A show about connected things."
                    )
                ]
            )
        )

        try await viewModel.addFeed(
            from: FeedDraft(
                rssURLString: "https://relay.fm/connected/feed"
            )
        )

        #expect(viewModel.feedSubscriptions.count == 1)
        #expect(store.configuration.feedSubscriptions.count == 1)

        let existingSubscription = try #require(viewModel.feedSubscriptions.first)
        try await viewModel.updateFeed(
            from: FeedDraft(
                id: existingSubscription.id,
                rssURLString: "https://relay.fm/connected/feed",
                artworkURL: existingSubscription.artworkURL,
                currentTitle: existingSubscription.title,
                isEnabled: false
            )
        )

        #expect(viewModel.feedSubscriptions.first?.title == "Connected")
        #expect(viewModel.feedSubscriptions.first?.description == "A show about connected things.")
        #expect(viewModel.feedSubscriptions.first?.retentionPolicy.episodeLimit == .max)
        #expect(viewModel.feedSubscriptions.first?.isEnabled == false)

        viewModel.removeFeeds(at: IndexSet(integer: 0))

        #expect(viewModel.feedSubscriptions.isEmpty)
        #expect(store.configuration.feedSubscriptions.isEmpty)
    }

    @Test
    func settingsMutationsPersist() throws {
        let store = InMemoryConfigurationStore()
        let viewModel = MainViewModel(store: store)

        viewModel.replaceSettings(
            AppSettings(
                ffmpegExecutablePath: "/opt/homebrew/bin/ffmpeg"
            )
        )

        #expect(viewModel.settings.ffmpegExecutablePath == "/opt/homebrew/bin/ffmpeg")
        #expect(store.configuration.settings == viewModel.settings)
    }

    @Test
    func applyFeedSummariesUpdatesStoredMetadata() throws {
        let subscriptionID = UUID(uuidString: "7B9FEA54-E516-4B39-8156-5B83D0B96768")!
        let store = InMemoryConfigurationStore(
            configuration: AppConfiguration(
                feedSubscriptions: [
                    FeedSubscription(
                        id: subscriptionID,
                        title: "Old Title",
                        rssURL: URL(string: "https://example.com/feed.xml")!
                    )
                ]
            )
        )
        let viewModel = MainViewModel(store: store)

        viewModel.load()
        viewModel.applyFeedSummaries([
            FeedSummary(
                subscriptionID: subscriptionID,
                title: "New Title",
                artworkURL: URL(string: "https://example.com/artwork.jpg"),
                description: "Fresh feed description."
            )
        ])

        #expect(viewModel.feedSubscriptions.first?.title == "New Title")
        #expect(viewModel.feedSubscriptions.first?.artworkURL == URL(string: "https://example.com/artwork.jpg"))
        #expect(viewModel.feedSubscriptions.first?.description == "Fresh feed description.")
    }

    @Test
    func removeFeedDeletesCachedFeed() throws {
        let subscriptionID = UUID()
        let cacheStore = InMemoryFeedCacheStore()
        let store = InMemoryConfigurationStore(
            configuration: AppConfiguration(
                feedSubscriptions: [
                    FeedSubscription(
                        id: subscriptionID,
                        title: "Cached Feed",
                        rssURL: URL(string: "https://example.com/feed.xml")!
                    )
                ]
            )
        )
        let viewModel = MainViewModel(store: store, feedCacheStore: cacheStore)
        viewModel.load()

        viewModel.removeFeeds(at: IndexSet(integer: 0))

        #expect(cacheStore.deletedSubscriptionIDs == [subscriptionID])
    }

    @Test
    func updateFeedDeletesCachedFeedWhenURLChanges() async throws {
        let subscriptionID = UUID()
        let oldURL = URL(string: "https://example.com/old.xml")!
        let newURL = URL(string: "https://example.com/new.xml")!
        let cacheStore = InMemoryFeedCacheStore()
        let store = InMemoryConfigurationStore(
            configuration: AppConfiguration(
                feedSubscriptions: [
                    FeedSubscription(
                        id: subscriptionID,
                        title: "Cached Feed",
                        rssURL: oldURL
                    )
                ]
            )
        )
        let viewModel = MainViewModel(
            store: store,
            metadataResolver: MockFeedMetadataResolver(
                summariesByURL: [
                    newURL.absoluteString: FeedSummary(subscriptionID: subscriptionID, title: "Cached Feed")
                ]
            ),
            feedCacheStore: cacheStore
        )
        viewModel.load()

        try await viewModel.updateFeed(
            from: FeedDraft(
                id: subscriptionID,
                rssURLString: newURL.absoluteString,
                currentTitle: "Cached Feed"
            )
        )

        #expect(cacheStore.deletedSubscriptionIDs == [subscriptionID])
    }
}

private final class InMemoryConfigurationStore: ConfigurationStore, @unchecked Sendable {
    var configuration: AppConfiguration = AppConfiguration()

    init(configuration: AppConfiguration = AppConfiguration()) {
        self.configuration = configuration
    }

    func loadConfiguration() throws -> AppConfiguration {
        configuration
    }

    func saveConfiguration(_ configuration: AppConfiguration) throws {
        self.configuration = configuration
    }
}

private final class InMemoryFeedCacheStore: FeedCacheStore, @unchecked Sendable {
    var deletedSubscriptionIDs: [UUID] = []

    func loadCachedFeed(for subscription: FeedSubscription) throws -> CachedFeed? {
        nil
    }

    func saveCachedFeed(_ cachedFeed: CachedFeed) throws {}

    func deleteCachedFeed(for subscriptionID: UUID) throws {
        deletedSubscriptionIDs.append(subscriptionID)
    }
}

private struct MockFeedMetadataResolver: FeedMetadataResolving {
    let summariesByURL: [String: FeedSummary]

    func resolveMetadata(for rssURL: URL, subscriptionID: UUID?) async throws -> FeedSummary {
        guard let summary = summariesByURL[rssURL.absoluteString] else {
            throw FeedServiceError.invalidResponse
        }

        return FeedSummary(
            subscriptionID: subscriptionID ?? summary.subscriptionID,
            title: summary.title,
            artworkURL: summary.artworkURL,
            description: summary.description
        )
    }
}
