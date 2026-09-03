import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

@MainActor
struct MainViewModelTests {
    @Test
    func loadReflectsStoredConfiguration() async throws {
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

        await viewModel.load()

        #expect(viewModel.hasLoadedConfiguration)
        #expect(viewModel.feedSubscriptions.count == 1)
        #expect(viewModel.settings.ffmpegExecutablePath == "/usr/local/bin/ffmpeg")
    }

    @Test
    func loadReadsConfigurationOutsideMainThread() async {
        let store = ThreadRecordingConfigurationStore()
        let viewModel = MainViewModel(store: store)

        await viewModel.load()

        #expect(store.loadMainThreadValues == [false])
    }

    @Test
    func addUpdateAndRemoveFeedPersistThroughStore() async throws {
        let store = InMemoryConfigurationStore()
        let viewModel = MainViewModel(
            store: store,
            feedResolver: MockFeedResolver(
                summariesByURL: [
                    "https://relay.fm/connected/updated-feed": FeedSummary(
                        subscriptionID: UUID(),
                        title: "Connected",
                        artworkURL: URL(string: "https://relay.fm/connected.png"),
                        description: "A show about connected things."
                    )
                ]
            )
        )

        try viewModel.addFeed(
            from: FeedDraft(
                rssURLString: "https://relay.fm/connected/feed"
            )
        )

        #expect(viewModel.feedSubscriptions.count == 1)
        #expect(store.configuration.feedSubscriptions.count == 1)
        #expect(viewModel.feedSubscriptions.first?.title == "relay.fm")

        let existingSubscription = try #require(viewModel.feedSubscriptions.first)
        try await viewModel.updateFeed(
            from: FeedDraft(
                id: existingSubscription.id,
                rssURLString: "https://relay.fm/connected/updated-feed",
                artworkURL: existingSubscription.artworkURL,
                currentTitle: existingSubscription.title,
                isEnabled: false,
                includesInAutomaticDownloads: false
            )
        )

        #expect(viewModel.feedSubscriptions.first?.title == "Connected")
        #expect(viewModel.feedSubscriptions.first?.description == "A show about connected things.")
        #expect(viewModel.feedSubscriptions.first?.isEnabled == false)
        #expect(viewModel.feedSubscriptions.first?.includesInAutomaticDownloads == false)

        viewModel.removeFeeds(at: IndexSet(integer: 0))

        #expect(viewModel.feedSubscriptions.isEmpty)
        #expect(store.configuration.feedSubscriptions.isEmpty)
    }

    @Test
    func updateFeedPreferencesDoesNotResolveUnchangedURL() async throws {
        let subscription = FeedSubscription(
            title: "Example",
            rssURL: URL(string: "https://example.com/feed.xml")!,
            artworkURL: URL(string: "https://example.com/art.png")!,
            description: "Existing description"
        )
        let store = InMemoryConfigurationStore(
            configuration: AppConfiguration(feedSubscriptions: [subscription])
        )
        let viewModel = MainViewModel(
            store: store,
            feedResolver: MockFeedResolver(summariesByURL: [:])
        )
        await viewModel.load()
        var draft = FeedDraft(subscription: subscription)
        draft.includesInAutomaticDownloads = false

        try await viewModel.updateFeed(from: draft)

        let updatedSubscription = try #require(viewModel.feedSubscriptions.first)
        #expect(!updatedSubscription.includesInAutomaticDownloads)
        #expect(updatedSubscription.title == subscription.title)
        #expect(updatedSubscription.artworkURL == subscription.artworkURL)
        #expect(updatedSubscription.description == subscription.description)
    }

    @Test
    func addFeedPersistsBeforeResolvingFeedMetadata() throws {
        let store = InMemoryConfigurationStore()
        let cacheStore = InMemoryFeedCacheStore()
        let viewModel = MainViewModel(
            store: store,
            feedResolver: MockFeedResolver(summariesByURL: [:]),
            feedCacheStore: cacheStore
        )

        let subscriptionID = try viewModel.addFeed(
            from: FeedDraft(rssURLString: "https://www.example.com/podcast.xml")
        )

        let subscription = try #require(viewModel.feedSubscriptions.first)
        #expect(subscription.id == subscriptionID)
        #expect(subscription.title == "example.com")
        #expect(subscription.rssURL.absoluteString == "https://www.example.com/podcast.xml")
        #expect(store.configuration.feedSubscriptions == [subscription])
        #expect(cacheStore.savedFeeds.isEmpty)
    }

    @Test
    func settingsMutationsPersist() throws {
        let store = InMemoryConfigurationStore()
        let viewModel = MainViewModel(store: store)

        viewModel.replaceSettings(
            AppSettings(
                ffmpegExecutablePath: "/opt/homebrew/bin/ffmpeg",
                appearancePreference: .dark,
                allowsInsecureDownloads: true,
                prefixesPublicationDateInEpisodeTitles: true,
                mp3Genre: "Spoken Word",
                automaticDownloadLimit: .latest3,
                deviceCleanupPolicy: DeviceCleanupPolicy(maximumEpisodesPerShow: 10)
            )
        )

        #expect(viewModel.settings.ffmpegExecutablePath == "/opt/homebrew/bin/ffmpeg")
        #expect(viewModel.settings.appearancePreference == .dark)
        #expect(viewModel.settings.allowsInsecureDownloads)
        #expect(viewModel.settings.prefixesPublicationDateInEpisodeTitles)
        #expect(viewModel.settings.mp3Genre == "Spoken Word")
        #expect(viewModel.settings.automaticDownloadLimit == .latest3)
        #expect(viewModel.settings.deviceCleanupPolicy == DeviceCleanupPolicy(maximumEpisodesPerShow: 10))
        #expect(store.configuration.settings == viewModel.settings)
    }

    @Test
    func importSubscriptionsPersistsNewSubscriptionsAndLeavesConflictingImportAtomic() async throws {
        let existingURL = URL(string: "https://example.com/existing.xml")!
        let newURL = URL(string: "https://example.com/new.xml")!
        let store = InMemoryConfigurationStore(
            configuration: AppConfiguration(
                feedSubscriptions: [
                    FeedSubscription(title: "Existing", rssURL: existingURL)
                ]
            )
        )
        let viewModel = MainViewModel(store: store)
        await viewModel.load()

        let addedSubscriptionIDs = try viewModel.importSubscriptions([
            OPMLSubscription(title: "New", rssURL: newURL)
        ])

        #expect(viewModel.feedSubscriptions.map(\.title) == ["Existing", "New"])
        #expect(store.configuration.feedSubscriptions.map(\.rssURL) == [existingURL, newURL])
        #expect(addedSubscriptionIDs == [viewModel.feedSubscriptions[1].id])

        #expect(throws: MainViewModelError.duplicateSubscription) {
            try viewModel.importSubscriptions([
                OPMLSubscription(title: "Another New", rssURL: URL(string: "https://example.com/another.xml")!),
                OPMLSubscription(title: "Duplicate", rssURL: existingURL),
            ])
        }
        #expect(store.configuration.feedSubscriptions.map(\.rssURL) == [existingURL, newURL])
    }

    @Test
    func rejectsDuplicateFeedAcrossCommonURLAliases() async throws {
        let existingURL = URL(string: "https://feeds.example.com/show/")!
        let store = InMemoryConfigurationStore(
            configuration: AppConfiguration(
                feedSubscriptions: [
                    FeedSubscription(title: "Existing", rssURL: existingURL)
                ]
            )
        )
        let viewModel = MainViewModel(store: store)
        await viewModel.load()

        #expect(throws: MainViewModelError.duplicateSubscription) {
            try viewModel.addFeed(
                from: FeedDraft(rssURLString: "http://feeds.example.com:80/show#episodes")
            )
        }
        #expect(store.configuration.feedSubscriptions.map(\.rssURL) == [existingURL])
    }

    @Test
    func applyFeedSummariesUpdatesStoredMetadata() async throws {
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

        await viewModel.load()
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
    func removeFeedDeletesCachedFeed() async throws {
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
        await viewModel.load()

        viewModel.removeFeeds(at: IndexSet(integer: 0))

        #expect(cacheStore.deletedSubscriptionIDs == [subscriptionID])
    }

    @Test
    func removeFeedRemovesSelectedSubscriptionEvenWhenStoredOrderDiffers() async throws {
        let alphaID = UUID()
        let zuluID = UUID()
        let cacheStore = InMemoryFeedCacheStore()
        let store = InMemoryConfigurationStore(
            configuration: AppConfiguration(
                feedSubscriptions: [
                    FeedSubscription(
                        id: zuluID,
                        title: "Zulu Podcast",
                        rssURL: URL(string: "https://example.com/zulu.xml")!
                    ),
                    FeedSubscription(
                        id: alphaID,
                        title: "Alpha Podcast",
                        rssURL: URL(string: "https://example.com/alpha.xml")!
                    ),
                ]
            )
        )
        let viewModel = MainViewModel(store: store, feedCacheStore: cacheStore)
        await viewModel.load()

        #expect(viewModel.feedSubscriptions.map(\.id) == [alphaID, zuluID])

        viewModel.removeFeeds(at: IndexSet(integer: 0))

        #expect(store.configuration.feedSubscriptions.map(\.id) == [zuluID])
        #expect(viewModel.feedSubscriptions.map(\.id) == [zuluID])
        #expect(cacheStore.deletedSubscriptionIDs == [alphaID])
    }

    @Test
    func updateFeedReplacesCachedFeedWhenURLChanges() async throws {
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
            feedResolver: MockFeedResolver(
                summariesByURL: [
                    newURL.absoluteString: FeedSummary(subscriptionID: subscriptionID, title: "Cached Feed")
                ]
            ),
            feedCacheStore: cacheStore
        )
        await viewModel.load()

        try await viewModel.updateFeed(
            from: FeedDraft(
                id: subscriptionID,
                rssURLString: newURL.absoluteString,
                currentTitle: "Cached Feed"
            )
        )

        #expect(cacheStore.savedFeeds.map(\.rssURL) == [newURL])
        #expect(cacheStore.deletedSubscriptionIDs.isEmpty)
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
    var savedFeeds: [CachedFeed] = []

    func loadCachedFeed(for subscription: FeedSubscription) throws -> CachedFeed? {
        nil
    }

    func saveCachedFeed(_ cachedFeed: CachedFeed) throws {
        savedFeeds.append(cachedFeed)
    }

    func deleteCachedFeed(for subscriptionID: UUID) throws {
        deletedSubscriptionIDs.append(subscriptionID)
    }
}

private final class ThreadRecordingConfigurationStore: ConfigurationStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []

    var loadMainThreadValues: [Bool] {
        lock.withLock { values }
    }

    func loadConfiguration() throws -> AppConfiguration {
        lock.withLock { values.append(Thread.isMainThread) }
        return AppConfiguration()
    }

    func saveConfiguration(_ configuration: AppConfiguration) throws {}
}

private struct MockFeedResolver: FeedResolving {
    let summariesByURL: [String: FeedSummary]

    func resolveFeed(for rssURL: URL, subscriptionID: UUID) async throws -> CachedFeed {
        guard let summary = summariesByURL[rssURL.absoluteString] else {
            throw FeedServiceError.invalidResponse
        }

        return CachedFeed(
            subscriptionID: subscriptionID,
            rssURL: rssURL,
            fetchedAt: Date(timeIntervalSince1970: 0),
            summary: FeedSummary(
                subscriptionID: subscriptionID,
                title: summary.title,
                artworkURL: summary.artworkURL,
                description: summary.description
            ),
            episodes: []
        )
    }
}
