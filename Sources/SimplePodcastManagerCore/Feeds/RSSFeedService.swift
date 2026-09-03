import Foundation

public struct RSSFeedService: FeedService {
    public let session: any HTTPDataLoading
    private let cacheStore: any FeedCacheStore
    private let currentDate: @Sendable () -> Date
    private let maximumConcurrentRefreshes: Int

    public init(
        session: any HTTPDataLoading = CachedHTTPSession.shared,
        cacheStore: any FeedCacheStore = JSONFeedCacheStore(directoryURL: JSONFeedCacheStore.defaultDirectoryURL()),
        currentDate: @escaping @Sendable () -> Date = Date.init,
        maximumConcurrentRefreshes: Int = 4
    ) {
        self.session = session
        self.cacheStore = cacheStore
        self.currentDate = currentDate
        self.maximumConcurrentRefreshes = max(1, maximumConcurrentRefreshes)
    }

    public func fetchLatestEpisodes(for subscriptions: [FeedSubscription]) async throws -> FeedFetchResult {
        let enabledSubscriptions = subscriptions.filter(\.isEnabled)
        var nextSubscriptionIndex = 0
        var outcomes: [SubscriptionFetchOutcome] = []

        await withTaskGroup(of: SubscriptionFetchOutcome.self) { group in
            func startNextRefreshIfNeeded() {
                guard nextSubscriptionIndex < enabledSubscriptions.count else { return }

                let index = nextSubscriptionIndex
                let subscription = enabledSubscriptions[index]
                nextSubscriptionIndex += 1
                group.addTask {
                    SubscriptionFetchOutcome(
                        index: index,
                        result: await fetchLatestEpisodes(for: subscription)
                    )
                }
            }

            for _ in 0..<min(maximumConcurrentRefreshes, enabledSubscriptions.count) {
                startNextRefreshIfNeeded()
            }

            while let outcome = await group.next() {
                outcomes.append(outcome)
                startNextRefreshIfNeeded()
            }
        }

        let orderedResults = outcomes.sorted { $0.index < $1.index }.map(\.result)
        let allEpisodes = orderedResults.flatMap(\.allEpisodes)
        let failures = orderedResults.flatMap(\.failures)
        let feedSummaries = orderedResults.flatMap(\.feedSummaries)

        return FeedFetchResult(
            allEpisodes: allEpisodes.sorted(by: EpisodeSelector.isHigherPriority(_:than:)),
            failures: failures,
            feedSummaries: feedSummaries
        )
    }

    private func fetchLatestEpisodes(for subscription: FeedSubscription) async -> FeedFetchResult {
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
                return result(from: cachedFeed)
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                throw FeedServiceError.requestFailed(statusCode: httpResponse.statusCode)
            }

            let parsedFeed = try RSSFeedParser().parse(
                data: data,
                sourceFeedURL: subscription.rssURL,
                subscriptionID: subscription.id
            )
            let summary = FeedSummary(
                subscriptionID: subscription.id,
                title: parsedFeed.title,
                artworkURL: subscription.artworkURL ?? parsedFeed.artworkURL,
                description: parsedFeed.description
            )
            let failures = parsedFeed.itemCount > 0 && parsedFeed.episodes.isEmpty
                ? [
                    FeedFetchFailure(
                        subscriptionID: subscription.id,
                        subscriptionTitle: subscription.title,
                        message: "This RSS feed has posts, but no downloadable audio episodes. Use the podcast RSS feed URL instead."
                    )
                ]
                : []

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

            return FeedFetchResult(
                allEpisodes: parsedFeed.episodes,
                failures: failures,
                feedSummaries: [summary]
            )
        } catch {
            if let cachedFeed {
                var result = result(from: cachedFeed)
                result.failures = [
                    FeedFetchFailure(
                        subscriptionID: subscription.id,
                        subscriptionTitle: subscription.title,
                        message: cachedFeedFallbackMessage(for: cachedFeed, error: error)
                    )
                ]
                return result
            }

            return FeedFetchResult(
                failures: [
                    FeedFetchFailure(
                        subscriptionID: subscription.id,
                        subscriptionTitle: subscription.title,
                        message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    )
                ]
            )
        }
    }

    private func result(from cachedFeed: CachedFeed) -> FeedFetchResult {
        FeedFetchResult(
            allEpisodes: cachedFeed.episodes.map(PublicationDateNormalizer.normalize),
            feedSummaries: [cachedFeed.summary]
        )
    }

    private func cachedFeedFallbackMessage(for cachedFeed: CachedFeed, error: Error) -> String {
        let cachedDate = cachedFeed.fetchedAt.formatted(date: .abbreviated, time: .omitted)
        let errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return "Could not refresh this feed. Showing saved episodes from \(cachedDate). \(errorMessage)"
    }
}

private struct SubscriptionFetchOutcome: Sendable {
    var index: Int
    var result: FeedFetchResult
}
