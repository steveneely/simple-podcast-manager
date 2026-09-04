import Foundation

public protocol FeedCacheStore: Sendable {
    func loadCachedFeed(for subscription: PodcastSubscription) throws -> CachedFeed?
    func saveCachedFeed(_ cachedFeed: CachedFeed) throws
    func deleteCachedFeed(for subscriptionID: UUID) throws
}
