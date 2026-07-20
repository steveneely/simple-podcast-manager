import Foundation

public protocol FeedResolving: Sendable {
    func resolveFeed(for rssURL: URL, subscriptionID: UUID) async throws -> CachedFeed
}
