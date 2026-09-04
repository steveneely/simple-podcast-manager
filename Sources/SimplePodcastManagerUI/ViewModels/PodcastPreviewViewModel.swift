import Foundation
import Observation
import SimplePodcastManagerCore

@MainActor
@Observable
public final class PodcastPreviewViewModel {
    public private(set) var allEpisodes: [Episode]
    public private(set) var failures: [FeedFetchFailure]
    public private(set) var feedSummaries: [UUID: FeedSummary]
    public private(set) var isLoading: Bool
    public private(set) var lastErrorMessage: String?

    private let service: any FeedService
    private let cacheStore: any FeedCacheStore
    private var episodesBySubscriptionID: [UUID: [Episode]]
    private var failuresBySubscriptionID: [UUID: [FeedFetchFailure]]

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
        self.episodesBySubscriptionID = [:]
        self.failuresBySubscriptionID = [:]
    }

    public var hasPreviewData: Bool {
        !allEpisodes.isEmpty || !failures.isEmpty || !feedSummaries.isEmpty
    }

    public func loadCachedPreview(for subscriptions: [PodcastSubscription]) async {
        let cacheStore = self.cacheStore
        let enabledSubscriptions = subscriptions.filter(\.isEnabled)
        let cachedFeeds = await Task.detached(priority: .userInitiated) {
            enabledSubscriptions.compactMap { try? cacheStore.loadCachedFeed(for: $0) }
        }.value

        self.allEpisodes = cachedFeeds.flatMap(\.episodes).sorted(by: EpisodeSelector.isHigherPriority(_:than:))
        self.feedSummaries = Dictionary(uniqueKeysWithValues: cachedFeeds.map { ($0.summary.subscriptionID, $0.summary) })
        self.failures = []
        rebuildIndexes()
    }

    public func refreshPreview(for subscriptions: [PodcastSubscription]) async {
        await loadCachedPreview(for: subscriptions)
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await service.fetchLatestEpisodes(for: subscriptions)
            self.allEpisodes = result.allEpisodes
            self.failures = result.failures
            self.feedSummaries = Dictionary(uniqueKeysWithValues: result.feedSummaries.map { ($0.subscriptionID, $0) })
            self.lastErrorMessage = nil
            rebuildIndexes()
        } catch {
            self.allEpisodes = []
            self.failures = []
            self.feedSummaries = [:]
            self.lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            rebuildIndexes()
        }
    }

    public func refreshPreview(for subscription: PodcastSubscription) async {
        await refreshPreview(forNewSubscriptions: [subscription])
    }

    public func refreshPreview(forNewSubscriptions subscriptions: [PodcastSubscription]) async {
        guard !subscriptions.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await service.fetchLatestEpisodes(for: subscriptions)
            replacePreviewData(for: Set(subscriptions.map(\.id)), with: result)
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

    public func episodes(for subscriptionID: UUID) -> [Episode] {
        episodesBySubscriptionID[subscriptionID] ?? []
    }

    public func failures(for subscriptionID: UUID) -> [FeedFetchFailure] {
        failuresBySubscriptionID[subscriptionID] ?? []
    }

    private func replacePreviewData(for subscriptionIDs: Set<UUID>, with result: FeedFetchResult) {
        allEpisodes.removeAll { episode in
            episode.subscriptionID.map(subscriptionIDs.contains) ?? false
        }
        allEpisodes.append(contentsOf: result.allEpisodes)
        allEpisodes.sort(by: EpisodeSelector.isHigherPriority(_:than:))

        failures.removeAll { subscriptionIDs.contains($0.subscriptionID) }
        failures.append(contentsOf: result.failures)

        for summary in result.feedSummaries {
            feedSummaries[summary.subscriptionID] = summary
        }
        rebuildIndexes()
    }

    private func rebuildIndexes() {
        episodesBySubscriptionID = Dictionary(grouping: allEpisodes.compactMap { episode in
            episode.subscriptionID.map { ($0, episode) }
        }, by: \.0).mapValues { $0.map(\.1) }
        failuresBySubscriptionID = Dictionary(grouping: failures, by: \.subscriptionID)
    }
}
