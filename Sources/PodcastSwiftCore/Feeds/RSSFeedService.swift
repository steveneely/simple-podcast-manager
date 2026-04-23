import Foundation

public struct RSSFeedService: FeedService {
    public let session: URLSession
    public let parserFactory: @Sendable () -> RSSFeedParser

    public init(
        session: URLSession = .shared,
        parserFactory: @escaping @Sendable () -> RSSFeedParser = RSSFeedParser.init
    ) {
        self.session = session
        self.parserFactory = parserFactory
    }

    public func fetchLatestEpisodes(for subscriptions: [FeedSubscription]) async throws -> FeedFetchResult {
        var selectedEpisodes: [Episode] = []
        var failures: [FeedFetchFailure] = []

        for subscription in subscriptions where subscription.isEnabled {
            do {
                let request = URLRequest(url: subscription.rssURL)
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw FeedServiceError.invalidResponse
                }

                guard (200..<300).contains(httpResponse.statusCode) else {
                    throw FeedServiceError.requestFailed(statusCode: httpResponse.statusCode)
                }

                let parser = parserFactory()
                let parsedFeed = try parser.parse(data: data, sourceFeedURL: subscription.rssURL, subscriptionID: subscription.id)
                let chosenEpisodes = EpisodeSelector.selectEpisodes(from: parsedFeed.episodes, for: subscription)
                selectedEpisodes.append(contentsOf: chosenEpisodes)
            } catch {
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
            selectedEpisodes: selectedEpisodes.sorted(by: EpisodeSelector.isHigherPriority(_:than:)),
            failures: failures
        )
    }
}
