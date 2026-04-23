import Foundation

public protocol FeedService: Sendable {
    func fetchLatestEpisodes(for subscriptions: [FeedSubscription]) async throws -> FeedFetchResult
}
