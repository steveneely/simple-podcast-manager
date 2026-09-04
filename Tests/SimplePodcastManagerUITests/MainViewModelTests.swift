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
                podcastSubscriptions: [
                    PodcastSubscription(title: "ATP", rssURL: URL(string: "https://atp.fm/rss")!)
                ]
            )
        )
        let viewModel = MainViewModel(store: store)

        await viewModel.load()

        #expect(viewModel.hasLoadedConfiguration)
        #expect(viewModel.podcastSubscriptions.count == 1)
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
    func addUpdateAndRemovePodcastPersistThroughStore() async throws {
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

        try viewModel.addPodcast(
            from: PodcastDraft(
                rssURLString: "https://relay.fm/connected/feed"
            )
        )

        #expect(viewModel.podcastSubscriptions.count == 1)
        #expect(store.configuration.podcastSubscriptions.count == 1)
        #expect(viewModel.podcastSubscriptions.first?.title == "relay.fm")

        let existingSubscription = try #require(viewModel.podcastSubscriptions.first)
        try await viewModel.updatePodcast(
            from: PodcastDraft(
                id: existingSubscription.id,
                rssURLString: "https://relay.fm/connected/updated-feed",
                artworkURL: existingSubscription.artworkURL,
                currentTitle: existingSubscription.title,
                isEnabled: false,
                includesInAutomaticDownloads: false
            )
        )

        #expect(viewModel.podcastSubscriptions.first?.title == "Connected")
        #expect(viewModel.podcastSubscriptions.first?.description == "A show about connected things.")
        #expect(viewModel.podcastSubscriptions.first?.isEnabled == false)
        #expect(viewModel.podcastSubscriptions.first?.includesInAutomaticDownloads == false)

        viewModel.removePodcasts(at: IndexSet(integer: 0))

        #expect(viewModel.podcastSubscriptions.isEmpty)
        #expect(store.configuration.podcastSubscriptions.isEmpty)
    }

    @Test
    func updatePodcastPreferencesDoesNotResolveUnchangedURL() async throws {
        let subscription = PodcastSubscription(
            title: "Example",
            rssURL: URL(string: "https://example.com/feed.xml")!,
            artworkURL: URL(string: "https://example.com/art.png")!,
            description: "Existing description"
        )
        let store = InMemoryConfigurationStore(
            configuration: AppConfiguration(podcastSubscriptions: [subscription])
        )
        let viewModel = MainViewModel(
            store: store,
            feedResolver: MockFeedResolver(summariesByURL: [:])
        )
        await viewModel.load()
        var draft = PodcastDraft(subscription: subscription)
        draft.includesInAutomaticDownloads = false

        try await viewModel.updatePodcast(from: draft)

        let updatedSubscription = try #require(viewModel.podcastSubscriptions.first)
        #expect(!updatedSubscription.includesInAutomaticDownloads)
        #expect(updatedSubscription.title == subscription.title)
        #expect(updatedSubscription.artworkURL == subscription.artworkURL)
        #expect(updatedSubscription.description == subscription.description)
    }

    @Test
    func addPodcastPersistsBeforeResolvingRSSMetadata() throws {
        let store = InMemoryConfigurationStore()
        let cacheStore = InMemoryFeedCacheStore()
        let viewModel = MainViewModel(
            store: store,
            feedResolver: MockFeedResolver(summariesByURL: [:]),
            feedCacheStore: cacheStore
        )

        let subscriptionID = try viewModel.addPodcast(
            from: PodcastDraft(rssURLString: "https://www.example.com/podcast.xml")
        )

        let subscription = try #require(viewModel.podcastSubscriptions.first)
        #expect(subscription.id == subscriptionID)
        #expect(subscription.title == "example.com")
        #expect(subscription.rssURL.absoluteString == "https://www.example.com/podcast.xml")
        #expect(store.configuration.podcastSubscriptions == [subscription])
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
                deviceCleanupPolicy: DeviceCleanupPolicy(maximumEpisodesPerPodcast: 10),
                podcastSortOrder: .reverseAlphabetic
            )
        )

        #expect(viewModel.settings.ffmpegExecutablePath == "/opt/homebrew/bin/ffmpeg")
        #expect(viewModel.settings.appearancePreference == .dark)
        #expect(viewModel.settings.allowsInsecureDownloads)
        #expect(viewModel.settings.prefixesPublicationDateInEpisodeTitles)
        #expect(viewModel.settings.mp3Genre == "Spoken Word")
        #expect(viewModel.settings.automaticDownloadLimit == .latest3)
        #expect(viewModel.settings.deviceCleanupPolicy == DeviceCleanupPolicy(maximumEpisodesPerPodcast: 10))
        #expect(viewModel.settings.podcastSortOrder == .reverseAlphabetic)
        #expect(store.configuration.settings == viewModel.settings)
    }

    @Test
    func importSubscriptionsPersistsNewSubscriptionsAndLeavesConflictingImportAtomic() async throws {
        let existingURL = URL(string: "https://example.com/existing.xml")!
        let newURL = URL(string: "https://example.com/new.xml")!
        let store = InMemoryConfigurationStore(
            configuration: AppConfiguration(
                podcastSubscriptions: [
                    PodcastSubscription(title: "Existing", rssURL: existingURL)
                ]
            )
        )
        let viewModel = MainViewModel(store: store)
        await viewModel.load()

        let addedSubscriptionIDs = try viewModel.importSubscriptions([
            OPMLSubscription(title: "New", rssURL: newURL)
        ])

        #expect(viewModel.podcastSubscriptions.map(\.title) == ["Existing", "New"])
        #expect(store.configuration.podcastSubscriptions.map(\.rssURL) == [existingURL, newURL])
        #expect(addedSubscriptionIDs == [viewModel.podcastSubscriptions[1].id])

        #expect(throws: MainViewModelError.duplicateSubscription) {
            try viewModel.importSubscriptions([
                OPMLSubscription(title: "Another New", rssURL: URL(string: "https://example.com/another.xml")!),
                OPMLSubscription(title: "Duplicate", rssURL: existingURL),
            ])
        }
        #expect(store.configuration.podcastSubscriptions.map(\.rssURL) == [existingURL, newURL])
    }

    @Test
    func rejectsDuplicatePodcastAcrossCommonRSSURLAliases() async throws {
        let existingURL = URL(string: "https://feeds.example.com/show/")!
        let store = InMemoryConfigurationStore(
            configuration: AppConfiguration(
                podcastSubscriptions: [
                    PodcastSubscription(title: "Existing", rssURL: existingURL)
                ]
            )
        )
        let viewModel = MainViewModel(store: store)
        await viewModel.load()

        #expect(throws: MainViewModelError.duplicateSubscription) {
            try viewModel.addPodcast(
                from: PodcastDraft(rssURLString: "http://feeds.example.com:80/show#episodes")
            )
        }
        #expect(store.configuration.podcastSubscriptions.map(\.rssURL) == [existingURL])
    }

    @Test
    func applyFeedSummariesUpdatesStoredPodcastMetadata() async throws {
        let subscriptionID = UUID(uuidString: "7B9FEA54-E516-4B39-8156-5B83D0B96768")!
        let store = InMemoryConfigurationStore(
            configuration: AppConfiguration(
                podcastSubscriptions: [
                    PodcastSubscription(
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

        #expect(viewModel.podcastSubscriptions.first?.title == "New Title")
        #expect(viewModel.podcastSubscriptions.first?.artworkURL == URL(string: "https://example.com/artwork.jpg"))
        #expect(viewModel.podcastSubscriptions.first?.description == "Fresh feed description.")
    }

    @Test
    func removePodcastDeletesCachedFeed() async throws {
        let subscriptionID = UUID()
        let cacheStore = InMemoryFeedCacheStore()
        let store = InMemoryConfigurationStore(
            configuration: AppConfiguration(
                podcastSubscriptions: [
                    PodcastSubscription(
                        id: subscriptionID,
                        title: "Cached Feed",
                        rssURL: URL(string: "https://example.com/feed.xml")!
                    )
                ]
            )
        )
        let viewModel = MainViewModel(store: store, feedCacheStore: cacheStore)
        await viewModel.load()

        viewModel.removePodcasts(at: IndexSet(integer: 0))

        #expect(cacheStore.deletedSubscriptionIDs == [subscriptionID])
    }

    @Test
    func removePodcastRemovesSelectedSubscriptionEvenWhenStoredOrderDiffers() async throws {
        let alphaID = UUID()
        let zuluID = UUID()
        let cacheStore = InMemoryFeedCacheStore()
        let store = InMemoryConfigurationStore(
            configuration: AppConfiguration(
                podcastSubscriptions: [
                    PodcastSubscription(
                        id: zuluID,
                        title: "Zulu Podcast",
                        rssURL: URL(string: "https://example.com/zulu.xml")!
                    ),
                    PodcastSubscription(
                        id: alphaID,
                        title: "Alpha Podcast",
                        rssURL: URL(string: "https://example.com/alpha.xml")!
                    ),
                ]
            )
        )
        let viewModel = MainViewModel(store: store, feedCacheStore: cacheStore)
        await viewModel.load()

        #expect(viewModel.podcastSubscriptions.map(\.id) == [alphaID, zuluID])

        viewModel.removePodcasts(at: IndexSet(integer: 0))

        #expect(store.configuration.podcastSubscriptions.map(\.id) == [zuluID])
        #expect(viewModel.podcastSubscriptions.map(\.id) == [zuluID])
        #expect(cacheStore.deletedSubscriptionIDs == [alphaID])
    }

    @Test
    func updatePodcastReplacesCachedFeedWhenURLChanges() async throws {
        let subscriptionID = UUID()
        let oldURL = URL(string: "https://example.com/old.xml")!
        let newURL = URL(string: "https://example.com/new.xml")!
        let cacheStore = InMemoryFeedCacheStore()
        let store = InMemoryConfigurationStore(
            configuration: AppConfiguration(
                podcastSubscriptions: [
                    PodcastSubscription(
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

        try await viewModel.updatePodcast(
            from: PodcastDraft(
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

    func loadCachedFeed(for subscription: PodcastSubscription) throws -> CachedFeed? {
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
