import Foundation

public protocol FeedService: Sendable {
    func fetchLatestEpisodes(for subscriptions: [PodcastSubscription]) async throws -> FeedFetchResult

    func fetchLatestEpisodes(
        for subscriptions: [PodcastSubscription],
        progress: @escaping @Sendable (_ completedCount: Int, _ totalCount: Int) async -> Void
    ) async throws -> FeedFetchResult
}

public extension FeedService {
    func fetchLatestEpisodes(
        for subscriptions: [PodcastSubscription],
        progress: @escaping @Sendable (_ completedCount: Int, _ totalCount: Int) async -> Void
    ) async throws -> FeedFetchResult {
        let result = try await fetchLatestEpisodes(for: subscriptions)
        let enabledCount = subscriptions.count(where: \.isEnabled)
        await progress(enabledCount, enabledCount)
        return result
    }
}
