import Foundation

public struct RSSFeedService: FeedService {
    public let session: URLSession
    private let cacheStore: any FeedCacheStore
    private let currentDate: @Sendable () -> Date

    public init(
        session: URLSession = CachedHTTPSession.shared,
        cacheStore: any FeedCacheStore = JSONFeedCacheStore(directoryURL: JSONFeedCacheStore.defaultDirectoryURL()),
        currentDate: @escaping @Sendable () -> Date = Date.init
    ) {
        self.session = session
        self.cacheStore = cacheStore
        self.currentDate = currentDate
    }

    public func fetchLatestEpisodes(for subscriptions: [FeedSubscription]) async throws -> FeedFetchResult {
        var allEpisodes: [Episode] = []
        var selectedEpisodes: [Episode] = []
        var failures: [FeedFetchFailure] = []
        var feedSummaries: [FeedSummary] = []

        for subscription in subscriptions where subscription.isEnabled {
            let cachedFeed = try? cacheStore.loadCachedFeed(for: subscription)
            do {
                var request = URLRequest(url: subscription.rssURL)
                if let etag = cachedFeed?.etag {
                    request.setValue(etag, forHTTPHeaderField: "If-None-Match")
                }
                if let lastModified = cachedFeed?.lastModified {
                    request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
                }

                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw FeedServiceError.invalidResponse
                }

                if httpResponse.statusCode == 304, let cachedFeed {
                    append(cachedFeed, for: subscription, to: &allEpisodes, &selectedEpisodes, &feedSummaries)
                    continue
                }

                guard (200..<300).contains(httpResponse.statusCode) else {
                    throw FeedServiceError.requestFailed(statusCode: httpResponse.statusCode)
                }

                let parser = RSSFeedParser()
                let parsedFeed = try parser.parse(data: data, sourceFeedURL: subscription.rssURL, subscriptionID: subscription.id)
                allEpisodes.append(contentsOf: parsedFeed.episodes)
                let chosenEpisodes = EpisodeSelector.selectEpisodes(from: parsedFeed.episodes, for: subscription)
                selectedEpisodes.append(contentsOf: chosenEpisodes)
                let summary = FeedSummary(
                    subscriptionID: subscription.id,
                    title: parsedFeed.title,
                    artworkURL: subscription.artworkURL ?? parsedFeed.artworkURL,
                    description: parsedFeed.description
                )
                feedSummaries.append(summary)
                try? cacheStore.saveCachedFeed(
                    CachedFeed(
                        subscriptionID: subscription.id,
                        rssURL: subscription.rssURL,
                        fetchedAt: currentDate(),
                        etag: httpResponse.value(forHTTPHeaderField: "ETag"),
                        lastModified: httpResponse.value(forHTTPHeaderField: "Last-Modified"),
                        summary: summary,
                        episodes: parsedFeed.episodes
                    )
                )
            } catch {
                if let cachedFeed {
                    append(cachedFeed, for: subscription, to: &allEpisodes, &selectedEpisodes, &feedSummaries)
                    failures.append(
                        FeedFetchFailure(
                            subscriptionID: subscription.id,
                            subscriptionTitle: subscription.title,
                            message: cachedFeedFallbackMessage(for: cachedFeed, error: error)
                        )
                    )
                    continue
                }

                failures.append(
                    FeedFetchFailure(
                        subscriptionID: subscription.id,
                        subscriptionTitle: subscription.title,
                        message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    )
                )
            }
        }

        return FeedFetchResult(
            allEpisodes: allEpisodes.sorted(by: EpisodeSelector.isHigherPriority(_:than:)),
            selectedEpisodes: selectedEpisodes.sorted(by: EpisodeSelector.isHigherPriority(_:than:)),
            failures: failures,
            feedSummaries: feedSummaries
        )
    }

    private func append(
        _ cachedFeed: CachedFeed,
        for subscription: FeedSubscription,
        to allEpisodes: inout [Episode],
        _ selectedEpisodes: inout [Episode],
        _ feedSummaries: inout [FeedSummary]
    ) {
        allEpisodes.append(contentsOf: cachedFeed.episodes)
        selectedEpisodes.append(contentsOf: EpisodeSelector.selectEpisodes(from: cachedFeed.episodes, for: subscription))
        feedSummaries.append(cachedFeed.summary)
    }

    private func cachedFeedFallbackMessage(for cachedFeed: CachedFeed, error: Error) -> String {
        let cachedDate = cachedFeed.fetchedAt.formatted(date: .abbreviated, time: .omitted)
        let errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return "Could not refresh this feed. Showing saved episodes from \(cachedDate). \(errorMessage)"
    }
}
