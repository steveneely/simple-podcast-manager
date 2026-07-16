import Foundation
import Observation
import SimplePodcastManagerCore

@MainActor
@Observable
public final class FeedPreviewViewModel {
    public private(set) var allEpisodes: [Episode]
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
        self.failures = []
        self.feedSummaries = [:]
        self.isLoading = false
        self.lastErrorMessage = nil
    }

    public var hasPreviewData: Bool {
        !allEpisodes.isEmpty || !failures.isEmpty || !feedSummaries.isEmpty
    }

    public func loadCachedPreview(for subscriptions: [FeedSubscription]) {
        var cachedEpisodes: [Episode] = []
        var cachedSummaries: [FeedSummary] = []

        for subscription in subscriptions where subscription.isEnabled {
            guard let cachedFeed = try? cacheStore.loadCachedFeed(for: subscription) else {
                continue
            }

            cachedEpisodes.append(contentsOf: cachedFeed.episodes)
            cachedSummaries.append(cachedFeed.summary)
        }

        guard !cachedEpisodes.isEmpty || !cachedSummaries.isEmpty else {
            return
        }

        self.allEpisodes = cachedEpisodes.sorted(by: EpisodeSelector.isHigherPriority(_:than:))
        self.feedSummaries = Dictionary(uniqueKeysWithValues: cachedSummaries.map { ($0.subscriptionID, $0) })
    }

    public func refreshPreview(for subscriptions: [FeedSubscription]) async {
        loadCachedPreview(for: subscriptions)
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await service.fetchLatestEpisodes(for: subscriptions)
            self.allEpisodes = result.allEpisodes
            self.failures = result.failures
            self.feedSummaries = Dictionary(uniqueKeysWithValues: result.feedSummaries.map { ($0.subscriptionID, $0) })
            self.lastErrorMessage = nil
        } catch {
            self.allEpisodes = []
            self.failures = []
            self.feedSummaries = [:]
            self.lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func refreshPreview(for subscription: FeedSubscription) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await service.fetchLatestEpisodes(for: [subscription])
            replacePreviewData(for: subscription.id, with: result)
            self.lastErrorMessage = nil
        } catch {
            self.lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func artworkURL(for subscriptionID: UUID) -> URL? {
        feedSummaries[subscriptionID]?.artworkURL
    }

    public func description(for subscriptionID: UUID) -> String? {
        feedSummaries[subscriptionID]?.description
    }

    private func replacePreviewData(for subscriptionID: UUID, with result: FeedFetchResult) {
        allEpisodes.removeAll { $0.subscriptionID == subscriptionID }
        allEpisodes.append(contentsOf: result.allEpisodes)
        allEpisodes.sort(by: EpisodeSelector.isHigherPriority(_:than:))

        failures.removeAll { $0.subscriptionID == subscriptionID }
        failures.append(contentsOf: result.failures)

        for summary in result.feedSummaries {
            feedSummaries[summary.subscriptionID] = summary
        }
    }
}
