import Foundation

public protocol FeedService: Sendable {
    func fetchLatestEpisodes(for subscriptions: [PodcastSubscription]) async throws -> FeedFetchResult
}
