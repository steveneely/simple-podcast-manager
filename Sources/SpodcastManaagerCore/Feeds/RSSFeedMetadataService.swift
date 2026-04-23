import Foundation

public struct RSSFeedMetadataService: FeedMetadataResolving {
    public let session: URLSession
    public let parserFactory: @Sendable () -> RSSFeedParser

    public init(
        session: URLSession = CachedHTTPSession.shared,
        parserFactory: @escaping @Sendable () -> RSSFeedParser = RSSFeedParser.init
    ) {
        self.session = session
        self.parserFactory = parserFactory
    }

    public func resolveMetadata(for rssURL: URL, subscriptionID: UUID?) async throws -> FeedSummary {
        let request = URLRequest(url: rssURL)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeedServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw FeedServiceError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let parser = parserFactory()
        let parsedFeed = try parser.parse(data: data, sourceFeedURL: rssURL, subscriptionID: subscriptionID)
        return FeedSummary(
            subscriptionID: subscriptionID ?? UUID(),
            title: parsedFeed.title,
            artworkURL: parsedFeed.artworkURL
        )
    }
}
