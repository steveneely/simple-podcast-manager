import Foundation
import Observation
import SimplePodcastManagerCore

@MainActor
@Observable
public final class FeedPreviewViewModel {
    public private(set) var allEpisodes: [Episode]
    public private(set) var selectedEpisodes: [Episode]
    public private(set) var failures: [FeedFetchFailure]
    public private(set) var feedSummaries: [UUID: FeedSummary]
    public private(set) var isLoading: Bool
    public private(set) var lastErrorMessage: String?

    private let service: any FeedService
    private let cacheStore: any FeedCacheStore

    public init(
        service: any FeedService = RSSFeedService(),
        cacheStore: any FeedCacheStore = JSONFeedCacheStore(directoryURL: JSONFeedCacheStore.defaultDirectoryURL())
    ) {
        self.service = service
        self.cacheStore = cacheStore
        self.allEpisodes = []
        self.selectedEpisodes = []
        self.failures = []
        self.feedSummaries = [:]
        self.isLoading = false
        self.lastErrorMessage = nil
    }

    public var hasPreviewData: Bool {
        !allEpisodes.isEmpty || !selectedEpisodes.isEmpty || !failures.isEmpty || !feedSummaries.isEmpty
    }

    public func loadCachedPreview(for subscriptions: [FeedSubscription]) {
        var cachedEpisodes: [Episode] = []
        var cachedSelectedEpisodes: [Episode] = []
        var cachedSummaries: [FeedSummary] = []

        for subscription in subscriptions where subscription.isEnabled {
            guard let cachedFeed = try? cacheStore.loadCachedFeed(for: subscription) else {
                continue
            }

            cachedEpisodes.append(contentsOf: cachedFeed.episodes)
            cachedSelectedEpisodes.append(contentsOf: EpisodeSelector.selectEpisodes(from: cachedFeed.episodes, for: subscription))
            cachedSummaries.append(cachedFeed.summary)
        }

        guard !cachedEpisodes.isEmpty || !cachedSelectedEpisodes.isEmpty || !cachedSummaries.isEmpty else {
            return
        }

        self.allEpisodes = cachedEpisodes.sorted(by: EpisodeSelector.isHigherPriority(_:than:))
        self.selectedEpisodes = cachedSelectedEpisodes.sorted(by: EpisodeSelector.isHigherPriority(_:than:))
        self.feedSummaries = Dictionary(uniqueKeysWithValues: cachedSummaries.map { ($0.subscriptionID, $0) })
    }

    public func refreshPreview(for subscriptions: [FeedSubscription]) async {
        loadCachedPreview(for: subscriptions)
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await service.fetchLatestEpisodes(for: subscriptions)
            self.allEpisodes = result.allEpisodes
            self.selectedEpisodes = result.selectedEpisodes
            self.failures = result.failures
            self.feedSummaries = Dictionary(uniqueKeysWithValues: result.feedSummaries.map { ($0.subscriptionID, $0) })
            self.lastErrorMessage = nil
        } catch {
            self.allEpisodes = []
            self.selectedEpisodes = []
            self.failures = []
            self.feedSummaries = [:]
            self.lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func artworkURL(for subscriptionID: UUID) -> URL? {
        feedSummaries[subscriptionID]?.artworkURL
    }

    public func description(for subscriptionID: UUID) -> String? {
        feedSummaries[subscriptionID]?.description
    }
}
