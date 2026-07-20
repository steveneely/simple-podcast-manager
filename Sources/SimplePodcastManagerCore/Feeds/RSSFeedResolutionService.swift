import Foundation

public struct RSSFeedResolutionService: FeedResolving {
    private let session: any HTTPDataLoading
    private let currentDate: @Sendable () -> Date

    public init(
        session: any HTTPDataLoading = CachedHTTPSession.shared,
        currentDate: @escaping @Sendable () -> Date = Date.init
    ) {
        self.session = session
        self.currentDate = currentDate
    }

    public func resolveFeed(for rssURL: URL, subscriptionID: UUID) async throws -> CachedFeed {
        let (data, response) = try await session.data(for: URLRequest(url: rssURL))

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeedServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw FeedServiceError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let parsedFeed = try RSSFeedParser().parse(
            data: data,
            sourceFeedURL: rssURL,
            subscriptionID: subscriptionID
        )
        let summary = FeedSummary(
            subscriptionID: subscriptionID,
            title: parsedFeed.title,
            artworkURL: parsedFeed.artworkURL,
            description: parsedFeed.description
        )

        return CachedFeed(
            subscriptionID: subscriptionID,
            rssURL: rssURL,
            fetchedAt: currentDate(),
            etag: httpResponse.value(forHTTPHeaderField: "ETag"),
            lastModified: httpResponse.value(forHTTPHeaderField: "Last-Modified"),
            summary: summary,
            episodes: parsedFeed.episodes
        )
    }
}
